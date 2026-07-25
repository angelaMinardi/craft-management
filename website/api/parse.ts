// Vercel Serverless Function — POST /api/parse
//
// Web companion to Corvid Craft's pattern parser. Takes a craft pattern and
// structures it into trackable, row-by-row steps + metadata.
//
// Accepts either:
//   • A PDF upload  — Content-Type: application/pdf, raw bytes in the body
//   • Pasted text   — Content-Type: application/json, body: { "text": "..." }
//
// Pipeline: extract text (unpdf for PDFs) → Gemini 2.5 Flash structured
// extraction → JSON. Mirrors the app's enrich-pattern Edge Function so the
// web tool and the iOS app behave consistently.
//
// Requires the GEMINI_API_KEY environment variable (set it in the Vercel
// project's Environment Variables — reuse the same key the app uses).

import { extractText, getDocumentProxy } from "unpdf";

// `process` is provided by the Vercel Node runtime; declare it so type-checking
// passes without adding @types/node as a dependency.
declare const process: { env: Record<string, string | undefined> };

// Allow up to 60s — PDF text extraction + a Gemini call can exceed the 10s default.
export const config = { maxDuration: 60 };

const GEMINI_MODEL = "gemini-2.5-flash";
const MAX_PDF_BYTES = 15 * 1024 * 1024; // 15 MB
const MAX_CONTENT_CHARS = 60_000; // keep token cost predictable

// --- Abuse / cost controls (AUDIT.md P1-3) ---
// This endpoint calls Gemini on every request and has no user auth, so without
// guards anyone can loop it and bill GEMINI_API_KEY. Two cheap, dependency-free
// defenses: (1) only accept requests that originate from our own site, and
// (2) a best-effort per-IP rate limit. The rate limit is in-memory and therefore
// per-instance — a soft cap, not a guarantee. Durable limiting needs Vercel KV /
// Upstash; add that before promoting this tool widely.
const ALLOWED_ORIGIN_HOSTS = new Set([
  "corvidcraft.com",
  "www.corvidcraft.com",
  "localhost",
  "127.0.0.1",
]);
const RATE_LIMIT_MAX = 10; // requests per window per IP
const RATE_LIMIT_WINDOW_MS = 60_000; // 1 minute
const recentHits = new Map<string, number[]>();

function isAllowedOrigin(request: Request): boolean {
  // Browser fetches from our pages send Origin and/or Referer; drive-by curl/bots
  // usually send neither. Preview deploys on *.vercel.app are allowed too.
  const candidates = [
    request.headers.get("origin"),
    request.headers.get("referer"),
  ].filter((v): v is string => Boolean(v));
  if (candidates.length === 0) return false;
  for (const c of candidates) {
    try {
      const host = new URL(c).hostname.toLowerCase();
      if (ALLOWED_ORIGIN_HOSTS.has(host) || host.endsWith(".vercel.app")) return true;
    } catch {
      /* malformed header — ignore */
    }
  }
  return false;
}

function isRateLimited(request: Request): boolean {
  const ip =
    (request.headers.get("x-forwarded-for") || "").split(",")[0].trim() ||
    request.headers.get("x-real-ip") ||
    "unknown";
  const now = Date.now();
  const recent = (recentHits.get(ip) || []).filter((t) => now - t < RATE_LIMIT_WINDOW_MS);
  recent.push(now);
  recentHits.set(ip, recent);
  if (recentHits.size > 5000) {
    for (const [key, times] of recentHits) {
      if (times.every((t) => now - t >= RATE_LIMIT_WINDOW_MS)) recentHits.delete(key);
    }
  }
  return recent.length > RATE_LIMIT_MAX;
}

interface ParsedStep {
  section: string;
  start_row: number;
  end_row: number;
  instruction: string;
  stitch_count?: number | null;
  note?: string | null;
}

interface ParseResult {
  title?: string;
  summary?: string;
  craft_type?: string | null;
  difficulty?: string | null;
  materials?: string | null;
  gauge?: string | null;
  needle_hook_sizes?: string | null;
  yarn_weight_yardage?: string | null;
  techniques?: string | null;
  tags?: string[];
  steps?: ParsedStep[];
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
}

