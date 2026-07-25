// Supabase Edge Function: enrich-pattern
// POST body: { pattern_id: string }. Requires Authorization: Bearer <user JWT>.
// Reads the pattern row, runs Gemini AI analysis on source_content or fetched page text,
// and updates the pattern with enriched metadata + cleaned content.
// Requires: GEMINI_API_KEY secret.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

interface EnrichRequest {
  pattern_id: string;
}

interface GeminiResult {
  title?: string;
  summary?: string;
  tags?: string[];
  craft_type?: string;
  difficulty?: string;
  materials?: string;
  cleaned_content?: string;
  video_url?: string;
  gauge?: string;
  needle_hook_sizes?: string;
  yarn_weight_yardage?: string;
  techniques?: string;
  instructions?: Array<Record<string, unknown>>;
  steps?: Array<{ title: string; body: string }>;
  yarn_links?: Array<{
    brand_name: string;
    official_url?: string;
    store_url?: string;
  }>;
}

const GEMINI_MODEL = "gemini-2.5-flash";

// SSRF guard: source_url is user-controlled and the fetched body is returned to
// the user via cleaned_content, so refuse non-http(s) schemes and hosts in
// private / loopback / link-local / cloud-metadata ranges. See AUDIT.md P1-1.
function isBlockedHost(hostname: string): boolean {
  const host = hostname.toLowerCase().replace(/^\[|\]$/g, ""); // strip IPv6 brackets
  if (
    host === "localhost" ||
    host === "metadata.google.internal" ||
    host.endsWith(".local") ||
    host.endsWith(".internal")
  ) {
    return true;
  }
  // IPv6 loopback / link-local (fe80::/10) / unique-local (fc00::/7)
  if (host === "::1" || host.startsWith("fe80:") || host.startsWith("fc") || host.startsWith("fd")) {
    return true;
  }
  // IPv4 literals
  const m = host.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/);
  if (m) {
    const a = Number(m[1]);
    const b = Number(m[2]);
    if (a === 0 || a === 10 || a === 127) return true; // this-network / 10/8 / loopback
    if (a === 169 && b === 254) return true; // link-local incl. 169.254.169.254 metadata
    if (a === 172 && b >= 16 && b <= 31) return true; // 172.16/12
    if (a === 192 && b === 168) return true; // 192.168/16
    if (a === 100 && b >= 64 && b <= 127) return true; // CGNAT 100.64/10
    if (a >= 224) return true; // multicast / reserved
  }
  return false;
}

// Follows redirects manually so every hop is validated against isBlockedHost —
// `redirect: "follow"` would let a public URL bounce to an internal address.
async function safeFetch(rawUrl: string, maxRedirects = 3): Promise<Response | null> {
  let current = rawUrl;
  for (let hop = 0; hop <= maxRedirects; hop++) {
    let parsed: URL;
    try {
      parsed = new URL(current);
    } catch {
      return null;
    }
    if (parsed.protocol !== "http:" && parsed.protocol !== "https:") return null;
    if (isBlockedHost(parsed.hostname)) return null;

    const res = await fetch(current, {
      headers: {
        "User-Agent":
          "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        Accept:
          "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      },
      redirect: "manual",
    });

    if (res.status >= 300 && res.status < 400) {
      const location = res.headers.get("location");
      if (!location) return res;
      current = new URL(location, current).toString(); // resolve relative redirects
      continue;
    }
    return res;
  }
  return null; // too many redirects
}

async function fetchWebPageText(url: string): Promise<string | null> {
  if (!url) return null;
  try {
    const res = await safeFetch(url);
    if (!res || !res.ok) return null;
    const html = await res.text();

    const ogTitle = html.match(
      /<meta[^>]*property="og:title"[^>]*content="([^"]*)"[^>]*>/i
    )?.[1];
    const ogDesc = html.match(
      /<meta[^>]*property="og:description"[^>]*content="([^"]*)"[^>]*>/i
    )?.[1];

    let text = html
      .replace(/<script[^>]*>[\s\S]*?<\/script>/gi, "")
      .replace(/<style[^>]*>[\s\S]*?<\/style>/gi, "")
      .replace(/<nav[^>]*>[\s\S]*?<\/nav>/gi, "")
      .replace(/<footer[^>]*>[\s\S]*?<\/footer>/gi, "")
      .replace(/<header[^>]*>[\s\S]*?<\/header>/gi, "")
      .replace(/<[^>]+>/g, "\n")
      .replace(/&nbsp;/gi, " ")
      .replace(/&amp;/gi, "&")
      .replace(/&lt;/gi, "<")
      .replace(/&gt;/gi, ">")
      .replace(/&#39;/gi, "'")
      .replace(/&quot;/gi, '"');

    text = text
      .split("\n")
      .map((l) => l.trim())
      .filter((l) => l.length > 0)
      .join("\n");

    const parts: string[] = [];
    if (ogTitle) parts.push(`Page title: ${ogTitle}`);
    if (ogDesc) parts.push(`Page description: ${ogDesc}`);
    if (text.length > 0) parts.push(`Page content: ${text.slice(0, 12000)}`);
    return parts.join("\n\n") || null;
  } catch {
    return null;
  }
}

