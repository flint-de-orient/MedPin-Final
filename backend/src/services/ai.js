// AI provider for MedPin: Gemini (GEMINI_API_KEY) or Claude (ANTHROPIC_API_KEY).
// With no key, `complete()` returns null and callers fall back to non-AI behaviour.
//
//   complete({ system, messages, effort?, format?, maxTokens?, vision? })
//   completeJson({ system, messages, schema, effort?, vision? })  → { ..., data }
//   embed(text) → number[] | null   (Gemini only)
//
// `messages` use the Anthropic shape: { role: 'user'|'assistant', content: string | blocks }.
// Blocks: { type:'text', text } and { type:'document'|'image', source:{ type:'base64', media_type, data } }.
const env = require('../config/env');

const provider = () => env.ai.provider;
const enabled = () => provider() === 'gemini' ? Boolean(env.ai.gemini.apiKey) : provider() === 'anthropic' ? Boolean(env.ai.apiKey) : false;
const modelName = () => (provider() === 'gemini' ? env.ai.gemini.chatModel : provider() === 'anthropic' ? env.ai.model : null);

// ── Claude ────────────────────────────────────────────────

let anthropic;
async function claudeComplete({ system, messages, effort, format, maxTokens, timeoutMs }) {
  if (!anthropic) {
    const Anthropic = require('@anthropic-ai/sdk');
    anthropic = new Anthropic({ apiKey: env.ai.apiKey });
  }
  const started = Date.now();
  const response = await anthropic.beta.messages.create({
    model: env.ai.model,
    max_tokens: maxTokens,
    betas: ['server-side-fallback-2026-07-01'],
    fallbacks: 'default', // on a safety decline, the API re-runs on its recommended fallback model
    system,
    messages,
    output_config: { effort, ...(format ? { format } : {}) },
  }, timeoutMs ? { timeout: timeoutMs, maxRetries: 1 } : undefined);
  const refused = response.stop_reason === 'refusal';
  return {
    text: refused ? '' : response.content.filter((b) => b.type === 'text').map((b) => b.text).join('\n').trim(),
    refused,
    model: response.model,
    latencyMs: Date.now() - started,
    inputTokens: response.usage?.input_tokens,
    outputTokens: response.usage?.output_tokens,
  };
}

// ── Gemini (REST) ─────────────────────────────────────────

const GEMINI = 'https://generativelanguage.googleapis.com/v1beta';

const toParts = (content) => {
  if (typeof content === 'string') return [{ text: content }];
  return content.map((b) => {
    if (b.type === 'text') return { text: b.text };
    if ((b.type === 'document' || b.type === 'image') && b.source?.type === 'base64') {
      return { inlineData: { mimeType: b.source.media_type, data: b.source.data } };
    }
    return { text: '' };
  });
};

/** Gemini's older `responseSchema` doesn't accept `additionalProperties`. */
const stripForGemini = (schema) => {
  if (Array.isArray(schema)) return schema.map(stripForGemini);
  if (!schema || typeof schema !== 'object') return schema;
  const out = {};
  for (const [k, v] of Object.entries(schema)) if (k !== 'additionalProperties') out[k] = stripForGemini(v);
  return out;
};

async function geminiCall(model, body, timeoutMs = 120000) {
  const res = await fetch(`${GEMINI}/models/${model}:generateContent`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'x-goog-api-key': env.ai.gemini.apiKey },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(timeoutMs),
  });
  const json = await res.json().catch(() => ({}));
  return { ok: res.ok, status: res.status, json };
}

