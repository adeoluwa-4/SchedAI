const OPENAI_API_URL = 'https://api.openai.com/v1/responses';
const DEFAULT_MAX_INPUT_CHARS = 4000;
const DEFAULT_MAX_TASKS = 30;
const DEFAULT_RATE_LIMIT_WINDOW_MS = 60 * 1000;
const DEFAULT_RATE_LIMIT_REQUESTS = 5;

const rateBuckets = globalThis.__schedaiRateBuckets || new Map();
globalThis.__schedaiRateBuckets = rateBuckets;

function configuredList(name) {
  return String(process.env[name] || '')
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean);
}

function numericEnv(name, fallback) {
  const value = Number(process.env[name]);
  return Number.isFinite(value) && value > 0 ? value : fallback;
}

function corsHeaders(req) {
  const allowedOrigins = configuredList('SCHEDAI_ALLOWED_ORIGINS');
  const origin = req.headers.origin;
  const allowOrigin = allowedOrigins.length === 0 || allowedOrigins.includes(origin)
    ? (origin || '*')
    : 'null';

  return {
    'Access-Control-Allow-Origin': allowOrigin,
    'Vary': 'Origin',
  };
}

const jsonHeaders = {
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-SchedAI-API-Token, X-SchedAI-Client-ID',
  'Content-Type': 'application/json',
  'Cache-Control': 'no-store',
};

const taskSchema = {
  type: 'object',
  additionalProperties: false,
  properties: {
    tasks: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        properties: {
          title: {
            type: 'string',
            description: 'Clean imperative task title without date/time filler words.',
          },
          estimatedMinutes: {
            type: 'integer',
            description: 'Best estimate in minutes. Use 30 when not stated.',
          },
          priority: {
            type: 'string',
            enum: ['high', 'medium', 'low'],
          },
          targetDayISO8601: {
            anyOf: [{ type: 'string' }, { type: 'null' }],
            description: 'YYYY-MM-DD when a date/day is specified but no exact clock time is required.',
          },
          scheduledStartISO8601: {
            anyOf: [{ type: 'string' }, { type: 'null' }],
            description: 'Full ISO-8601 datetime with timezone only when the user gave an exact time.',
          },
          scheduledEndISO8601: {
            anyOf: [{ type: 'string' }, { type: 'null' }],
            description: 'Full ISO-8601 datetime with timezone when known or inferable from duration.',
          },
          isPinned: {
            type: 'boolean',
            description: 'True only when scheduledStartISO8601 is not null and the user gave a specific time.',
          },
          notes: {
            anyOf: [{ type: 'string' }, { type: 'null' }],
          },
        },
        required: [
          'title',
          'estimatedMinutes',
          'priority',
          'targetDayISO8601',
          'scheduledStartISO8601',
          'scheduledEndISO8601',
          'isPinned',
          'notes',
        ],
      },
    },
    needsClarification: {
      type: 'boolean',
    },
    clarificationQuestion: {
      anyOf: [{ type: 'string' }, { type: 'null' }],
    },
  },
  required: ['tasks', 'needsClarification', 'clarificationQuestion'],
};

function send(req, res, status, body) {
  res.status(status);
  Object.entries(corsHeaders(req)).forEach(([key, value]) => res.setHeader(key, value));
  Object.entries(jsonHeaders).forEach(([key, value]) => res.setHeader(key, value));
  res.end(JSON.stringify(body));
}

