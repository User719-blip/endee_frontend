import { corsHeaders } from '../_shared/cors.ts';

const ENDEE_BASE_URL = Deno.env.get('ENDEE_BASE_URL') ?? '';
const ENDEE_API_KEY = Deno.env.get('ENDEE_API_KEY') ?? '';
const COLLECTION_NAME = Deno.env.get('ENDEE_COLLECTION_NAME') ?? 'codebase';

async function requestEndee(path: string, body: Record<string, unknown>) {
  const url = `${ENDEE_BASE_URL.replace(/\/$/, '')}${path}`;

  const attemptRaw = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: ENDEE_API_KEY,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });

  if (attemptRaw.status === 401 || attemptRaw.status === 403) {
    const attemptBearer = await fetch(url, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${ENDEE_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    });
    return attemptBearer;
  }

  return attemptRaw;
}

Deno.serve(async (req) => {
  try {
    if (req.method === 'OPTIONS') {
      return new Response('ok', { headers: corsHeaders });
    }

    if (!ENDEE_API_KEY) {
      return new Response(JSON.stringify({ error: 'ENDEE_API_KEY is not configured in Supabase secrets.' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    if (!ENDEE_BASE_URL) {
      return new Response(
        JSON.stringify({
          error: 'ENDEE_BASE_URL is not configured. Set it to your Endee API base URL (not the dashboard URL).',
        }),
        {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      );
    }

    const { file, text, vector } = await req.json();
    if (typeof file !== 'string' || typeof text !== 'string' || !Array.isArray(vector)) {
      return new Response(JSON.stringify({ error: 'file, text, and vector are required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const response = await requestEndee(
      `/v1/collections/${COLLECTION_NAME}/points`,
      {
        points: [
          {
            vector,
            payload: { text, file },
          },
        ],
      },
    );

    const rawBody = await response.text();
    let payload: unknown;
    try {
      payload = JSON.parse(rawBody);
    } catch {
      payload = { raw: rawBody };
    }

    if (typeof rawBody === 'string' && rawBody.includes('<title>Login - Endee Dashboard</title>')) {
      return new Response(
        JSON.stringify({
          error:
            'ENDEE_BASE_URL is pointing to the Endee dashboard/login page. Set it to the actual Endee API base URL from Endee docs.',
          raw: 'Received the dashboard login HTML instead of an API response.',
        }),
        {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      );
    }

    if (!response.ok) {
      return new Response(JSON.stringify({ error: payload }), {
        status: response.status,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    return new Response(JSON.stringify({ ok: true, result: payload }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (error) {
    return new Response(
      JSON.stringify({
        error: 'store_document function crashed',
        message: error instanceof Error ? error.message : String(error),
      }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      },
    );
  }
});