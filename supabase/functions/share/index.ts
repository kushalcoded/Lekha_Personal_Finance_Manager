// Shared pages — the guest side of a shared debt ledger.
//
// Deploy with "Verify JWT" DISABLED: guests have no account and no JWT. The
// share token in the request body is the credential, exactly the way
// ingest-sms works. Everything is scoped by looking that token up; nothing the
// client says about who it is is ever trusted.
//
// The owner's app does NOT come through here. It talks to PostgREST directly
// with the user's own JWT under the owner-scoped RLS policies. This function
// exists only because a guest has no way to authenticate to Postgres at all —
// which is also why it must never grow an action that acts on the owner's
// behalf.
//
// Secrets to set (Edge Functions → Secrets):
//   GUEST_PIN_PEPPER     — mixed into every PIN hash. It is not in the
//                          database, so a database leak on its own exposes no
//                          PINs. Changing it invalidates every existing PIN.
//   GUEST_SESSION_SECRET — signs the week-long session tokens. Changing it
//                          just signs everyone out.
//
// On the honesty of a 4-digit PIN: 10,000 possibilities is not much, and
// PBKDF2 does not change that against someone who already has the hashes. The
// three things actually holding the door are that you need the share link
// before a PIN is even asked for, that guessing is rate-limited per person,
// and that the pepper lives here rather than in Postgres. That is the right
// amount of lock for a page that records who owes whom and moves no money.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const PEPPER = Deno.env.get("GUEST_PIN_PEPPER") ?? "";
const SESSION_SECRET = Deno.env.get("GUEST_SESSION_SECRET") ?? "";

const SESSION_DAYS = 7;
const MAX_FAILS = 5;
const PBKDF2_ROUNDS = 100000;

// A browser calls this cross-origin, so without these headers and an OPTIONS
// handler every request dies as "Failed to fetch" before reaching the code.
// Narrower than gemini-proxy's on purpose: the guest sends no auth header, the
// session rides in the JSON body.
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const supabase = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
);

const enc = new TextEncoder();

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "content-type": "application/json" },
  });
}

function b64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

function unb64url(s: string): Uint8Array {
  const t = s.replace(/-/g, "+").replace(/_/g, "/");
  const padded = t + "=".repeat((4 - (t.length % 4)) % 4);
  return Uint8Array.from(atob(padded), (c) => c.charCodeAt(0));
}

/** Length-independent compare, so a wrong PIN can't be timed character by
 * character. */
function sameSecret(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

async function hashPin(pin: string, salt: Uint8Array): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(pin + PEPPER),
    "PBKDF2",
    false,
    ["deriveBits"],
  );
  const bits = await crypto.subtle.deriveBits(
    { name: "PBKDF2", salt, iterations: PBKDF2_ROUNDS, hash: "SHA-256" },
    key,
    256,
  );
  return b64url(new Uint8Array(bits));
}

async function hmac(payload: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(SESSION_SECRET),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(payload));
  return b64url(new Uint8Array(sig));
}

/** Signed, self-contained, 7 days. No sessions table: there is no scheduler
 * here to reap one, and the only revocation this feature needs — the owner
 * resetting a PIN — comes free from bumping pin_version, which is checked on
 * every read anyway. */
async function mintSession(
  personId: string,
  spaceId: string,
  pinVersion: number,
): Promise<string> {
  const claims = {
    p: personId,
    sp: spaceId,
    v: pinVersion,
    exp: Math.floor(Date.now() / 1000) + SESSION_DAYS * 86400,
  };
  const body = b64url(enc.encode(JSON.stringify(claims)));
  return `${body}.${await hmac(body)}`;
}

async function readSession(
  token: unknown,
): Promise<{ p: string; sp: string; v: number } | null> {
  if (typeof token !== "string" || !token.includes(".")) return null;
  const [body, sig] = token.split(".");
  if (!body || !sig) return null;
  if (!sameSecret(await hmac(body), sig)) return null;
  try {
    const claims = JSON.parse(new TextDecoder().decode(unb64url(body)));
    if (!claims?.exp || claims.exp * 1000 < Date.now()) return null;
    return claims;
  } catch {
    return null;
  }
}

/** Wrong PINs cost more each time: 15 minutes, then 30, then an hour, capped
 * at a day. Five-per-15-minutes turns 10,000 guesses into years. */
function lockMinutes(failedCount: number): number {
  const locks = Math.max(1, failedCount - MAX_FAILS + 1);
  return Math.min(15 * 2 ** (locks - 1), 24 * 60);
}

type Participant = {
  token: string;
  owner_id: string;
  space_id: string;
  person_id: string;
  owner_net: number;
};

async function participantByToken(token: unknown): Promise<Participant | null> {
  if (typeof token !== "string" || token.length < 32) return null;
  const { data } = await supabase
    .from("shared_participants")
    .select("token, owner_id, space_id, person_id, owner_net")
    .eq("token", token)
    .is("revoked_at", null)
    .maybeSingle();
  return (data as Participant) ?? null;
}