function buildGeminiPrompt(content: string, sourceUrl: string): string {
  return `You are a craft pattern analyzer. The pattern can be ANY craft: knitting, crochet, sewing, leatherworking, beading, jewelry, weaving, embroidery, paper craft, woodworking, etc. Extract structured information appropriate to the craft. Respond ONLY with valid JSON, no markdown fences. Output the short metadata fields first (title, summary, tags, craft_type, etc.), then instructions, then cleaned_content LAST.

Analyze this craft pattern and extract the following as JSON:
{
  "title": "a short, catchy name for this pattern (2-5 words)",
  "summary": "2-3 sentence description",
  "tags": ["tag1", "tag2"],
  "craft_type": "knitting/crochet/sewing/etc or null",
  "difficulty": "beginner/intermediate/advanced or null",
  "materials": "brief materials summary or null",
  "video_url": "tutorial URL from the page, or null",
  "gauge": "e.g. 22 sts x 30 rows = 4 in stockinette, or null",
  "needle_hook_sizes": "e.g. US 7 (4.5 mm), or null",
  "yarn_weight_yardage": "e.g. Worsted; 800 yd, or null",
  "techniques": "comma-separated skills, or null",
  "yarn_links": [{"brand_name": "Brand name", "official_url": "or null", "store_url": "or null"}],
  "instructions": [{"section": "Toe", "start_row": 0, "end_row": 0, "instruction": "full text", "stitch_count": null, "note": null}],
  "cleaned_content": "the relevant pattern content only — OUTPUT THIS FIELD LAST"
}

YARN_LINKS: For fiber crafts use yarn brand names. For other crafts use supplier names. Max 8.

INSTRUCTIONS: Extract every individual working instruction organized by section with row/round numbers.
Each: section (1-4 words), start_row/end_row (from text; when instructions are clearly sequential within a section but lack explicit row labels, assign sequential numbers starting at 1; use 0 only for setup/transition instructions that are not distinct rows), instruction (complete, unmodified), stitch_count (int or null), note (or null).
Omit materials/gauge/abbreviations from instructions. Return [] if no real instructions exist.

TITLE: Create a cute, memorable name. NOT the webpage title. 2-5 words. Never include "FREE", "pattern", website names.
Tags: craft type, garment type, technique, season/occasion. Max 6.
CLEANED_CONTENT: Start from first substantive section. Omit intro. Keep materials, gauge, sizing tables, construction notes. Stop at last instruction. Remove nav/ads/SEO. Use \\n\\n for paragraphs.

Source URL: ${sourceUrl}

Content:
${content}`;
}

async function analyzeWithGemini(
  content: string,
  sourceUrl: string,
  apiKey: string
): Promise<GeminiResult | null> {
  const prompt = buildGeminiPrompt(content, sourceUrl);

  const requestBody = {
    contents: [{ parts: [{ text: prompt }] }],
    generationConfig: {
      responseMimeType: "application/json",
      maxOutputTokens: 65536,
      temperature: 0.1,
      thinkingConfig: { thinkingBudget: 1024 },
    },
  };

  try {
    const res = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-goog-api-key": apiKey,
        },
        body: JSON.stringify(requestBody),
      }
    );

    if (!res.ok) {
      console.error(`Gemini API error: ${res.status} ${res.statusText}`);
      return null;
    }
    const data = (await res.json()) as Record<string, unknown>;
    const candidates = data.candidates as Array<Record<string, unknown>>;
    if (!candidates?.length) {
      console.error("Gemini returned no candidates", JSON.stringify(data).slice(0, 500));
      return null;
    }

    const parts = (candidates[0].content as Record<string, unknown>)
      ?.parts as Array<Record<string, unknown>>;
    if (!parts?.length) return null;

    const outputPart = parts
      .reverse()
      .find((p) => p.thought !== true && typeof p.text === "string");
    if (!outputPart?.text) return null;

    let text = (outputPart.text as string).trim();
    if (text.startsWith("```")) {
      text = text
        .replace(/^```json?\s*/, "")
        .replace(/\s*```$/, "")
        .trim();
    }

    try {
      return JSON.parse(text) as GeminiResult;
    } catch {
      const repaired = repairTruncatedJSON(text);
      return repaired;
    }
  } catch {
    return null;
  }
}

