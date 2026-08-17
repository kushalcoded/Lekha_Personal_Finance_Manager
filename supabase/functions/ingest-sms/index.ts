// SMS ingest endpoint for iOS (and anything else that can POST).
//
// An iPhone Shortcuts automation fires on incoming bank SMS and POSTs:
//   { "token": "<per-user ingest token>", "body": "<sms text>", "ts": 1712... }
//
// The raw text is logged to `ingested_sms` (that table feeds the connection
// health card) and then parsed RIGHT HERE, so the detection exists the moment
// the message arrives. Previously parsing waited for the app to be opened,
// which on iOS could be days — the phone can't run app code in the background.
// Parsed debits land in `detected_transactions`, which every device reads.
//
// If parsing is unavailable (no key, quota, model error) the row is left with
// status 'new' so the app's own drain still picks it up on next open — the old
// behaviour, kept as the fallback rather than the primary path.
//
// Deploy with JWT verification OFF (Shortcuts can't send one):
//   dashboard: Edge Functions → ingest-sms → Verify JWT: disabled
// SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are auto-injected. Set the same
// GEMINI_API_KEY / GROQ_API_KEY secrets this function shares with gemini-proxy.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const GEMINI_KEY = Deno.env.get("GEMINI_API_KEY") ?? "";
const GEMINI_MODEL = Deno.env.get("GEMINI_MODEL") ?? "gemini-3.1-flash-lite";
const GROQ_KEY = Deno.env.get("GROQ_API_KEY") ?? "";
const GROQ_MODEL = Deno.env.get("GROQ_MODEL") ?? "llama-3.3-70b-versatile";

function systemPrompt(today: string): string {
  return (
    "You read ONE bank or UPI SMS and extract the transaction amount " +
    "and, when the message states it, when it happened. " +
    'Respond with ONLY compact JSON: {"isFinancial":bool,"isDebit":bool,' +
    '"amount":number,"when":string|null}. ' +
    "isFinancial=false for OTP, promotional, balance-only, EMI-due, or " +
    "delivery messages. isDebit=true only when money LEFT the account " +
    "(debited / spent / paid / sent / withdrawn); false for credits, " +
    "refunds, or received money. amount is the transaction amount, NOT the " +
    "available balance; use 0 if unclear. " +
    '"when" is the transaction date (and time if given) as an ISO 8601 ' +
    "string, resolving 2-digit years and formats like 01-08-26 or " +
    `"on 30Jul25 14:22"; today is ${today}. Use null when the message does ` +
    "not state a date — never guess."
  );
}

async function askGemini(system: string, prompt: string): Promise<string | null> {
  if (!GEMINI_KEY) return null;
  try {
    const res = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_KEY}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          system_instruction: { parts: [{ text: system }] },
          contents: [{ parts: [{ text: prompt }] }],
          generationConfig: { temperature: 0, maxOutputTokens: 220 },
        }),
      },
    );
    const data = await res.json();
    const text = data?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
    if (!res.ok || !String(text).trim()) return null;
    return String(text).trim();
  } catch {
    return null;
  }
}

async function askGroq(system: string, prompt: string): Promise<string | null> {
  if (!GROQ_KEY) return null;
  try {
    const res = await fetch("https://api.groq.com/openai/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${GROQ_KEY}`,
      },
      body: JSON.stringify({
        model: GROQ_MODEL,
        messages: [
          { role: "system", content: system },
          { role: "user", content: prompt },
        ],
        temperature: 0,
        max_tokens: 220,
      }),
    });
    if (!res.ok) return null;
    const data = await res.json();
    const text = data?.choices?.[0]?.message?.content ?? "";
    return String(text).trim() || null;
  } catch {
    return null;
  }
}

/**
 * "HDFC Bank · UPI" from a bank SMS — mirrors smsSenderLabel in the app.
 * Once a message is parsed nothing needs its text again, and storing other
 * people's bank SMS is not something this project wants to be doing. The
 * unparsed copy in `ingested_sms` is the one exception: the app's own drain
 * is the fallback and still needs the words.
 */
