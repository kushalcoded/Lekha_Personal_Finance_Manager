// AI proxy — keeps API keys server-side so they never ship in the web bundle
// or APK. The app calls this with the signed-in user's JWT.
//
// Deploy with "Verify JWT" ENABLED (the default): the Supabase gateway then
// rejects unauthenticated calls, so only signed-in users can spend quota.
//
// Flow per request:
//   1. Per-user daily cap (AI_DAILY_LIMIT, default 50) via the ai_usage table
//      — fails open if the table/function isn't set up yet.
//   2. Gemini. On quota/error/empty answer →
//   3. Groq fallback (OpenAI-compatible), if GROQ_API_KEY is set.
//
// Secrets to set (Edge Functions → Secrets):
//   GEMINI_API_KEY   — your Google AI Studio key
//   GEMINI_MODEL     — optional, defaults below
//   GROQ_API_KEY     — optional fallback key from console.groq.com
//   GROQ_MODEL       — optional, defaults to llama-3.3-70b-versatile
//   AI_DAILY_LIMIT   — optional, calls per user per day, defaults to 50

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const KEY = Deno.env.get("GEMINI_API_KEY") ?? "";
const MODEL = Deno.env.get("GEMINI_MODEL") ?? "gemini-3.1-flash-lite";
const GROQ_KEY = Deno.env.get("GROQ_API_KEY") ?? "";
const GROQ_MODEL = Deno.env.get("GROQ_MODEL") ?? "llama-3.3-70b-versatile";
const DAILY_LIMIT = Number(Deno.env.get("AI_DAILY_LIMIT") ?? "50");

// Browsers preflight cross-origin requests that carry Authorization headers;
// without these headers (and an OPTIONS handler) the web app's calls die with
// "Failed to fetch" before ever reaching the function.
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

/** User id from the JWT the gateway already verified. */
function userIdFrom(req: Request): string | null {
  try {
    const jwt = (req.headers.get("authorization") ?? "")
      .replace(/^Bearer\s+/i, "");
    const payload = JSON.parse(
      atob(jwt.split(".")[1].replace(/-/g, "+").replace(/_/g, "/")),
    );
    return payload?.sub ?? null;
  } catch {
    return null;
  }
}

/** Atomically bump today's counter; null when metering isn't available. */
async function bumpUsage(userId: string): Promise<number | null> {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) return null;
  try {
    const res = await fetch(`${url}/rest/v1/rpc/increment_ai_usage`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: key,
        Authorization: `Bearer ${key}`,
      },
      body: JSON.stringify({ uid: userId }),
    });
    if (!res.ok) return null;
    return Number(await res.json());
  } catch {
    return null;
  }
}

async function askGemini(
  system: string,
  prompt: string,
  temperature: number,
): Promise<string | null> {
  if (!KEY) return null;
  try {
    const res = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${KEY}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          system_instruction: { parts: [{ text: system }] },
          contents: [{ parts: [{ text: prompt }] }],
          generationConfig: {
            temperature,
            topK: 32,
            topP: 0.95,
            maxOutputTokens: 220,
          },
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

async function askGroq(
  system: string,
  prompt: string,
  temperature: number,
): Promise<string | null> {
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
          ...(system.trim() ? [{ role: "system", content: system }] : []),
          { role: "user", content: prompt },
        ],
        temperature: Math.min(temperature, 2),
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

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS });
  }
  try {
    if (req.method !== "POST") {
      return new Response(JSON.stringify({ error: "POST only" }), {
        status: 405,
        headers: CORS,
      });
    }
    if (!KEY && !GROQ_KEY) {
      return new Response(JSON.stringify({ error: "no AI key configured" }), {
        status: 500,
        headers: CORS,
      });
    }
    const payload = await req.json();
    const system = String(payload?.system ?? "");
    const prompt = String(payload?.prompt ?? "");
    const temperature = Number(payload?.temperature ?? 0.4);
    if (!prompt.trim()) {
      return new Response(JSON.stringify({ error: "missing prompt" }), {
        status: 400,
        headers: CORS,
      });
    }

    const uid = userIdFrom(req);
    if (uid) {
      const count = await bumpUsage(uid);
      if (count !== null && count > DAILY_LIMIT) {
        return new Response(
          JSON.stringify({
            error: "Daily AI limit reached — try again tomorrow.",
          }),
          { status: 429, headers: CORS },
        );
      }
    }

    const text = (await askGemini(system, prompt, temperature)) ??
      (await askGroq(system, prompt, temperature));
    if (!text) {
      return new Response(
        JSON.stringify({ error: "all AI providers failed" }),
        { status: 502, headers: CORS },
      );
    }
    return new Response(JSON.stringify({ text }), {
      status: 200,
      headers: { ...CORS, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: CORS,
    });
  }
});