function repairTruncatedJSON(text: string): GeminiResult | null {
  let json = text.trim();
  if (json.startsWith("```")) {
    json = json
      .replace(/^```json?\s*/, "")
      .replace(/\s*```$/, "")
      .trim();
  }

  try {
    return JSON.parse(json) as GeminiResult;
  } catch {
    /* continue repair */
  }

  const stack: string[] = [];
  let inString = false;
  let prev = " ";

  for (const char of json) {
    if (inString) {
      if (char === '"' && prev !== "\\") inString = false;
    } else {
      if (char === '"') inString = true;
      else if (char === "{") stack.push("}");
      else if (char === "[") stack.push("]");
      else if (char === "}" || char === "]") {
        if (stack.length) stack.pop();
      }
    }
    prev = char;
  }

  if (inString) json += '"';
  json = json.replace(/,\s*$/, "");
  json += stack.reverse().join("");

  try {
    return JSON.parse(json) as GeminiResult;
  } catch {
    return null;
  }
}

function encodeInstructionsJSON(
  instructions: Array<Record<string, unknown>> | undefined
): string | null {
  if (!instructions?.length) return null;
  const first = instructions[0];
  if (!first.section || !first.instruction) return null;

  const encoded = instructions
    .filter(
      (i) =>
        typeof i.section === "string" &&
        (i.section as string).length > 0 &&
        typeof i.instruction === "string" &&
        (i.instruction as string).length > 0
    )
    .map((i) => {
      const obj: Record<string, unknown> = {
        section: i.section,
        start_row: (i.start_row as number) ?? 0,
        end_row: (i.end_row as number) ?? 0,
        instruction: i.instruction,
      };
      if (typeof i.stitch_count === "number") obj.stitch_count = i.stitch_count;
      if (typeof i.note === "string" && (i.note as string).length > 0)
        obj.note = i.note;
      return obj;
    });

  return encoded.length > 0 ? JSON.stringify(encoded) : null;
}

