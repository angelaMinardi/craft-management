// Supabase Edge Function: extract-pattern-from-video
// POST body: { url: string } (YouTube URL). Requires Authorization: Bearer <user JWT>.
// Checks freemium YouTube import limit, then fetches transcript and runs Claude.
// Requires: ANTHROPIC_API_KEY. Optional: SCRAPECREATORS_API_KEY or YOUTUBE_TRANSCRIPT_DEV_API_KEY for reliable transcripts.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const YOUTUBE_REGEX = /(?:youtube\.com\/watch\?v=|youtu\.be\/)([a-zA-Z0-9_-]{11})/;

interface RequestBody {
  url: string;
}

interface PatternPayload {
  title: string;
  summary: string;
  tags: string[];
  craft_type: string | null;
  difficulty: string | null;
  materials: string | null;
  cleaned_content: string | null;
  video_url: string | null;
  gauge: string | null;
  needle_hook_sizes: string | null;
  yarn_weight_yardage: string | null;
  techniques: string | null;
  yarn_links: Array<{ brand_name: string; official_url: string | null; store_url: string | null }>;
  steps?: Array<{ title: string; body: string }>;
}

type CaptionTrack = { baseUrl: string; kind?: string };

function findKey(obj: unknown, key: string): unknown {
  if (obj === null || typeof obj !== "object") return undefined;
  const record = obj as Record<string, unknown>;
  if (Object.prototype.hasOwnProperty.call(record, key)) return record[key];
  for (const v of Object.values(record)) {
    const found = findKey(v, key);
    if (found !== undefined) return found;
  }
  return undefined;
}

async function fetchCaptionAsText(captionUrl: string): Promise<string | null> {
  try {
    const captionRes = await fetch(captionUrl, {
      headers: { "User-Agent": "Mozilla/5.0 (Windows NT 10.0; rv:91.0) Gecko/20100101 Firefox/91.0" },
    });
    const captionXml = await captionRes.text();
    const textMatch = captionXml.match(/<text[^>]*>([^<]*)</g);
    if (!textMatch) return null;
    const lines = textMatch.map((line) => {
      const m = line.match(/<text[^>]*>([^<]*)</);
      return m ? decodeHTMLEntities(m[1].trim()) : "";
    });
    const text = lines.filter(Boolean).join("\n");
    return text.length > 20 ? text : null;
  } catch {
    return null;
  }
}

function getCaptionTracks(data: Record<string, unknown>): CaptionTrack[] {
  const raw = data.captions ?? (data.response as Record<string, unknown>)?.captions;
  const captions = raw as { playerCaptionsTracklistRenderer?: { captionTracks?: CaptionTrack[] } } | undefined;
  return captions?.playerCaptionsTracklistRenderer?.captionTracks ?? [];
}

async function fetchTranscriptViaGetTranscript(
  apiKey: string,
  transcriptToken: string,
  headers: Record<string, string>
): Promise<string | null> {
  try {
    const res = await fetch(
      `https://www.youtube.com/youtubei/v1/get_transcript?key=${apiKey}`,
      {
        method: "POST",
        headers,
        body: JSON.stringify({
          context: {
            client: { clientName: "WEB", clientVersion: "2.20241028.01.00" },
          },
          params: transcriptToken,
        }),
      }
    );
    if (!res.ok) return null;
    const data = (await res.json()) as Record<string, unknown>;
    const segments = findKey(data, "initialSegments") as Array<Record<string, unknown>> | undefined;
    if (!Array.isArray(segments)) return null;
    const lines = segments
      .map((seg) => {
        const segRenderer = seg.transcriptSegmentRenderer as Record<string, unknown> | undefined;
        const runs = (segRenderer?.snippet as Record<string, unknown>)?.runs as Array<{ text?: string }> | undefined;
        return runs?.[0]?.text ?? "";
      })
      .filter(Boolean);
    const text = lines.join("\n").trim();
    return text.length > 20 ? text : null;
  } catch {
    return null;
  }
}