async function geminiComplete({ system, messages, format, maxTokens, vision, effort, timeoutMs }) {
  const model = vision ? env.ai.gemini.visionModel : env.ai.gemini.chatModel;
  const started = Date.now();
  const body = {
    systemInstruction: system ? { parts: [{ text: system }] } : undefined,
    contents: messages.map((m) => ({ role: m.role === 'assistant' ? 'model' : 'user', parts: toParts(m.content) })),
    generationConfig: {
      maxOutputTokens: maxTokens,
      ...(format ? { responseMimeType: 'application/json', responseJsonSchema: format.schema } : {}),
      ...(effort === 'low' ? { thinkingConfig: { thinkingLevel: 'low' } } : {}),
    },
  };
  let r = await geminiCall(model, body, timeoutMs);
  if (!r.ok && r.status === 400 && body.generationConfig.thinkingConfig && /thinking/i.test(JSON.stringify(r.json))) {
    delete body.generationConfig.thinkingConfig; // a model without thinking levels
    r = await geminiCall(model, body, timeoutMs);
  }
  if (!r.ok && format && r.status === 400 && /responseJsonSchema|response_json_schema/i.test(JSON.stringify(r.json))) {
    // Older model: fall back to the OpenAPI-style schema field.
    body.generationConfig = { maxOutputTokens: maxTokens, responseMimeType: 'application/json', responseSchema: stripForGemini(format.schema) };
    r = await geminiCall(model, body, timeoutMs);
  }
  if (!r.ok) throw new Error(`Gemini ${r.status}: ${r.json?.error?.message || 'request failed'}`);
  const cand = r.json.candidates?.[0];
  const refused = Boolean(r.json.promptFeedback?.blockReason) || ['SAFETY', 'PROHIBITED_CONTENT', 'BLOCKLIST', 'SPII'].includes(cand?.finishReason);
  const text = refused ? '' : (cand?.content?.parts || []).filter((p) => p.text && !p.thought).map((p) => p.text).join('').trim();
  return {
    text,
    refused,
    truncated: cand?.finishReason === 'MAX_TOKENS',
    model,
    latencyMs: Date.now() - started,
    inputTokens: r.json.usageMetadata?.promptTokenCount,
    outputTokens: r.json.usageMetadata?.candidatesTokenCount,
  };
}

// ── Public ────────────────────────────────────────────────

/**
 * One assistant turn.
 * @returns {Promise<null | {text, refused, model, latencyMs, inputTokens, outputTokens}>}
 */
async function complete({ system, messages, effort = 'medium', format, maxTokens = 8192, vision = false, timeoutMs }) {
  if (!enabled()) return null;
  if (provider() === 'gemini') return geminiComplete({ system, messages, format, maxTokens, vision, effort, timeoutMs });
  return claudeComplete({ system, messages, effort, format, maxTokens, timeoutMs });
}

/** Structured JSON answer matching `schema`. Returns { ...result, data } or null. */
async function completeJson({ system, messages, schema, effort = 'medium', vision = false, maxTokens = 8192, timeoutMs }) {
  const out = await complete({ system, messages, effort, vision, maxTokens, timeoutMs, format: { type: 'json_schema', schema } });
  if (!out) return null;
  if (out.refused || !out.text) return { ...out, data: null };
  try {
    return { ...out, data: JSON.parse(out.text) };
  } catch {
    return { ...out, data: null };
  }
}

/** Text embedding for knowledge-base search (Gemini only). */
async function embed(text) {
  if (provider() !== 'gemini' || !env.ai.gemini.apiKey || !text) return null;
  const res = await fetch(`${GEMINI}/models/${env.ai.gemini.embedModel}:embedContent`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'x-goog-api-key': env.ai.gemini.apiKey },
    body: JSON.stringify({ content: { parts: [{ text: String(text).slice(0, 8000) }] } }),
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(`Gemini embed ${res.status}: ${json?.error?.message || 'failed'}`);
  return json.embedding?.values || null;
}

const cosine = (a, b) => {
  let dot = 0;
  let na = 0;
  let nb = 0;
  for (let i = 0; i < Math.min(a.length, b.length); i += 1) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  return na && nb ? dot / Math.sqrt(na * nb) : 0;
};

module.exports = { enabled, provider, modelName, complete, completeJson, embed, cosine };