function buildPrompt(content: string): string {
  return `You are a craft pattern analyzer. The pattern can be ANY craft: knitting, crochet, sewing, leatherworking, beading, jewelry, weaving, embroidery, paper craft, woodworking, etc. Extract structured information appropriate to the craft. Respond ONLY with valid JSON, no markdown fences.

Analyze this craft pattern and extract the following as JSON:
{
  "title": "a short, catchy name for this pattern (2-5 words). NOT the file/webpage title. Never include 'FREE', 'pattern', or website names.",
  "summary": "2-3 sentence plain-language description of what you make and how.",
  "tags": ["craft type", "garment/item type", "technique", "season/occasion"],
  "craft_type": "knitting/crochet/sewing/etc or null",
  "difficulty": "beginner/intermediate/advanced or null",
  "materials": "brief materials summary or null",
  "gauge": "e.g. 22 sts x 30 rows = 4 in stockinette, or null",
  "needle_hook_sizes": "e.g. US 7 (4.5 mm), or null",
  "yarn_weight_yardage": "e.g. Worsted; 800 yd, or null",
  "techniques": "comma-separated skills, or null",
  "steps": [{"section": "Brim", "start_row": 1, "end_row": 1, "instruction": "full unmodified instruction text", "stitch_count": null, "note": null}]
}

STEPS: Extract every individual working instruction organized by section, with row/round numbers.
Each step: section (1-4 words), start_row/end_row (from the text; when instructions are clearly sequential within a section but lack explicit row labels, assign sequential numbers starting at 1; use 0 only for setup/transition instructions that are not distinct rows), instruction (complete and unmodified), stitch_count (integer or null), note (or null).
Omit materials/gauge/abbreviation lists from steps. Return [] if no real working instructions exist.
Order steps in the order a maker would work them.

CONTENT TO ANALYZE:
${content}`;
}

async function extractPdfText(bytes: Uint8Array): Promise<string> {
  const pdf = await getDocumentProxy(bytes);
  const { text } = await extractText(pdf, { mergePages: true });
  const joined = Array.isArray(text) ? text.join("\n") : text;
  return (joined || "").replace(/\u0000/g, "").trim();
}

// Last-resort recovery for a Gemini response truncated at the output-token limit.
function repairTruncatedJSON(text: string): ParseResult | null {
  let json = text.trim();
  if (json.startsWith("```")) {
    json = json.replace(/^```json?\s*/, "").replace(/\s*```$/, "").trim();
  }
  try {
    return JSON.parse(json) as ParseResult;
  } catch {
    /* fall through to brace-balancing repair */
  }

  const stack: string[] = [];
  let inString = false;
  let prev = " ";
  for (const char of json) {
    if (inString) {
      if (char === '"' && prev !== "\\") inString = false;
    } else if (char === '"') inString = true;
    else if (char === "{") stack.push("}");
    else if (char === "[") stack.push("]");
    else if ((char === "}" || char === "]") && stack.length) stack.pop();
    prev = char;
  }
  if (inString) json += '"';
  json = json.replace(/,\s*$/, "");
  json += stack.reverse().join("");

  try {
    return JSON.parse(json) as ParseResult;
  } catch {
    return null;
  }
}

async function callGemini(content: string, apiKey: string): Promise<ParseResult | null> {
  const requestBody = {
    contents: [{ parts: [{ text: buildPrompt(content) }] }],
    generationConfig: {
      responseMimeType: "application/json",
      maxOutputTokens: 65536,
      temperature: 0.1,
      // thinkingBudget kept small: thinking tokens eat the output budget and
      // truncate the JSON (see CLAUDE.md Gemini gotchas).
      thinkingConfig: { thinkingBudget: 1024 },
    },
  };

  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": apiKey },
      body: JSON.stringify(requestBody),
    }
  );

  if (!res.ok) {
    console.error(`Gemini API error: ${res.status} ${res.statusText}`);
    return null;
  }

  const data = (await res.json()) as Record<string, unknown>;
  const candidates = data.candidates as Array<Record<string, unknown>> | undefined;
  if (!candidates?.length) {
    console.error("Gemini returned no candidates", JSON.stringify(data).slice(0, 500));
    return null;
  }

  const parts = (candidates[0].content as Record<string, unknown>)?.parts as
    | Array<Record<string, unknown>>
    | undefined;
  if (!parts?.length) return null;

  const outputPart = [...parts]
    .reverse()
    .find((p) => p.thought !== true && typeof p.text === "string");
  if (!outputPart?.text) return null;

  let text = (outputPart.text as string).trim();
  if (text.startsWith("```")) {
    text = text.replace(/^```json?\s*/, "").replace(/\s*```$/, "").trim();
  }

  try {
    return JSON.parse(text) as ParseResult;
  } catch {
    return repairTruncatedJSON(text);
  }
}

