import { corsHeaders } from '../_shared/cors.ts';

const HF_API_KEY = Deno.env.get('HF_API_KEY') ?? '';
const HF_EMBEDDING_MODEL = 'BAAI/bge-small-en-v1.5';

function meanPool(tokenEmbeddings: number[][]): number[] {
  const dimension = tokenEmbeddings[0].length;
  const sums = new Array<number>(dimension).fill(0);

  for (const token of tokenEmbeddings) {
    for (let i = 0; i < dimension; i++) {
      sums[i] += token[i];
    }
  }

  return sums.map((value) => value / tokenEmbeddings.length);
}

Deno.serve(async (req) => {
  try {
    if (req.method === 'OPTIONS') {
      return new Response('ok', { headers: corsHeaders });
    }

    if (!HF_API_KEY) {
      return new Response(JSON.stringify({ error: 'HF_API_KEY is not configured in Supabase secrets.' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    if (!HF_API_KEY.startsWith('hf_')) {
      return new Response(
        JSON.stringify({
          error: 'HF_API_KEY format is invalid. It must start with hf_.',
        }),
        {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        },
      );
    }

    const { text } = await req.json();
    if (typeof text !== 'string' || !text.trim()) {
      return new Response(JSON.stringify({ error: 'text is required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const response = await fetch(
      `https://router.huggingface.co/hf-inference/models/${HF_EMBEDDING_MODEL}`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${HF_API_KEY}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          inputs: text,
          options: { wait_for_model: true },
          normalize: true,
        }),
      },
    );

    const rawBody = await response.text();
    let payload: unknown;
    try {
      payload = JSON.parse(rawBody);
    } catch {
      payload = { raw: rawBody };
    }

    if (!response.ok) {
      return new Response(JSON.stringify({ error: payload }), {
        status: response.status,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    let embedding: number[];
    if (Array.isArray(payload) && payload.length > 0 && typeof payload[0] === 'number') {
      embedding = payload.map((value: number) => Number(value));
    } else if (Array.isArray(payload) && payload.length > 0 && Array.isArray(payload[0])) {
      embedding = meanPool(payload as number[][]);
    } else {
      return new Response(JSON.stringify({ error: 'unexpected embedding format', payload }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    return new Response(JSON.stringify({ embedding }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (error) {
    return new Response(
      JSON.stringify({
        error: 'embed function crashed',
        message: error instanceof Error ? error.message : String(error),
      }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      },
    );
  }
});