// Gemini proxy — keeps the API key server-side so it never ships in the web
// bundle or APK. The app calls this with the signed-in user's JWT.
//
// Deploy with "Verify JWT" ENABLED (the default): the Supabase gateway then
// rejects unauthenticated calls, so only signed-in users can spend quota.
//
// Secrets to set (Edge Functions → Secrets):
//   GEMINI_API_KEY   — your Google AI Studio key
//   GEMINI_MODEL     — optional, defaults below

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const KEY = Deno.env.get("GEMINI_API_KEY") ?? "";
const MODEL = Deno.env.get("GEMINI_MODEL") ?? "gemini-3.1-flash-lite";

serve(async (req) => {
  try {
    if (req.method !== "POST") {
      return new Response(JSON.stringify({ error: "POST only" }), { status: 405 });
    }
    if (!KEY) {
      return new Response(JSON.stringify({ error: "GEMINI_API_KEY not set" }), {
        status: 500,
      });
    }
    const payload = await req.json();
    const system = String(payload?.system ?? "");
    const prompt = String(payload?.prompt ?? "");
    const temperature = Number(payload?.temperature ?? 0.4);
    if (!prompt.trim()) {
      return new Response(JSON.stringify({ error: "missing prompt" }), {
        status: 400,
      });
    }

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
    if (!res.ok || !String(text).trim()) {
      return new Response(
        JSON.stringify({ error: `gemini ${res.status}`, detail: data?.error?.message }),
        { status: 502 },
      );
    }
    return new Response(JSON.stringify({ text: String(text).trim() }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500 });
  }
});