export async function POST(request: Request): Promise<Response> {
  if (!isAllowedOrigin(request)) {
    return json(
      { error: "This parser can only be used from the Corvid Craft website." },
      403
    );
  }
  if (isRateLimited(request)) {
    return json(
      { error: "You're going a bit fast — please wait a minute and try again." },
      429
    );
  }

  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    return json(
      { error: "The parser isn't configured yet (missing GEMINI_API_KEY)." },
      500
    );
  }

  const contentType = request.headers.get("content-type") || "";
  let content = "";
  let source: "pdf" | "text" = "text";

  try {
    if (contentType.includes("application/pdf")) {
      const buf = await request.arrayBuffer();
      if (buf.byteLength === 0) return json({ error: "That upload was empty." }, 400);
      if (buf.byteLength > MAX_PDF_BYTES)
        return json({ error: "PDF is too large (15 MB max)." }, 413);
      content = await extractPdfText(new Uint8Array(buf));
      source = "pdf";
    } else if (contentType.includes("application/json")) {
      const body = (await request.json().catch(() => null)) as { text?: string } | null;
      content = (body?.text || "").trim();
      source = "text";
    } else {
      return json(
        { error: "Send a PDF (application/pdf) or JSON { text }." },
        415
      );
    }
  } catch {
    return json({ error: "Couldn't read that file. Is it a valid PDF?" }, 400);
  }

  if (content.length < 40) {
    return json(
      {
        error:
          source === "pdf"
            ? "Couldn't pull readable text from that PDF — it may be image-only or scanned. Try pasting the pattern text instead."
            : "Please paste a bit more pattern text to parse.",
      },
      422
    );
  }

  content = content.slice(0, MAX_CONTENT_CHARS);

  let result: ParseResult | null = null;
  try {
    result = await callGemini(content, apiKey);
  } catch (err) {
    console.error("Gemini call threw", err);
  }

  if (!result || !result.title) {
    return json(
      { error: "The parser couldn't make sense of this one. Try a different pattern." },
      502
    );
  }

  // Normalize steps so the client can render without guarding every field.
  const steps: ParsedStep[] = Array.isArray(result.steps)
    ? result.steps
        .filter((s) => s && typeof s.instruction === "string" && s.instruction.trim().length > 0)
        .map((s) => ({
          section: (s.section || "Steps").toString().trim() || "Steps",
          start_row: Number.isFinite(s.start_row) ? Number(s.start_row) : 0,
          end_row: Number.isFinite(s.end_row) ? Number(s.end_row) : 0,
          instruction: s.instruction.trim(),
          stitch_count:
            typeof s.stitch_count === "number" ? s.stitch_count : null,
          note: typeof s.note === "string" && s.note.trim() ? s.note.trim() : null,
        }))
    : [];

  return json({
    title: result.title,
    summary: result.summary ?? null,
    craft_type: result.craft_type ?? null,
    difficulty: result.difficulty ?? null,
    materials: result.materials ?? null,
    gauge: result.gauge ?? null,
    needle_hook_sizes: result.needle_hook_sizes ?? null,
    yarn_weight_yardage: result.yarn_weight_yardage ?? null,
    techniques: result.techniques ?? null,
    tags: Array.isArray(result.tags) ? result.tags.slice(0, 8) : [],
    steps,
    meta: { source, chars: content.length },
  });
}
