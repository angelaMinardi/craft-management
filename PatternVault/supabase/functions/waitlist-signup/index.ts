// Supabase Edge Function: waitlist-signup
// POST: { email, name?, craft_types?, current_method?, device?, archetype?, referral_source? }
//   -> { position, total, remaining, isFull }
// GET: -> { total, remaining, isFull }
// No auth required — public beta signup. Capped at 12 beta testers.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const BETA_CAP = 12;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

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
      const { count } = await supabase
        .from("waitlist_signups")
        .select("*", { count: "exact", head: true });

      const total = count ?? 0;
      return new Response(
        JSON.stringify({
          total,
          remaining: Math.max(0, BETA_CAP - total),
          isFull: total >= BETA_CAP,
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    if (req.method === "POST") {
      const body = await req.json();
      const email = (body.email ?? "").trim().toLowerCase();

      if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
        return new Response(
          JSON.stringify({ error: "Please enter a valid email address." }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      // Check if this email already exists (re-signup is fine)
      const { data: existing } = await supabase
        .from("waitlist_signups")
        .select("id")
        .eq("email", email)
        .maybeSingle();

      // If new signup, check the cap
      if (!existing) {
        const { count: currentTotal } = await supabase
          .from("waitlist_signups")
          .select("*", { count: "exact", head: true });

        if ((currentTotal ?? 0) >= BETA_CAP) {
          return new Response(
            JSON.stringify({
              error:
                "All 12 beta spots have been claimed! Join the waitlist for public launch.",
              isFull: true,
            }),
            {
              status: 409,
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            },
          );
        }
      }

      // Upsert to handle duplicates gracefully
      const { error: upsertError } = await supabase
        .from("waitlist_signups")
        .upsert(
          {
            email,
            name: body.name?.trim() || null,
            craft_types: Array.isArray(body.craft_types) ? body.craft_types : null,
            current_method: body.current_method?.trim() || null,
            device: body.device?.trim() || null,
            archetype: body.archetype ?? null,
            referral_source: body.referral_source ?? null,
          },
          { onConflict: "email" },
        );

      if (upsertError) {
        console.error("Upsert error:", upsertError);
        return new Response(
          JSON.stringify({ error: "Something went wrong. Please try again." }),
          {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      // Get position (row number by signup order)
      const { data: positionData } = await supabase
        .from("waitlist_signups")
        .select("id, signed_up_at")
        .eq("email", email)
        .single();

      const { count: totalCount } = await supabase
        .from("waitlist_signups")
        .select("*", { count: "exact", head: true });

      // Position = count of rows with signed_up_at <= this row's signed_up_at
      let position = totalCount ?? 1;
      if (positionData) {
        const { count: posCount } = await supabase
          .from("waitlist_signups")
          .select("*", { count: "exact", head: true })
          .lte("signed_up_at", positionData.signed_up_at);
        position = posCount ?? 1;
      }

      const total = totalCount ?? position;
      return new Response(
        JSON.stringify({
          position,
          total,
          remaining: Math.max(0, BETA_CAP - total),
          isFull: total >= BETA_CAP,
        }),
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
    console.error("Waitlist signup error:", err);
    return new Response(
      JSON.stringify({ error: "Something went wrong. Please try again." }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
