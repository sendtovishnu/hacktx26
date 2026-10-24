import { GoogleGenAI } from '@google/genai';
import type { ZodType } from 'zod';

export type Provider = 'gemini' | 'muse';

const TIMEOUT_MS = 20_000;

export const useMocks = () => process.env.USE_MOCKS === 'true';
const defaultProvider = (): Provider => (process.env.LLM_PROVIDER === 'muse' ? 'muse' : 'gemini');

let gemini: GoogleGenAI | undefined;

async function callGemini(prompt: string): Promise<string> {
  gemini ??= new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY });
  const res = await gemini.models.generateContent({
    model: process.env.GEMINI_MODEL || 'gemini-flash-lite-latest',
    contents: prompt,
    config: { responseMimeType: 'application/json', httpOptions: { timeout: TIMEOUT_MS } },
  });
  return res.text ?? '';
}

// Meta Model API (Muse Spark), OpenAI-compatible chat completions.
async function callMuse(prompt: string): Promise<string> {
  const base = (process.env.META_API_BASE_URL || 'https://api.meta.ai/v1').replace(/\/$/, '');
  const res = await fetch(`${base}/chat/completions`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${process.env.META_API_KEY}` },
    body: JSON.stringify({
      model: process.env.META_MODEL || 'muse-spark-1.3',
      messages: [{ role: 'user', content: prompt }],
    }),
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  if (!res.ok) throw new Error(`Muse ${res.status}: ${(await res.text()).slice(0, 200)}`);
  const body = (await res.json()) as { choices?: { message?: { content?: string } }[] };
  return body.choices?.[0]?.message?.content ?? '';
}

// Models sometimes wrap JSON in ```json fences or add a sentence around it.
function parseJSON(text: string): unknown {
  const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  const raw = (fenced ? fenced[1] : text).trim();
  try {
    return JSON.parse(raw);
  } catch {
    const start = raw.search(/[[{]/);
    const end = Math.max(raw.lastIndexOf('}'), raw.lastIndexOf(']'));
    if (start === -1 || end <= start) throw new Error('no JSON in model output');
    return JSON.parse(raw.slice(start, end + 1));
  }
}

const callers: Record<Provider, (prompt: string) => Promise<string>> = { gemini: callGemini, muse: callMuse };

/**
 * Asks a model for JSON and validates it. Tries the provider twice, then the other
 * provider once, then returns `fallback`. Never throws.
 */
export async function generateJSON<T>(
  prompt: string,
  schema: ZodType<T>,
  fallback: T,
  provider: Provider = defaultProvider(),
): Promise<T> {
  if (useMocks()) return fallback;
  const other: Provider = provider === 'muse' ? 'gemini' : 'muse';
  const fullPrompt = `${prompt}\n\nRespond with a single JSON value only. No markdown, no commentary.`;
  for (const p of [provider, provider, other]) {
    try {
      const parsed = schema.safeParse(parseJSON(await callers[p](fullPrompt)));
      if (parsed.success) return parsed.data;
      console.warn(`[llm] ${p} returned invalid JSON:`, parsed.error.issues.slice(0, 3));
    } catch (e) {
      console.warn(`[llm] ${p} failed:`, (e as Error).message);
    }
  }
  console.warn('[llm] all attempts failed, using fallback');
  return fallback;
}
