const OPENAI_API_URL = 'https://api.openai.com/v1/responses';

const jsonHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
  'Content-Type': 'application/json',
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

function send(res, status, body) {
  res.status(status);
  Object.entries(jsonHeaders).forEach(([key, value]) => res.setHeader(key, value));
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

function extractOutputText(response) {
  if (typeof response.output_text === 'string') return response.output_text;

  for (const item of response.output || []) {
    for (const content of item.content || []) {
      if (typeof content.text === 'string') return content.text;
    }
  }

  return null;
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
  Object.entries(jsonHeaders).forEach(([key, value]) => res.setHeader(key, value));

  if (req.method === 'OPTIONS') {
    res.status(204).end();
    return;
  }

  if (req.method !== 'POST') {
    send(res, 405, { error: 'Method not allowed' });
    return;
  }

  if (!process.env.OPENAI_API_KEY) {
    send(res, 503, { error: 'AI parser is not configured' });
    return;
  }

  const body = parseBody(req);
  const input = String(body.input || '').trim();

  if (!input) {
    send(res, 400, { error: 'Missing input' });
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
          offlinePreview: Array.isArray(body.offlinePreview) ? body.offlinePreview : [],
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
    send(res, 502, { error: 'AI parser request failed' });
    return;
  }

  if (!openaiResponse.ok) {
    send(res, openaiResponse.status, {
      error: 'OpenAI request failed',
      detail: data?.error?.message || null,
    });
    return;
  }

  const outputText = extractOutputText(data);
  if (!outputText) {
    send(res, 502, { error: 'AI parser returned no text' });
    return;
  }

  try {
    const parsed = JSON.parse(outputText);
    send(res, 200, parsed);
  } catch {
    send(res, 502, { error: 'AI parser returned invalid JSON' });
  }
};
