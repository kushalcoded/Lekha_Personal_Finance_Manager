// SMS ingest endpoint for iOS (and anything else that can POST).
//
// An iPhone Shortcuts automation fires on incoming bank SMS and POSTs:
//   { "token": "<per-user ingest token>", "body": "<sms text>", "ts": 1712... }
// We resolve the token to a user and queue the raw SMS in `ingested_sms`.
// The app drains that queue through its existing Gemini parse + dedup
// pipeline, so no parsing happens here — this function is just a mailbox.
//
// Deploy with JWT verification OFF (Shortcuts can't send one):
//   dashboard: Edge Functions → ingest-sms → Verify JWT: disabled
// SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are auto-injected secrets.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

serve(async (req) => {
  try {
    if (req.method !== "POST") {
      return new Response(JSON.stringify({ error: "POST only" }), { status: 405 });
    }
    const payload = await req.json();
    const token = String(payload?.token ?? "");
    const body = String(payload?.body ?? "").slice(0, 2000);
    const ts = Number(payload?.ts ?? 0);
    if (token.length < 32 || !body.trim()) {
      return new Response(JSON.stringify({ error: "missing token/body" }), {
        status: 400,
      });
    }

    const { data: match, error: lookupErr } = await supabase
      .from("ingest_tokens")
      .select("user_id")
      .eq("token", token)
      .maybeSingle();
    if (lookupErr) throw lookupErr;
    if (!match) {
      return new Response(JSON.stringify({ error: "invalid token" }), {
        status: 401,
      });
    }

    const receivedAt = ts > 0 ? new Date(ts).toISOString() : new Date().toISOString();
    const { error: insertErr } = await supabase.from("ingested_sms").insert({
      user_id: match.user_id,
      body,
      received_at: receivedAt,
    });
    if (insertErr) throw insertErr;

    return new Response(JSON.stringify({}), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500 });
  }
});