async function fetchYoutubeTranscript(videoId: string): Promise<string | null> {
  const headers = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Content-Type": "application/json",
  };

  try {
    const pageRes = await fetch(`https://www.youtube.com/watch?v=${videoId}`, { headers });
    const html = await pageRes.text();

    let apiKey =
      html.match(/"INNERTUBE_API_KEY"\s*:\s*"([^"]+)"/)?.[1] ??
      html.match(/INNERTUBE_API_KEY["\s]*[:=]["\s]*([a-zA-Z0-9_-]+)/)?.[1];
    if (!apiKey) return null;

    const webClient = { clientName: "WEB", clientVersion: "2.20241028.01.00" };
    const playerRes = await fetch(
      `https://www.youtube.com/youtubei/v1/player?key=${apiKey}`,
      {
        method: "POST",
        headers,
        body: JSON.stringify({
          context: { client: webClient },
          videoId,
        }),
      }
    );
    if (!playerRes.ok) return null;
    const playerData = (await playerRes.json()) as Record<string, unknown>;

    const transcriptEndpoint = findKey(playerData, "getTranscriptEndpoint") as { params?: string } | undefined;
    const transcriptParams = transcriptEndpoint?.params;
    if (transcriptParams) {
      const text = await fetchTranscriptViaGetTranscript(apiKey, transcriptParams, headers);
      if (text) return text;
    }

    const clients = [
      { clientName: "ANDROID", clientVersion: "20.10.38" },
      { clientName: "WEB", clientVersion: "2.20231219.01.00" },
      { clientName: "TV_EMBEDDED", clientVersion: "2.0" },
    ];

    for (const client of clients) {
      const res = await fetch(
        `https://www.youtube.com/youtubei/v1/player?key=${apiKey}`,
        {
          method: "POST",
          headers,
          body: JSON.stringify({ context: { client }, videoId }),
        }
      );
      if (!res.ok) continue;
      const data = (await res.json()) as Record<string, unknown>;
      const tracks = getCaptionTracks(data);
      const manualFirst = [...tracks].sort((a, b) => (a.kind === "asr" ? 1 : 0) - (b.kind === "asr" ? 1 : 0));

      for (const t of manualFirst) {
        if (!t?.baseUrl) continue;
        const url = t.baseUrl.replace(/&fmt=\w+$/, "");
        const text = await fetchCaptionAsText(url);
        if (text) return text;
      }
    }
    return null;
  } catch {
    return null;
  }
}

function decodeHTMLEntities(s: string): string {
  return s
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&#39;/g, "'")
    .replace(/&quot;/g, '"')
    .replace(/&#x27;/g, "'");
}

/** ScrapeCreators: GET with url param, x-api-key. Returns transcript_only_text or joined transcript[].text. */
async function fetchTranscriptScrapeCreators(videoUrl: string): Promise<string | null> {
  const apiKey = Deno.env.get("SCRAPECREATORS_API_KEY");
  if (!apiKey) return null;
  try {
    const res = await fetch(
      `https://api.scrapecreators.com/v1/youtube/video/transcript?url=${encodeURIComponent(videoUrl)}`,
      { headers: { "x-api-key": apiKey } }
    );
    if (!res.ok) return null;
    const data = (await res.json()) as {
      transcript_only_text?: string;
      transcript?: Array<{ text?: string }>;
    };
    const text = data.transcript_only_text ?? data.transcript?.map((t) => t.text ?? "").join(" ").trim();
    return text && text.length > 50 ? text : null;
  } catch {
    return null;
  }
}

/** YouTubeTranscript.dev: POST /api/v2/transcribe with video (url or id), Bearer token. Uses captions only (no ASR). */
async function fetchTranscriptYouTubeTranscriptDev(videoIdOrUrl: string): Promise<string | null> {
  const apiKey = Deno.env.get("YOUTUBE_TRANSCRIPT_DEV_API_KEY");
  if (!apiKey) return null;
  try {
    const res = await fetch("https://www.youtubetranscript.dev/api/v2/transcribe", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ video: videoIdOrUrl, source: "auto" }),
    });
    if (!res.ok) return null;
    const data = (await res.json()) as { status?: string; data?: { transcript?: { text?: string } } };
    if (data.status !== "completed" || !data.data?.transcript?.text) return null;
    const text = data.data.transcript.text.trim();
    return text.length > 50 ? text : null;
  } catch {
    return null;
  }
}

/** Try optional transcript APIs first, then built-in YouTube fetcher. */
async function getYoutubeTranscript(videoId: string, videoUrl: string): Promise<string | null> {
  const fromScrape = await fetchTranscriptScrapeCreators(videoUrl);
  if (fromScrape) return fromScrape;
  const fromDev = await fetchTranscriptYouTubeTranscriptDev(videoUrl);
  if (fromDev) return fromDev;
  const fromDevById = await fetchTranscriptYouTubeTranscriptDev(videoId);
  if (fromDevById) return fromDevById;
  return fetchYoutubeTranscript(videoId);
}

