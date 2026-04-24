import { corsHeaders } from '../_shared/cors.ts';

const HF_API_KEY = Deno.env.get('HF_API_KEY') ?? '';
const HF_CHAT_MODELS = [
  'Qwen/Qwen2.5-7B-Instruct',
  'meta-llama/Llama-3.1-8B-Instruct',
  'mistralai/Mistral-7B-Instruct-v0.3',
];

const HF_GENERATION_MODELS = [
  'mistralai/Mistral-7B-Instruct-v0.2',
  'google/gemma-2-2b-it',
  'HuggingFaceH4/zephyr-7b-beta',
];

type AttemptError = {
  strategy: string;
  model: string;
  endpoint: string;
  status: number;
  payload: unknown;
};

function parseJson(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    return { raw: text };
  }
}

function buildFallbackAnswer(context: string, question: string): string {
  const lines = context
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line.length > 0);
  const summary = lines.slice(0, 6).join('\n');

  return [
    'I could not reach a supported generation model right now, so here is a context-grounded fallback.',
    `Question: ${question}`,
    '',
    'Most relevant retrieved snippets:',
    summary || 'No context lines available.',
  ].join('\n');
}

function buildStreamEvent(data: unknown): Uint8Array {
  return new TextEncoder().encode(`data: ${JSON.stringify(data)}\n\n`);
}

function streamTextResponse(text: string, meta: Record<string, unknown>) {
  const encoder = new TextEncoder();
  const chunks = text.match(/\S+\s*/g) ?? [text];
  let index = 0;

  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(buildStreamEvent({ type: 'meta', ...meta }));

      const pump = () => {
        if (index >= chunks.length) {
          controller.enqueue(buildStreamEvent({ type: 'done', ...meta, generated_text: text }));
          controller.close();
          return;
        }

        controller.enqueue(buildStreamEvent({ type: 'token', token: chunks[index] }));
        index += 1;
        setTimeout(pump, 18);
      };

      pump();
    },
    cancel() {},
  });

  return new Response(stream, {
    headers: {
      ...corsHeaders,
      'Content-Type': 'text/event-stream; charset=utf-8',
      'Cache-Control': 'no-cache, no-transform',
      Connection: 'keep-alive',
    },
  });
}

async function tryStreamChatCompletions(prompt: string, errors: AttemptError[]) {
  for (const model of HF_CHAT_MODELS) {
    const endpoint = 'https://router.huggingface.co/v1/chat/completions';
    const response = await fetch(endpoint, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${HF_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model,
        messages: [
          {
            role: 'system',
            content:
              'Answer strictly from the provided context. If context is insufficient, clearly say so.',
          },
          { role: 'user', content: prompt },
        ],
        temperature: 0.2,
        max_tokens: 300,
        stream: true,
      }),
    });

    if (!response.ok || !response.body) {
      const rawBody = await response.text();
      errors.push({
        strategy: 'chat-completions-stream',
        model,
        endpoint,
        status: response.status,
        payload: parseJson(rawBody),
      });
      continue;
    }

    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let buffer = '';
    let answerText = '';

    const stream = new ReadableStream<Uint8Array>({
      async start(controller) {
        controller.enqueue(buildStreamEvent({ type: 'meta', model, endpoint, fallback: false }));

        try {
          while (true) {
            const { done, value } = await reader.read();
            if (done) {
              break;
            }

            buffer += decoder.decode(value, { stream: true });
            const lines = buffer.split('\n');
            buffer = lines.pop() ?? '';

            for (const line of lines) {
              const trimmed = line.trim();
              if (!trimmed.startsWith('data:')) {
                continue;
              }

              const payloadText = trimmed.slice(5).trim();
              if (!payloadText || payloadText === '[DONE]') {
                continue;
              }

              const payload = parseJson(payloadText) as Record<string, unknown>;
              const choices = payload.choices;
              if (!Array.isArray(choices) || choices.length === 0) {
                continue;
              }

              const first = choices[0] as {
                delta?: { content?: unknown };
                message?: { content?: unknown };
              };
              const delta = first?.delta?.content;
              const messageContent = first?.message?.content;
              const token =
                typeof delta === 'string'
                  ? delta
                  : typeof messageContent === 'string'
                    ? messageContent
                    : '';
              if (!token) {
                continue;
              }

              answerText += token;
              controller.enqueue(buildStreamEvent({ type: 'token', token }));
            }
          }

          controller.enqueue(
            buildStreamEvent({
              type: 'done',
              generated_text: answerText,
              model,
              endpoint,
              fallback: false,
            }),
          );
          controller.close();
        } catch (error) {
          controller.enqueue(
            buildStreamEvent({
              type: 'error',
              model,
              endpoint,
              error: String(error),
            }),
          );
          controller.error(error);
        }
      },
    });

    return new Response(stream, {
      headers: {
        ...corsHeaders,
        'Content-Type': 'text/event-stream; charset=utf-8',
        'Cache-Control': 'no-cache, no-transform',
        Connection: 'keep-alive',
      },
    });
  }

  return null;
}