async function participantBySession(claims: {
  p: string;
  sp: string;
}): Promise<Participant | null> {
  const { data } = await supabase
    .from("shared_participants")
    .select("token, owner_id, space_id, person_id, owner_net")
    .eq("space_id", claims.sp)
    .eq("person_id", claims.p)
    .is("revoked_at", null)
    .maybeSingle();
  return (data as Participant) ?? null;
}

async function personById(id: string) {
  const { data } = await supabase
    .from("shared_people")
    .select(
      "id, name, pin_hash, pin_salt, pin_version, failed_count, locked_until",
    )
    .eq("id", id)
    .maybeSingle();
  return data;
}

/** What the page renders. No arithmetic on the balance happens here — see
 * owner_net's comment in SETUP_SHARE.md. Pending rows are returned with their
 * status so the page can keep them out of the headline and say so. */
async function ledgerFor(part: Participant, youName: string) {
  const [space, entries] = await Promise.all([
    supabase
      .from("shared_spaces")
      .select("title, owner_name")
      .eq("id", part.space_id)
      .maybeSingle(),
    supabase
      .from("shared_entries")
      .select("id, kind, total, payer_name, shares, note, occurred_on, status")
      .eq("space_id", part.space_id)
      .order("occurred_on", { ascending: false })
      .order("created_at", { ascending: false })
      .limit(200),
  ]);

  const ownerName = space.data?.owner_name ?? "They";
  const rows = (entries.data ?? []).map((e: Record<string, unknown>) => {
    const shares = (e.shares ?? {}) as Record<string, number>;
    return {
      id: e.id,
      kind: e.kind,
      total: Number(e.total),
      payerName: e.payer_name,
      yourShare: Number(shares[youName] ?? 0),
      note: e.note,
      on: e.occurred_on,
      status: e.status,
    };
  });

  return {
    title: space.data?.title ?? null,
    ownerName,
    // Positive = the owner is owed, i.e. the guest owes.
    ownerNet: Number(part.owner_net),
    you: youName,
    entries: rows,
  };
}

// ---------------------------------------------------------------- actions

async function open(payload: Record<string, unknown>): Promise<Response> {
  const part = await participantByToken(payload?.t);
  if (!part) return json({ error: "link not active" }, 404);
  const person = await personById(part.person_id);
  if (!person) return json({ error: "link not active" }, 404);

  const space = await supabase
    .from("shared_spaces")
    .select("owner_name")
    .eq("id", part.space_id)
    .maybeSingle();
  const base = {
    name: person.name,
    ownerName: space.data?.owner_name ?? "They",
  };

  // Best-effort; a failure here must never cost the guest their page.
  supabase
    .from("shared_participants")
    .update({ last_seen_at: new Date().toISOString() })
    .eq("token", part.token)
    .then(() => {});

  const claims = await readSession(payload?.s);
  if (
    claims &&
    claims.p === part.person_id &&
    claims.sp === part.space_id &&
    claims.v === person.pin_version
  ) {
    return json({
      ...base,
      state: "ok",
      ledger: await ledgerFor(part, person.name),
    });
  }

  if (!person.pin_hash) return json({ ...base, state: "claim" });

  const locked = person.locked_until
    ? Date.parse(person.locked_until) - Date.now()
    : 0;
  return json({
    ...base,
    state: "login",
    lockedFor: locked > 0 ? Math.ceil(locked / 1000) : 0,
  });
}

async function claim(payload: Record<string, unknown>): Promise<Response> {
  const pin = String(payload?.pin ?? "");
  if (!/^\d{4}$/.test(pin)) return json({ error: "four digits" }, 400);

  const part = await participantByToken(payload?.t);
  if (!part) return json({ error: "link not active" }, 404);
  const person = await personById(part.person_id);
  if (!person) return json({ error: "link not active" }, 404);
  if (person.pin_hash) {
    return json({ error: "already claimed" }, 409);
  }

  const salt = crypto.getRandomValues(new Uint8Array(16));
  const { error } = await supabase
    .from("shared_people")
    .update({
      pin_hash: await hashPin(pin, salt),
      pin_salt: b64url(salt),
      pin_set_at: new Date().toISOString(),
      failed_count: 0,
      locked_until: null,
      pin_reset_requested_at: null,
    })
    .eq("id", person.id)
    // Only if it is still unclaimed: two people opening a forwarded link at
    // the same moment must not both believe they set the PIN.
    .is("pin_hash", null);
  if (error) throw error;

  return json({
    s: await mintSession(person.id, part.space_id, person.pin_version),
    ledger: await ledgerFor(part, person.name),
  });
}