type ClaudeResult = { payload: PatternPayload } | { payload: null; error: string };

async function extractWithClaude(transcript: string, videoUrl: string): Promise<ClaudeResult> {
  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) return { payload: null, error: "Missing ANTHROPIC_API_KEY" };

  const systemPrompt =
    "You are a craft pattern analyzer. Given a video transcript about a craft pattern, extract structured information. Respond ONLY with valid JSON, no markdown fences.";
  const userPrompt = `
Analyze this video transcript and extract the following as JSON:
{
  "title": "a short, catchy name for this pattern (2-5 words)",
  "summary": "2-3 sentence description",
  "tags": ["tag1", "tag2"],
  "craft_type": "knitting/crochet/sewing/etc or null",
  "difficulty": "beginner/intermediate/advanced or null",
  "materials": "brief materials summary or null",
  "cleaned_content": "relevant pattern instructions or notes from the transcript, or null",
  "video_url": ${JSON.stringify(videoUrl)},
  "gauge": "or null",
  "needle_hook_sizes": "or null",
  "yarn_weight_yardage": "or null",
  "techniques": "comma-separated or null",
  "yarn_links": [{"brand_name":"","official_url":null,"store_url":null}],
  "steps": [{"title": "short step name (2-5 words)", "body": "instructions for this phase"}]
}
Max 6 tags. yarn_links: only real yarn brand names with URLs if known. Max 8.
steps: 3-15 construction phases (e.g. "Materials & setup", "Body", "Finishing"). title: 2-5 words. body: full instructions for that phase. Omit steps if transcript has no real pattern structure.

Transcript:
${transcript.slice(0, 15000)}
`;

  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: "claude-sonnet-4-20250514",
      max_tokens: 2000,
      system: systemPrompt,
      messages: [{ role: "user", content: userPrompt }],
    }),
  });

  const data = await res.json().catch(() => ({})) as { content?: Array<{ text?: string }>; error?: { message?: string } };
  if (!res.ok) {
    const msg = data?.error?.message ?? data?.message ?? `Anthropic API ${res.status}`;
    return { payload: null, error: msg };
  }
  const text = data.content?.[0]?.text;
  if (!text) return { payload: null, error: "No text in Claude response" };

  let cleaned = text.trim();
  if (cleaned.startsWith("```")) {
    cleaned = cleaned.replace(/^```json?\s*/, "").replace(/\s*```$/, "").trim();
  }
  try {
    return { payload: JSON.parse(cleaned) as PatternPayload };
  } catch {
    return { payload: null, error: "Claude returned invalid JSON" };
  }
}

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
    });
  }

  let body: RequestBody;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON body" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const url = body?.url;
  if (!url || typeof url !== "string") {
    return new Response(JSON.stringify({ error: "Missing url in body" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const ytMatch = url.match(YOUTUBE_REGEX);
  const videoId = ytMatch?.[1];
  if (!videoId) {
    return new Response(JSON.stringify({ error: "Unsupported URL; YouTube only" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return new Response(JSON.stringify({ error: "Missing or invalid Authorization header" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseUrl || !supabaseAnonKey) {
    return new Response(JSON.stringify({ error: "Server configuration error" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
  const supabase = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: youtubeCount, error: rpcError } = await supabase.rpc("increment_youtube_imports_for_current_user");
  if (rpcError || youtubeCount === -1) {
    return new Response(
      JSON.stringify({
        error: "YouTube import limit reached this month. Upgrade to Premium for unlimited imports.",
      }),
      { status: 402, headers: { "Content-Type": "application/json" } }
    );
  }

  const transcript = await getYoutubeTranscript(videoId, url);
  if (!transcript || transcript.length < 50) {
    return new Response(
      JSON.stringify({ error: "Could not fetch transcript; video may have no captions" }),
      { status: 422, headers: { "Content-Type": "application/json" } }
    );
  }

  const result = await extractWithClaude(transcript, url);
  if (!result.payload) {
    return new Response(
      JSON.stringify({ error: "AI extraction failed", detail: result.error }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  const payload = result.payload;
  const responseBody = {
    ...payload,
    parsed_steps: JSON.stringify(payload.steps ?? []),
  };
  return new Response(JSON.stringify(responseBody), {
    status: 200,
    headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
  });
});
