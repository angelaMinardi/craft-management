// Supabase Edge Function: mascot-poll
// POST: { name_choice, voter_id } -> { results }
// GET: -> { results }
// Anonymous voting for mascot naming poll.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

const VALID_NAMES = ["pip", "bobbin", "purl", "thimble", "bramble"];

async function getResults(supabase: ReturnType<typeof createClient>) {
  const { data } = await supabase
    .from("mascot_poll_votes")
    .select("name_choice");

  const results: Record<string, number> = {};
  for (const name of VALID_NAMES) results[name] = 0;
  for (const row of data || []) {
    if (results[row.name_choice] !== undefined) {
      results[row.name_choice]++;
    }
  }
  return results;
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  try {
    if (req.method === "GET") {
      const results = await getResults(supabase);
      return new Response(
        JSON.stringify({ results }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    if (req.method === "POST") {
      const body = await req.json();
      const nameChoice = body.name_choice;
      const voterId = body.voter_id;

      if (!nameChoice || !VALID_NAMES.includes(nameChoice)) {
        return new Response(
          JSON.stringify({ error: "Invalid name choice." }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      if (!voterId) {
        return new Response(
          JSON.stringify({ error: "Voter ID required." }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      // Upsert — allows changing vote
      const { error: upsertError } = await supabase
        .from("mascot_poll_votes")
        .upsert(
          { name_choice: nameChoice, voter_id: voterId },
          { onConflict: "voter_id" },
        );

      if (upsertError) {
        console.error("Poll vote error:", upsertError);
        return new Response(
          JSON.stringify({ error: "Something went wrong." }),
          {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      const results = await getResults(supabase);
      return new Response(
        JSON.stringify({ results }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    return new Response(
      JSON.stringify({ error: "Method not allowed" }),
      {
        status: 405,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (err) {
    console.error("Mascot poll error:", err);
    return new Response(
      JSON.stringify({ error: "Something went wrong." }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