function encodeStepsJSON(
  steps: Array<{ title: string; body: string }> | undefined
): string | null {
  if (!steps?.length) return null;
  const encoded = steps
    .filter((s) => s.title?.length > 0 && s.body?.length > 0)
    .map((s) => ({ title: s.title, body: s.body }));
  return encoded.length > 0 ? JSON.stringify(encoded) : null;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, content-type",
      },
    });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
    });
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  let body: EnrichRequest;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const patternId = body?.pattern_id;
  if (!patternId) {
    return new Response(JSON.stringify({ error: "Missing pattern_id" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const geminiApiKey = Deno.env.get("GEMINI_API_KEY");

  if (!supabaseUrl || !supabaseAnonKey) {
    return new Response(
      JSON.stringify({ error: "Server configuration error" }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  if (!geminiApiKey) {
    return new Response(
      JSON.stringify({ error: "GEMINI_API_KEY not configured" }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  const supabase = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  // Load pattern
  const { data: pattern, error: fetchError } = await supabase
    .from("patterns")
    .select("*")
    .eq("id", patternId)
    .single();

  if (fetchError || !pattern) {
    return new Response(JSON.stringify({ error: "Pattern not found" }), {
      status: 404,
      headers: { "Content-Type": "application/json" },
    });
  }

  // TikTok videos: skip AI enrichment — captions produce poor steps/descriptions
  if ((pattern.source_platform as string)?.toLowerCase() === "tiktok") {
    if (pattern.enrichment_status !== "complete") {
      await supabase
        .from("patterns")
        .update({
          enrichment_status: "complete",
          enrichment_completed_at: new Date().toISOString(),
        })
        .eq("id", patternId);
    }
    return new Response(
      JSON.stringify({ status: "complete", message: "TikTok — skipped enrichment" }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  }

  // Skip if already enriched successfully
  if (pattern.enrichment_status === "complete") {
    return new Response(
      JSON.stringify({ status: "complete", message: "Already enriched" }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  }

  // Skip if actively processing (started < 2 minutes ago) to avoid duplicate runs
  if (pattern.enrichment_status === "processing" && pattern.enrichment_started_at) {
    const startedAt = new Date(pattern.enrichment_started_at as string).getTime();
    if (Date.now() - startedAt < 120_000) {
      return new Response(
        JSON.stringify({ status: "processing", message: "Already in progress" }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      );
    }
  }

  // Mark as processing
  await supabase
    .from("patterns")
    .update({
      enrichment_status: "processing",
      enrichment_started_at: new Date().toISOString(),
    })
    .eq("id", patternId);

  try {
    // Build content for AI: prefer stored source_content, fall back to page fetch
    let contentForAI = pattern.source_content as string | null;

    if (!contentForAI || contentForAI.length < 50) {
      const fetched = await fetchWebPageText(pattern.source_url as string);
      if (fetched) contentForAI = fetched;
    }

    if (!contentForAI || contentForAI.length < 30) {
      // Not enough content for meaningful AI analysis
      await supabase
        .from("patterns")
        .update({
          enrichment_status: "complete",
          enrichment_completed_at: new Date().toISOString(),
        })
        .eq("id", patternId);
      return new Response(
        JSON.stringify({
          status: "complete",
          message: "Insufficient content for AI analysis",
        }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      );
    }

    const aiResult = await analyzeWithGemini(
      contentForAI,
      pattern.source_url as string,
      geminiApiKey
    );

    if (!aiResult) {
      await supabase
        .from("patterns")
        .update({
          enrichment_status: "failed",
          enrichment_error: "AI analysis returned no results",
          enrichment_completed_at: new Date().toISOString(),
        })
        .eq("id", patternId);
      return new Response(JSON.stringify({ status: "failed" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Build update payload — only fill fields that are currently empty
    const updatePayload: Record<string, unknown> = {
      enrichment_status: "complete",
      enrichment_completed_at: new Date().toISOString(),
      enrichment_error: null,
    };

    if (aiResult.cleaned_content) {
      updatePayload.source_content = aiResult.cleaned_content;
    }
    if (aiResult.summary && (!pattern.description || (pattern.description as string).length < 10)) {
      updatePayload.description = aiResult.summary;
    }
    if (aiResult.difficulty && !pattern.difficulty) {
      updatePayload.difficulty = aiResult.difficulty;
    }
    if (aiResult.materials && !pattern.materials) {
      updatePayload.materials = aiResult.materials;
    }
    if (aiResult.craft_type && !pattern.craft_type) {
      updatePayload.craft_type = aiResult.craft_type;
    }
    if (aiResult.gauge && !pattern.gauge) {
      updatePayload.gauge = aiResult.gauge;
    }
    if (aiResult.needle_hook_sizes && !pattern.needle_hook_sizes) {
      updatePayload.needle_hook_sizes = aiResult.needle_hook_sizes;
    }
    if (aiResult.yarn_weight_yardage && !pattern.yarn_weight_yardage) {
      updatePayload.yarn_weight_yardage = aiResult.yarn_weight_yardage;
    }
    if (aiResult.techniques && !pattern.techniques) {
      updatePayload.techniques = aiResult.techniques;
    }
    if (aiResult.video_url && !pattern.video_url) {
      updatePayload.video_url = aiResult.video_url;
    }

    const parsedSteps =
      encodeInstructionsJSON(aiResult.instructions) ??
      encodeStepsJSON(aiResult.steps);
    if (parsedSteps && !pattern.parsed_steps) {
      updatePayload.parsed_steps = parsedSteps;
    }

    await supabase
      .from("patterns")
      .update(updatePayload)
      .eq("id", patternId);

    // Insert yarn links
    if (aiResult.yarn_links?.length) {
      for (let i = 0; i < Math.min(aiResult.yarn_links.length, 8); i++) {
        const link = aiResult.yarn_links[i];
        if (!link.brand_name) continue;
        const linkPayload: Record<string, unknown> = {
          id: crypto.randomUUID(),
          pattern_id: patternId,
          user_id: pattern.user_id,
          brand_name: link.brand_name,
          display_order: i,
        };
        if (link.official_url) linkPayload.official_url = link.official_url;
        if (link.store_url) linkPayload.store_url = link.store_url;
        await supabase.from("pattern_yarn_links").insert(linkPayload);
      }
    }

    // Link tags
    if (aiResult.tags?.length) {
      for (const tagName of aiResult.tags.slice(0, 6)) {
        const { data: existing } = await supabase
          .from("tags")
          .select("id")
          .ilike("name", tagName)
          .limit(1);
        if (existing?.length) {
          await supabase.from("pattern_tags").insert({
            pattern_id: patternId,
            tag_id: existing[0].id,
          });
        }
      }
    }

    // Increment AI usage
    await supabase.rpc("increment_ai_usage", {
      p_user_id: pattern.user_id,
    });

    return new Response(JSON.stringify({ status: "complete" }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "Unknown error";
    await supabase
      .from("patterns")
      .update({
        enrichment_status: "failed",
        enrichment_error: message,
        enrichment_completed_at: new Date().toISOString(),
      })
      .eq("id", patternId);
    return new Response(
      JSON.stringify({ status: "failed", error: message }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  }
});