function senderLabel(body: string): string {
  const head = body.split(/[:\-—]/)[0].trim();
  const words = head.split(/\s+/).filter(Boolean);
  const name = (words.length > 3 || !head ? words.slice(0, 2).join(" ") : head) ||
    "Bank SMS";
  const channels: [string, string][] = [
    ["upi", "UPI"],
    ["atm", "ATM"],
    ["imps", "IMPS"],
    ["neft", "NEFT"],
    ["debit card", "Card"],
    ["credit card", "Card"],
    ["autopay", "Autopay"],
  ];
  const lower = body.toLowerCase();
  const hit = channels.find(([key]) => lower.includes(key));
  return hit ? `${name} · ${hit[1]}` : name;
}

/** Models like to wrap JSON in prose or fences. */
function extractJson(raw: string): string {
  const fenced = raw.match(/```(?:json)?\s*([\s\S]*?)```/i);
  const text = (fenced ? fenced[1] : raw).trim();
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  return start >= 0 && end > start ? text.slice(start, end + 1) : text;
}

/**
 * The transaction's own time when the SMS states one, else when it reached us.
 * Mirrors resolveTransactionTime in the app so both paths agree.
 */
function occurredAt(stated: unknown, fallbackIso: string): string {
  const text = String(stated ?? "").trim();
  if (!text || text.toLowerCase() === "null") return fallbackIso;
  const parsed = new Date(text);
  if (Number.isNaN(parsed.getTime())) return fallbackIso;
  const now = Date.now();
  if (parsed.getTime() > now + 86_400_000) return fallbackIso;
  if (parsed.getTime() < now - 400 * 86_400_000) return fallbackIso;
  // Date-only answers keep the delivery clock time rather than claiming
  // midnight precision the message never gave.
  if (
    parsed.getUTCHours() === 0 &&
    parsed.getUTCMinutes() === 0 &&
    parsed.getUTCSeconds() === 0
  ) {
    const fallback = new Date(fallbackIso);
    parsed.setUTCHours(fallback.getUTCHours(), fallback.getUTCMinutes());
  }
  return parsed.toISOString();
}

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

    const receivedAt = ts > 0
      ? new Date(ts).toISOString()
      : new Date().toISOString();

    // Parse first so the raw row can be filed as already-handled.
    const system = systemPrompt(receivedAt.slice(0, 10));
    const prompt = `SMS: ${body}\nReturn only the JSON.`;
    const answer = (await askGemini(system, prompt)) ??
      (await askGroq(system, prompt));

    let parsed: Record<string, unknown> | null = null;
    if (answer) {
      try {
        parsed = JSON.parse(extractJson(answer));
      } catch {
        parsed = null;
      }
    }

    const { data: raw, error: insertErr } = await supabase
      .from("ingested_sms")
      .insert({
        user_id: match.user_id,
        // Kept whole only while the app still has to parse it.
        body: parsed ? senderLabel(body) : body,
        received_at: receivedAt,
        // 'done' only when we actually parsed it; otherwise the app's drain
        // remains the safety net.
        status: parsed ? "done" : "new",
      })
      .select("id")
      .single();
    if (insertErr) throw insertErr;

    let detected = false;
    if (parsed) {
      const amount = Number(parsed["amount"] ?? 0);
      const isDebit = parsed["isDebit"] === true;
      const isFinancial = parsed["isFinancial"] === true;
      if (isFinancial && isDebit && amount > 0) {
        // Same id shape the app uses for cloud rows, so a client that already
        // drained this SMS the old way doesn't create a second card.
        const { error: detectErr } = await supabase
          .from("detected_transactions")
          .upsert({
            id: `cloud_${raw.id}`,
            user_id: match.user_id,
            amount,
            occurred_at: occurredAt(parsed["when"], receivedAt),
            raw_body: senderLabel(body),
            status: "pending",
          }, { onConflict: "id" });
        if (detectErr) throw detectErr;
        detected = true;
      }
    }

    return new Response(JSON.stringify({ parsed: !!parsed, detected }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500 });
  }
});