async function login(payload: Record<string, unknown>): Promise<Response> {
  const pin = String(payload?.pin ?? "");
  const part = await participantByToken(payload?.t);
  if (!part) return json({ error: "link not active" }, 404);
  const person = await personById(part.person_id);
  if (!person) return json({ error: "link not active" }, 404);
  if (!person.pin_hash || !person.pin_salt) {
    return json({ error: "not claimed", state: "claim" }, 409);
  }

  // Checked before any hashing, so a locked identity costs no CPU at all —
  // otherwise the lockout is itself a way to burn the function's budget.
  const lockedFor = person.locked_until
    ? Date.parse(person.locked_until) - Date.now()
    : 0;
  if (lockedFor > 0) {
    return json({ error: "locked", lockedFor: Math.ceil(lockedFor / 1000) }, 429);
  }

  const attempt = await hashPin(pin, unb64url(person.pin_salt));
  if (!sameSecret(attempt, person.pin_hash)) {
    const failed = (person.failed_count ?? 0) + 1;
    const until = failed >= MAX_FAILS
      ? new Date(Date.now() + lockMinutes(failed) * 60000).toISOString()
      : null;
    await supabase
      .from("shared_people")
      .update({ failed_count: failed, locked_until: until })
      .eq("id", person.id);
    return json(
      until
        ? { error: "locked", lockedFor: lockMinutes(failed) * 60 }
        : { error: "wrong pin", left: MAX_FAILS - failed },
      until ? 429 : 401,
    );
  }

  await supabase
    .from("shared_people")
    .update({ failed_count: 0, locked_until: null })
    .eq("id", person.id);

  return json({
    s: await mintSession(person.id, part.space_id, person.pin_version),
    ledger: await ledgerFor(part, person.name),
  });
}

async function add(payload: Record<string, unknown>): Promise<Response> {
  const claims = await readSession(payload?.s);
  if (!claims) return json({ error: "session expired" }, 401);
  const part = await participantBySession(claims);
  if (!part) return json({ error: "link not active" }, 404);
  const person = await personById(part.person_id);
  if (!person || person.pin_version !== claims.v) {
    return json({ error: "session expired" }, 401);
  }

  const space = await supabase
    .from("shared_spaces")
    .select("owner_name")
    .eq("id", part.space_id)
    .maybeSingle();
  const ownerName = space.data?.owner_name ?? "";

  const kind = payload?.kind === "settlement" ? "settlement" : "expense";
  const total = Number(payload?.total ?? 0);
  if (!isFinite(total) || total <= 0) return json({ error: "amount" }, 400);

  // The payer has to be somebody in this space, and the guest can only ever
  // name themselves or the owner — otherwise a share link becomes a way to
  // write entries about people who never agreed to be in it.
  const payer = String(payload?.payer ?? person.name);
  if (payer !== person.name && payer !== ownerName) {
    return json({ error: "payer" }, 400);
  }

  const rawShares = (payload?.shares ?? {}) as Record<string, unknown>;
  const shares: Record<string, number> = {};
  for (const [who, amount] of Object.entries(rawShares)) {
    if (who !== person.name && who !== ownerName) continue;
    const n = Number(amount);
    if (isFinite(n) && n > 0) shares[who] = n;
  }
  if (Object.keys(shares).length === 0) return json({ error: "shares" }, 400);

  // The entry has to involve the owner — they either paid, or owe part of it.
  // Anything else is a line about two other people, which a pairwise ledger
  // cannot represent and the owner has no way to accept.
  if (payer !== ownerName && !(ownerName in shares)) {
    return json({ error: "does not involve the owner" }, 400);
  }

  const on = String(payload?.on ?? "").match(/^\d{4}-\d{2}-\d{2}$/)
    ? String(payload?.on)
    : new Date().toISOString().slice(0, 10);

  const { error } = await supabase.from("shared_entries").insert({
    owner_id: part.owner_id,
    space_id: part.space_id,
    author_person_id: person.id,
    kind,
    total,
    payer_name: payer,
    shares,
    note: String(payload?.note ?? "").slice(0, 200) || null,
    occurred_on: on,
    status: "pending",
  });
  if (error) throw error;

  return json({ ledger: await ledgerFor(part, person.name) });
}

async function forgot(payload: Record<string, unknown>): Promise<Response> {
  const part = await participantByToken(payload?.t);
  if (part) {
    await supabase
      .from("shared_people")
      .update({ pin_reset_requested_at: new Date().toISOString() })
      .eq("id", part.person_id);
  }
  // Always the same answer. A different response for an unknown token would
  // make this endpoint a free way to test whether a guessed link is real.
  return json({ ok: true });
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS });
  }
  try {
    if (req.method !== "POST") {
      return json({ error: "POST only" }, 405);
    }
    if (!PEPPER || !SESSION_SECRET) {
      return json({ error: "share secrets not configured" }, 500);
    }
    const payload = await req.json();
    switch (String(payload?.action ?? "")) {
      case "open":
        return await open(payload);
      case "claim":
        return await claim(payload);
      case "login":
        return await login(payload);
      case "add":
        return await add(payload);
      case "forgot":
        return await forgot(payload);
      default:
        return json({ error: "unknown action" }, 400);
    }
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
