// Supabase Edge Function: waitlist-signup
// POST: { email, name?, craft_types?, current_method?, device?, archetype?, referral_source? }
//   -> { position, total }
// GET: -> { total }
// No auth required — public beta signup. No cap on signups.
// Emails via Resend: notification to admin, confirmation to signer (new signups only).

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

const ADMIN_EMAIL = "r.minardi.angela@gmail.com";
const FROM_EMAIL = "hello@corvidcraft.com";
const FROM_NAME = "Corvid Craft";

async function sendEmail(to: string, subject: string, html: string): Promise<void> {
  const apiKey = Deno.env.get("RESEND_API_KEY");
  if (!apiKey) {
    console.warn("RESEND_API_KEY not set — skipping email");
    return;
  }

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: `${FROM_NAME} <${FROM_EMAIL}>`,
      to: [to],
      subject,
      html,
    }),
  });

  if (!res.ok) {
    const err = await res.text();
    console.error("Resend error:", err);
  }
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
      const { count } = await supabase
        .from("waitlist_signups")
        .select("*", { count: "exact", head: true });

      const total = count ?? 0;
      return new Response(
        JSON.stringify({ total }),
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

      // Check if this email already exists before upsert (for email logic)
      const { data: existing } = await supabase
        .from("waitlist_signups")
        .select("id")
        .eq("email", email)
        .maybeSingle();

      const isNewSignup = !existing;

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

      // Send emails only for new signups (not re-submissions)
      if (isNewSignup) {
        const name = body.name?.trim() || null;
        const crafts = Array.isArray(body.craft_types) && body.craft_types.length > 0
          ? body.craft_types.join(", ")
          : "not specified";
        const device = body.device || "not specified";
        const archetype = body.archetype || null;
        const displayName = name || email;

        // Fire emails in parallel, don't await (non-blocking)
        Promise.all([
          // Admin notification
          sendEmail(
            ADMIN_EMAIL,
            `New beta signup #${position}: ${displayName}`,
            `
<div style="font-family:sans-serif;max-width:480px;margin:0 auto;padding:24px;">
  <h2 style="color:#4A2040;margin:0 0 16px;">New Beta Tester Signup 🎉</h2>
  <table style="width:100%;border-collapse:collapse;font-size:14px;">
    <tr><td style="padding:6px 0;color:#666;width:120px;">Position</td><td style="padding:6px 0;font-weight:600;color:#4A2040;">#${position} of ${total}</td></tr>
    <tr><td style="padding:6px 0;color:#666;">Name</td><td style="padding:6px 0;color:#4A2040;">${name ?? "—"}</td></tr>
    <tr><td style="padding:6px 0;color:#666;">Email</td><td style="padding:6px 0;color:#4A2040;">${email}</td></tr>
    <tr><td style="padding:6px 0;color:#666;">Crafts</td><td style="padding:6px 0;color:#4A2040;">${crafts}</td></tr>
    <tr><td style="padding:6px 0;color:#666;">Device</td><td style="padding:6px 0;color:#4A2040;">${device}</td></tr>
    ${archetype ? `<tr><td style="padding:6px 0;color:#666;">Archetype</td><td style="padding:6px 0;color:#4A2040;">${archetype}</td></tr>` : ""}
  </table>
  <p style="margin-top:24px;font-size:12px;color:#999;">
    Sent from Corvid Craft waitlist · <a href="https://supabase.com/dashboard/project/fbzbnztvanuiijzymckn/editor" style="color:#A8C5A0;">View in Supabase</a>
  </p>
</div>
            `.trim(),
          ),
          // Confirmation to signer
          sendEmail(
            email,
            "You're on the Corvid Craft beta list! 🧶",
            `
<div style="font-family:sans-serif;max-width:480px;margin:0 auto;padding:24px;">
  <h2 style="color:#4A2040;margin:0 0 8px;">You're in, ${name ?? "crafter"}!</h2>
  <p style="color:#5C3A52;line-height:1.6;margin:0 0 16px;">
    Thanks for signing up to beta test Corvid Craft. You're <strong>beta tester #${position}</strong> — we'll send you TestFlight access as we onboard testers.
  </p>
  <p style="color:#5C3A52;line-height:1.6;margin:0 0 24px;">
    In the meantime, take the crafting archetype quiz to find out what kind of crafter you are:
  </p>
  <a href="https://www.corvidcraft.com/quiz" style="display:inline-block;padding:12px 24px;background:#A8C5A0;color:white;text-decoration:none;border-radius:100px;font-weight:700;">Take the Quiz</a>
  <p style="margin-top:32px;font-size:12px;color:#999;">
    You're receiving this because you signed up at corvidcraft.com · Built with ♥ in Northern BC
  </p>
</div>
            `.trim(),
          ),
        ]).catch((err) => console.error("Email send error:", err));
      }

      return new Response(
        JSON.stringify({ position, total }),
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
