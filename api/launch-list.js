const DEFAULT_WINDOW_MS = 60 * 1000;
const DEFAULT_MAX_REQUESTS = 5;
const SUPABASE_REST_VERSION = 'v1';
const RESEND_API_URL = 'https://api.resend.com/emails';

const rateBuckets = globalThis.__schedaiLaunchListRateBuckets || new Map();
globalThis.__schedaiLaunchListRateBuckets = rateBuckets;

function json(res, status, body) {
  res.status(status);
  res.setHeader('Content-Type', 'application/json');
  res.setHeader('Cache-Control', 'no-store');
  res.end(JSON.stringify(body));
}

function parseBody(req) {
  if (!req.body) return {};
  if (typeof req.body === 'object') return req.body;
  try {
    return JSON.parse(req.body);
  } catch {
    return {};
  }
}

function numberEnv(name, fallback) {
  const value = Number(process.env[name]);
  return Number.isFinite(value) && value > 0 ? value : fallback;
}

function requestKey(req) {
  return String(req.headers['x-forwarded-for'] || '').split(',')[0].trim()
    || req.socket?.remoteAddress
    || 'unknown';
}

function rateLimit(req) {
  const now = Date.now();
  const windowMs = numberEnv('LAUNCH_LIST_RATE_LIMIT_WINDOW_MS', DEFAULT_WINDOW_MS);
  const maxRequests = numberEnv('LAUNCH_LIST_RATE_LIMIT_REQUESTS', DEFAULT_MAX_REQUESTS);
  const key = requestKey(req);
  const bucket = (rateBuckets.get(key) || []).filter((timestamp) => now - timestamp < windowMs);

  if (bucket.length >= maxRequests) {
    const retryAfterSeconds = Math.max(1, Math.ceil((windowMs - (now - bucket[0])) / 1000));
    return { limited: true, retryAfterSeconds };
  }

  bucket.push(now);
  rateBuckets.set(key, bucket);
  return { limited: false, retryAfterSeconds: 0 };
}

function cleanedString(value, maxLength) {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  if (!trimmed) return null;
  return trimmed.slice(0, maxLength);
}

function normalizedEmail(value) {
  const cleaned = cleanedString(value, 254);
  if (!cleaned) return null;
  const email = cleaned.toLowerCase();
  const pattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  return pattern.test(email) ? email : null;
}

function normalizedPhone(value) {
  const cleaned = cleanedString(value, 32);
  if (!cleaned) return null;
  const normalized = cleaned.replace(/[^\d+]/g, '');
  if (normalized.length < 7) return null;
  return normalized.slice(0, 20);
}

function buildPayload(body) {
  const fullName = cleanedString(body.fullName, 120);
  const email = normalizedEmail(body.email);
  const phoneNumber = normalizedPhone(body.phoneNumber);
  const sourcePage = cleanedString(body.sourcePage, 120) || 'launch-list';

  if (!fullName) {
    return { error: 'Please enter your name.' };
  }

  if (!email) {
    return { error: 'Please enter a valid email address.' };
  }

  return {
    payload: {
      full_name: fullName,
      email,
      phone_number: phoneNumber,
      source_page: sourcePage,
      status: 'subscribed',
      confirmation_email_sent_at: null,
    },
  };
}

async function upsertSignup(payload) {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) {
    throw new Error('missing_supabase_config');
  }

  const response = await fetch(
    `${url}/rest/${SUPABASE_REST_VERSION}/launch_list_signups?on_conflict=email`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        apikey: key,
        Authorization: `Bearer ${key}`,
        Prefer: 'resolution=merge-duplicates,return=representation',
      },
      body: JSON.stringify(payload),
    }
  );

  if (!response.ok) {
    throw new Error(`supabase_error_${response.status}`);
  }

  const rows = await response.json().catch(() => []);
  return Array.isArray(rows) ? rows[0] || payload : payload;
}

function confirmationEmailHtml(name) {
  return `
    <div style="font-family: Avenir Next, Segoe UI, sans-serif; color: #102035; line-height: 1.6;">
      <h1 style="margin-bottom: 12px;">You're on the SchedAI launch list</h1>
      <p>Hi ${name},</p>
      <p>Thanks for joining the launch list. We'll let you know when SchedAI is ready to download.</p>
      <p>You do not need to do anything else right now. When launch day arrives, we'll send the details to this email address.</p>
      <p style="margin-top: 24px;">SchedAI</p>
    </div>
  `;
}

async function sendConfirmationEmail(signup) {
  const apiKey = process.env.RESEND_API_KEY;
  const from = process.env.LAUNCH_LIST_FROM_EMAIL;
  if (!apiKey || !from) {
    return false;
  }

  const payload = {
    from,
    to: [signup.email],
    subject: 'You are on the SchedAI launch list',
    html: confirmationEmailHtml(signup.full_name),
  };

  if (process.env.LAUNCH_LIST_REPLY_TO) {
    payload.reply_to = process.env.LAUNCH_LIST_REPLY_TO;
  }

  const response = await fetch(RESEND_API_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify(payload),
  });

  return response.ok;
}

async function markEmailSent(email) {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) return;

  await fetch(
    `${url}/rest/${SUPABASE_REST_VERSION}/launch_list_signups?email=eq.${encodeURIComponent(email)}`,
    {
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
        apikey: key,
        Authorization: `Bearer ${key}`,
      },
      body: JSON.stringify({
        confirmation_email_sent_at: new Date().toISOString(),
      }),
    }
  ).catch(() => null);
}

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    json(res, 405, { error: 'Method not allowed' });
    return;
  }

  const limited = rateLimit(req);
  if (limited.limited) {
    res.setHeader('Retry-After', String(limited.retryAfterSeconds));
    json(res, 429, { error: 'Too many signup attempts. Please try again shortly.' });
    return;
  }

  const honeypot = cleanedString(parseBody(req).company, 120);
  if (honeypot) {
    json(res, 200, { ok: true });
    return;
  }

  const body = parseBody(req);
  const { payload, error } = buildPayload(body);
  if (error) {
    json(res, 400, { error });
    return;
  }

  try {
    const signup = await upsertSignup(payload);
    const emailSent = await sendConfirmationEmail(signup);
    if (emailSent) {
      await markEmailSent(signup.email);
    }

    json(res, 200, {
      ok: true,
      emailSent,
      message: emailSent
        ? 'You are on the launch list. Check your email for confirmation.'
        : 'You are on the launch list.',
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : 'unknown_error';
    if (message === 'missing_supabase_config') {
      json(res, 503, { error: 'Launch list is not configured yet.' });
      return;
    }
    json(res, 500, { error: 'We could not save your signup right now.' });
  }
};