async function tryChatCompletions(prompt: string, errors: AttemptError[]) {
  for (const model of HF_CHAT_MODELS) {
    const endpoint = 'https://router.huggingface.co/v1/chat/completions';
    const response = await fetch(endpoint, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${HF_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model,
        messages: [
          {
            role: 'system',
            content:
              'Answer strictly from the provided context. If context is insufficient, clearly say so.',
          },
          { role: 'user', content: prompt },
        ],
        temperature: 0.2,
        max_tokens: 300,
      }),
    });

    const rawBody = await response.text();
    const payload = parseJson(rawBody) as Record<string, unknown>;
    if (!response.ok) {
      errors.push({
        strategy: 'chat-completions',
        model,
        endpoint,
        status: response.status,
        payload,
      });
      continue;
    }

    const choices = payload.choices;
    if (Array.isArray(choices) && choices.length > 0) {
      const first = choices[0] as { message?: { content?: unknown } };
      const content = first?.message?.content;
      if (typeof content === 'string' && content.trim()) {
        return { generatedText: content, model, endpoint };
      }
    }

    errors.push({
      strategy: 'chat-completions',
      model,
      endpoint,
      status: response.status,
      payload: { error: 'unexpected chat completion format', payload },
    });
  }

  return null;
}

async function tryInferenceGenerate(prompt: string, errors: AttemptError[]) {
  for (const model of HF_GENERATION_MODELS) {
    const endpoint = 'https://router.huggingface.co/hf-inference/models';
    const response = await fetch(`${endpoint}/${model}`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${HF_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        inputs: prompt,
        parameters: {
          max_new_tokens: 300,
          temperature: 0.2,
          return_full_text: false,
        },
        options: {
          wait_for_model: true,
          use_cache: false,
        },
      }),
    });

    const rawBody = await response.text();
    const payload = parseJson(rawBody);

    if (!response.ok) {
      errors.push({
        strategy: 'hf-inference',
        model,
        endpoint,
        status: response.status,
        payload,
      });
      continue;
    }

    if (Array.isArray(payload) && payload.length > 0) {
      const first = payload[0] as { generated_text?: unknown };
      if (typeof first?.generated_text === 'string' && first.generated_text.trim()) {
        return { generatedText: first.generated_text, model, endpoint };
      }
    }

    errors.push({
      strategy: 'hf-inference',
      model,
      endpoint,
      status: response.status,
      payload: { error: 'unexpected generation format', payload },
    });
  }

  return null;
}

async function answerWithFallback(prompt: string, context: string, question: string) {
  const errors: AttemptError[] = [];

  const chatResult = await tryChatCompletions(prompt, errors);
  if (chatResult) {
    return {
      generatedText: chatResult.generatedText,
      model: chatResult.model,
      endpoint: chatResult.endpoint,
      fallback: false,
      attempts: errors,
    };
  }

  const generationResult = await tryInferenceGenerate(prompt, errors);
  if (generationResult) {
    return {
      generatedText: generationResult.generatedText,
      model: generationResult.model,
      endpoint: generationResult.endpoint,
      fallback: false,
      attempts: errors,
    };
  }

  return {
    generatedText: buildFallbackAnswer(context, question),
    model: 'fallback-context-summarizer',
    endpoint: 'internal',
    fallback: true,
    attempts: errors,
  };
}

Deno.serve(async (req) => {
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
    return new Response(JSON.stringify({ error: 'HF_API_KEY format is invalid. It must start with hf_.' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  const { context, question, stream } = await req.json();
  if (typeof context !== 'string' || typeof question !== 'string') {
    return new Response(JSON.stringify({ error: 'context and question are required' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  const prompt = `Answer only from this context.\n\nContext:\n${context}\n\nQuestion:\n${question}`;
  if (stream === true) {
    const streamed = await tryStreamChatCompletions(prompt, []);
    if (streamed) {
      return streamed;
    }

    const fallback = buildFallbackAnswer(context, question);
    return streamTextResponse(fallback, {
      model: 'fallback-context-summarizer',
      endpoint: 'internal',
      fallback: true,
    });
  }

  const result = await answerWithFallback(prompt, context, question);
  return new Response(
    JSON.stringify({
      generated_text: result.generatedText,
      model: result.model,
      endpoint: result.endpoint,
      fallback: result.fallback,
      attempts: result.attempts,
    }),
    { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
  );
});