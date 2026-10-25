/**
 * SePay → MBB Money webhook relay.
 *
 * Why this exists
 * ---------------
 * iOS suspends (or kills) a backgrounded app, so a phone cannot be listening
 * for a bank push. SePay, however, *can* push — it already sees the MB Bank
 * notification server-side. This Worker receives that push and parks it in a
 * queue the app drains on next launch (or on every foreground tick).
 *
 * Flow
 * ----
 *   MB Bank → SePay → POST /sepay  (this Worker)
 *                        ├─ verify HMAC/auth
 *                        ├─ normalise into the app's row shape
 *                        ├─ POST to Firebase RTDB (or D1) as an inbox item
 *                        └─ 200 immediately (SePay retries on non-2xx)
 *
 *   App → GET /pull?since=<ms>  → returns queued rows, app de-dupes by key
 *
 * The app already stores `sepay:<id>` as its reference number, so replaying the
 * same webhook never creates a duplicate — the inbox can safely be re-delivered.
 *
 * Deploy
 * ------
 *   1. `npm i -g wrangler && wrangler login`
 *   2. Create a KV namespace:  `wrangler kv namespace create INBOX`
 *   3. Put the returned id into wrangler.toml below.
 *   4. `wrangler secret put SEPAY_WEBHOOK_SECRET`   (any long random string)
 *   5. `wrangler secret put APP_PULL_TOKEN`         (any long random string)
 *   6. `wrangler deploy`  → copy the https://…workers.dev URL
 *   7. In SePay dashboard: Webhooks → add URL `<worker>/sepay`,
 *      select "Có mã giao dịch" / "Chuyển khoản", set the auth header to
 *      `Authorization: Bearer <SEPAY_WEBHOOK_SECRET>`.
 *   8. In the app settings, paste the Worker URL + APP_PULL_TOKEN.
 */

/** Rows older than this are dropped on pull — the regular SePay API covers them. */
const INBOX_TTL_MS = 30 * 24 * 60 * 60 * 1000;

/** Hard cap so a misconfigured sender cannot grow storage without bound. */
const MAX_INBOX = 2000;

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders() });
    }

    switch (url.pathname) {
      case '/sepay':
        return handleSepayWebhook(request, env, ctx);
      case '/pull':
        return handlePull(request, env);
      case '/health':
        return json({ ok: true, ts: Date.now() });
      default:
        return json({ error: 'not found' }, 404);
    }
  },
};

// ---------------------------------------------------------------- webhook in

async function handleSepayWebhook(request, env, ctx) {
  if (request.method !== 'POST') {
    return json({ error: 'method not allowed' }, 405);
  }

  // SePay sends `Authorization: Bearer <secret>` when configured; also accept
  // the older `?token=` form so the dashboard can be set up either way.
  const auth = request.headers.get('Authorization') || '';
  const bearer = auth.replace(/^Bearer\s+/i, '').trim();
  const queryToken = new URL(request.url).searchParams.get('token') || '';
  const provided = bearer || queryToken;

  if (!constantTimeEqual(provided, env.SEPAY_WEBHOOK_SECRET)) {
    return json({ error: 'unauthorized' }, 401);
  }

  let payload;
  try {
    payload = await request.json();
  } catch {
    return json({ error: 'invalid json' }, 400);
  }

  const row = normalise(payload);
  if (!row) {
    // Acknowledge anyway: SePay retries non-2xx, and retrying a payload we
    // cannot parse will never succeed.
    return json({ ok: true, skipped: 'unrecognised payload' });
  }

  // The app only tracks spending; income is acknowledged but not queued, so the
  // inbox stays small and the list stays focused.
  if (row.isIncome) {
    return json({ ok: true, skipped: 'income' });
  }

  ctx.waitUntil(enqueue(env, row));
  return json({ ok: true, key: row.key });
}

/**
 * Maps SePay's webhook payload to the app's row shape.
 *
 * SePay is not consistent across payload versions: transaction ids appear as
 * `id`, `transactionId` or `referenceCode`, amounts as numbers or strings, and
 * transfer type as `transferType` ("in"/"out") or a signed amount. Each of
 * those is handled rather than assuming one shape.
 */