function normalizedBooleanEnv(name, fallback = false) {
  const value = String(process.env[name] || '').trim().toLowerCase();
  if (!value) return fallback;
  if (['1', 'true', 'yes', 'on'].includes(value)) return true;
  if (['0', 'false', 'no', 'off'].includes(value)) return false;
  return fallback;
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

function extractOutputText(response) {
  if (typeof response.output_text === 'string') return response.output_text;

  for (const item of response.output || []) {
    for (const content of item.content || []) {
      if (typeof content.text === 'string') return content.text;
    }
  }

  return null;
}

function normalizedClientID(req) {
  const clientID = String(req.headers['x-schedai-client-id'] || '').trim();
  if (!/^[A-Za-z0-9._-]{8,128}$/.test(clientID)) return null;
  return clientID;
}

function requestIPAddress(req) {
  return String(req.headers['x-forwarded-for'] || '').split(',')[0].trim()
    || req.socket?.remoteAddress
    || 'unknown';
}

function requestKey(req) {
  return normalizedClientID(req) || requestIPAddress(req);
}

function isRateLimited(req) {
  const windowMs = numericEnv('SCHEDAI_RATE_LIMIT_WINDOW_MS', DEFAULT_RATE_LIMIT_WINDOW_MS);
  const maxRequests = numericEnv('SCHEDAI_RATE_LIMIT_REQUESTS', DEFAULT_RATE_LIMIT_REQUESTS);
  const now = Date.now();
  const key = requestKey(req);
  const bucket = (rateBuckets.get(key) || []).filter((timestamp) => now - timestamp < windowMs);

  if (bucket.length >= maxRequests) {
    rateBuckets.set(key, bucket);
    const oldestActive = bucket[0] || now;
    const retryAfterSeconds = Math.max(1, Math.ceil((windowMs - (now - oldestActive)) / 1000));
    return {
      limited: true,
      retryAfterSeconds,
      maxRequests,
      windowMs,
    };
  }

  bucket.push(now);
  rateBuckets.set(key, bucket);

  for (const [bucketKey, timestamps] of rateBuckets.entries()) {
    const active = timestamps.filter((timestamp) => now - timestamp < windowMs);
    if (active.length === 0) rateBuckets.delete(bucketKey);
    else rateBuckets.set(bucketKey, active);
  }

  return {
    limited: false,
    retryAfterSeconds: 0,
    maxRequests,
    windowMs,
  };
}

function tokenAuthorized(req) {
  const tokens = configuredList('SCHEDAI_API_TOKENS');
  if (tokens.length === 0) return true;

  const auth = String(req.headers.authorization || '');
  const bearer = auth.startsWith('Bearer ') ? auth.slice(7).trim() : '';
  const headerToken = String(req.headers['x-schedai-api-token'] || '').trim();
  return tokens.includes(bearer) || tokens.includes(headerToken);
}

function isAIEnabled() {
  return normalizedBooleanEnv('SCHEDAI_AI_ENABLED', true);
}

function blockedClientID(req) {
  const clientID = normalizedClientID(req);
  if (!clientID) return null;
  const blocked = configuredList('SCHEDAI_BLOCKED_CLIENT_IDS');
  return blocked.includes(clientID) ? clientID : null;
}

function clientIDRequired() {
  return normalizedBooleanEnv('SCHEDAI_REQUIRE_CLIENT_ID', false);
}

function clampInt(value, lower, upper, fallback) {
  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.min(Math.max(parsed, lower), upper);
}

function limitedString(value, maxLength) {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  if (!trimmed) return null;
  return trimmed.slice(0, maxLength);
}

function normalizeOfflinePreview(value) {
  const maxTasks = numericEnv('SCHEDAI_MAX_TASKS', DEFAULT_MAX_TASKS);
  if (!Array.isArray(value)) return [];
  return value.slice(0, maxTasks).map((task) => ({
    title: limitedString(task?.title, 140) || 'Task',
    estimatedMinutes: clampInt(task?.estimatedMinutes, 5, 600, 30),
    priority: ['high', 'medium', 'low'].includes(task?.priority) ? task.priority : 'medium',
    targetDayISO8601: limitedString(task?.targetDayISO8601, 40),
    scheduledStartISO8601: limitedString(task?.scheduledStartISO8601, 80),
    scheduledEndISO8601: limitedString(task?.scheduledEndISO8601, 80),
    isPinned: Boolean(task?.isPinned),
    notes: limitedString(task?.notes, 500),
  }));
}

function sanitizeParsedResponse(parsed) {
  const maxTasks = numericEnv('SCHEDAI_MAX_TASKS', DEFAULT_MAX_TASKS);
  if (!parsed || typeof parsed !== 'object' || !Array.isArray(parsed.tasks)) {
    return null;
  }

  const tasks = parsed.tasks.slice(0, maxTasks).map((task) => {
    const title = limitedString(task?.title, 140);
    if (!title) return null;
    const scheduledStart = limitedString(task?.scheduledStartISO8601, 80);

    return {
      title,
      estimatedMinutes: clampInt(task?.estimatedMinutes, 5, 600, 30),
      priority: ['high', 'medium', 'low'].includes(task?.priority) ? task.priority : 'medium',
      targetDayISO8601: limitedString(task?.targetDayISO8601, 40),
      scheduledStartISO8601: scheduledStart,
      scheduledEndISO8601: limitedString(task?.scheduledEndISO8601, 80),
      isPinned: scheduledStart ? Boolean(task?.isPinned) : false,
      notes: limitedString(task?.notes, 500),
    };
  }).filter(Boolean);

  return {
    tasks,
    needsClarification: Boolean(parsed.needsClarification),
    clarificationQuestion: limitedString(parsed.clarificationQuestion, 240),
  };
}

function systemPrompt() {
  return [
    'You are SchedAI, a careful task parser for students and busy people.',
    'Convert natural, messy spoken text into clean task objects.',
    'Use the provided nowISO8601, planningDateISO8601, locale, and timeZone.',
    'Preserve context across connected phrases. Example: "enroll for class A and for class B" means two enroll tasks.',
    'Remove filler like remind me, I need to, on Monday, then, and timestamps from titles.',
    'Do not invent tasks, dates, or clock times. If the user gives only a day/date, set targetDayISO8601 and leave scheduledStartISO8601 null.',
    'If the user gives a specific time, set scheduledStartISO8601 and isPinned true.',
    'If the user gives a duration, use it for estimatedMinutes and scheduledEndISO8601 when a start time exists.',
    'If the text is ambiguous, still return your best safe parse and set needsClarification true with one short question.',
  ].join('\n');
}

module.exports = async function handler(req, res) {
  Object.entries(corsHeaders(req)).forEach(([key, value]) => res.setHeader(key, value));
  Object.entries(jsonHeaders).forEach(([key, value]) => res.setHeader(key, value));

  if (req.method === 'OPTIONS') {
    res.status(204).end();
    return;
  }

  if (req.method !== 'POST') {
    send(req, res, 405, { error: 'Method not allowed' });
    return;
  }

  if (!isAIEnabled()) {
    send(req, res, 503, { error: 'AI features are temporarily disabled' });
    return;
  }

  if (clientIDRequired() && !normalizedClientID(req)) {
    send(req, res, 400, { error: 'Missing client identifier' });
    return;
  }

  if (blockedClientID(req)) {
    send(req, res, 403, { error: 'AI access disabled for this client' });
    return;
  }

  if (!tokenAuthorized(req)) {
    send(req, res, 401, { error: 'Unauthorized' });
    return;
  }

  const rateLimit = isRateLimited(req);
  if (rateLimit.limited) {
    res.setHeader('Retry-After', String(rateLimit.retryAfterSeconds));
    send(req, res, 429, { error: 'Too many requests' });
    return;
  }

  if (!process.env.OPENAI_API_KEY) {
    send(req, res, 503, { error: 'AI parser is not configured' });
    return;
  }

  const body = parseBody(req);
  const input = String(body.input || '').trim();
  const maxInputChars = numericEnv('SCHEDAI_MAX_INPUT_CHARS', DEFAULT_MAX_INPUT_CHARS);

  if (!input) {
    send(req, res, 400, { error: 'Missing input' });
    return;
  }

  if (input.length > maxInputChars) {
    send(req, res, 413, { error: 'Input is too long' });
    return;
  }

  const payload = {
    model: process.env.OPENAI_MODEL || 'gpt-4o-mini',
    input: [
      { role: 'system', content: systemPrompt() },
      {
        role: 'user',
        content: JSON.stringify({
          input,
          nowISO8601: body.nowISO8601 || new Date().toISOString(),
          planningDateISO8601: body.planningDateISO8601 || body.nowISO8601 || new Date().toISOString(),
          timeZone: body.timeZone || 'UTC',
          locale: body.locale || 'en_US',
          offlinePreview: normalizeOfflinePreview(body.offlinePreview),
        }),
      },
    ],
    text: {
      format: {
        type: 'json_schema',
        name: 'schedai_task_parse',
        strict: true,
        schema: taskSchema,
      },
    },
  };

  let openaiResponse;
  let data;
  try {
    openaiResponse = await fetch(OPENAI_API_URL, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(payload),
    });
    data = await openaiResponse.json().catch(() => null);
  } catch {
    send(req, res, 502, { error: 'AI parser request failed' });
    return;
  }

  if (!openaiResponse.ok) {
    send(req, res, openaiResponse.status, { error: 'AI parser request failed' });
    return;
  }

  const outputText = extractOutputText(data);
  if (!outputText) {
    send(req, res, 502, { error: 'AI parser returned no text' });
    return;
  }

  try {
    const parsed = JSON.parse(outputText);
    const sanitized = sanitizeParsedResponse(parsed);
    if (!sanitized) {
      send(req, res, 502, { error: 'AI parser returned invalid task data' });
      return;
    }
    send(req, res, 200, sanitized);
  } catch {
    send(req, res, 502, { error: 'AI parser returned invalid JSON' });
  }
};
