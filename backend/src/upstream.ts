/**
 * Shared retry policy for calls to the Anthropic Messages API.
 *
 * Anthropic rate limits (429) and overload/5xx responses are transient by
 * nature: a single-shot call turns a blip that would clear in half a second
 * into a user-facing failure — historically the dominant cause of AI
 * features feeling unreliable. Every upstream call in this worker goes
 * through `fetchAnthropicWithRetry` so reports, chat, quick-add extraction,
 * and photo extraction all share one policy.
 */

/**
 * Upstream statuses worth retrying: rate limiting (429), Anthropic's
 * overloaded signal (529), request timeout (408), and transient 5xx. A 400
 * or 401 is a bug or a bad key — retrying those just burns wall-clock.
 */
export const UPSTREAM_RETRYABLE_STATUSES = new Set([408, 429, 500, 502, 503, 504, 529]);

/** Total attempts (1 initial + 2 retries) and the base backoff delay. */
export const UPSTREAM_MAX_ATTEMPTS = 3;
export const UPSTREAM_RETRY_BASE_DELAY_MS = 400;

/** Backoff sleep. Workers bill CPU time, not wall-clock, so waiting is cheap. */
function sleep(ms: number): Promise<void> {
  if (ms <= 0) return Promise.resolve();
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export interface UpstreamAttemptResult {
  /** The final response, or `null` when every attempt threw. */
  response: Response | null;
  /** Set only when `response` is null — the last thrown error's message. */
  networkMessage: string | null;
}

/**
 * Calls `doFetch` up to `maxAttempts` times, retrying only transient
 * failures (a thrown fetch, or a status in `UPSTREAM_RETRYABLE_STATUSES`)
 * with exponential backoff. Returns the last response either way — callers
 * keep their existing non-2xx handling unchanged.
 */
export async function fetchAnthropicWithRetry(
  doFetch: typeof fetch,
  url: string,
  init: RequestInit,
  opts: { maxAttempts?: number; retryDelayMs?: number } = {}
): Promise<UpstreamAttemptResult> {
  const maxAttempts = opts.maxAttempts ?? UPSTREAM_MAX_ATTEMPTS;
  const retryDelayMs = opts.retryDelayMs ?? UPSTREAM_RETRY_BASE_DELAY_MS;

  let response: Response | null = null;
  let networkMessage: string | null = null;

  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    response = null;
    networkMessage = null;
    try {
      response = await doFetch(url, init);
    } catch (err) {
      networkMessage = err instanceof Error ? err.message : "Network error calling the AI service.";
    }

    const retryable = response === null || UPSTREAM_RETRYABLE_STATUSES.has(response.status);
    if (!retryable || attempt === maxAttempts) break;
    await sleep(retryDelayMs * 2 ** (attempt - 1));
  }

  return { response, networkMessage };
}