function normalise(p) {
  if (!p || typeof p !== 'object') return null;

  const rawAmount = p.transferAmount ?? p.amount ?? p.amountIn ?? p.value;
  const amount = Math.round(Math.abs(Number(rawAmount)));
  if (!Number.isFinite(amount) || amount <= 0) return null;

  const type = String(p.transferType ?? p.type ?? '').toLowerCase();
  const isIncome =
    type === 'in' || type === 'credit' || type === 'receive' ||
    (p.transferType === undefined && Number(rawAmount) > 0 && p.amountIn !== undefined);

  const rawDate =
    p.transactionDate ?? p.transaction_date ?? p.when ?? p.occurredAt;
  const at = parseDate(rawDate);

  const content =
    String(p.content ?? p.description ?? p.transaction_content ?? '').trim();

  const id =
    p.id ?? p.transactionId ?? p.referenceCode ?? p.reference_number ??
    p.code ?? null;
  if (id === null) return null;

  return {
    key: `sepay:${id}`,
    amount,
    isIncome,
    at,
    content,
    bank: String(p.bankBrandName ?? p.bank_brand_name ?? p.gateway ?? '').trim() || null,
    receivedAt: Date.now(),
  };
}

function parseDate(raw) {
  if (raw === undefined || raw === null || raw === '') return Date.now();

  // SePay sends "YYYY-MM-DD HH:mm:ss" in Vietnam time; treat it as UTC+7
  // explicitly rather than relying on the Worker's clock being localised.
  const m = String(raw).match(
    /^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2}))?$/,
  );
  if (m) {
    const ms = Date.UTC(
      Number(m[1]),
      Number(m[2]) - 1,
      Number(m[3]),
      Number(m[4]) - 7,
      Number(m[5]),
      Number(m[6] ?? 0),
    );
    return ms;
  }

  const parsed = Date.parse(raw);
  return Number.isNaN(parsed) ? Date.now() : parsed;
}

async function enqueue(env, row) {
  const key = `in_:${row.receivedAt}:${row.key}`;
  await env.INBOX.put(key, JSON.stringify(row), {
    expirationTtl: Math.ceil(INBOX_TTL_MS / 1000),
  });
}

// ------------------------------------------------------------------- pull out

async function handlePull(request, env) {
  if (request.method !== 'GET') {
    return json({ error: 'method not allowed' }, 405);
  }

  const auth = request.headers.get('Authorization') || '';
  const token = auth.replace(/^Bearer\s+/i, '').trim() ||
    new URL(request.url).searchParams.get('token') ||
    '';
  if (!constantTimeEqual(token, env.APP_PULL_TOKEN)) {
    return json({ error: 'unauthorized' }, 401);
  }

  const sinceMs = Number(new URL(request.url).searchParams.get('since') ?? 0);
  const cutoff = Date.now() - INBOX_TTL_MS;

  const rows = [];
  let cursor;
  do {
    const page = await env.INBOX.list({ cursor, limit: 1000 });
    for (const k of page.keys) {
      if (k.name.startsWith('in_:')) rows.push(k.name);
    }
    cursor = page.cursor;
  } while (cursor);

  rows.sort(); // keys embed receivedAt, so lexical order is chronological

  const out = [];
  for (const name of rows) {
    if (out.length >= MAX_INBOX) break;
    const raw = await env.INBOX.get(name);
    if (!raw) continue;
    let row;
    try {
      row = JSON.parse(raw);
    } catch {
      continue;
    }
    if (row.receivedAt < Math.max(cutoff, sinceMs)) continue;
    out.push(row);
  }

  return json({ ok: true, count: out.length, rows: out });
}

// -------------------------------------------------------------------- helpers

/**
 * Compares two strings without an early exit.
 *
 * A plain `===` on a secret leaks its length and prefix through timing, which
 * on a public endpoint is a real (if narrow) attack surface.
 */
function constantTimeEqual(a, b) {
  const left = String(a ?? '');
  const right = String(b ?? '');
  if (!right) return false;
  if (left.length !== right.length) return false;
  let diff = 0;
  for (let i = 0; i < left.length; i++) {
    diff |= left.charCodeAt(i) ^ right.charCodeAt(i);
  }
  return diff === 0;
}

function corsHeaders() {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Authorization, Content-Type',
    'Access-Control-Max-Age': '86400',
  };
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...corsHeaders() },
  });
}

// Exported for the test suite only. These are pure functions with no access to
// `env`, so exposing them cannot widen the Worker's surface area.
export {
  normalise as normaliseForTest,
  parseDate as parseDateForTest,
  constantTimeEqual as constantTimeEqualForTest,
};
