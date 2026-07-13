// Shared JSON-body validation primitives used by every /v1/ai/generate input
// validator (src/generate.ts's "chat"/"extract" validators and src/relay.ts's
// "report" validator). Centralized here so the two security invariants that
// must hold identically across all three AI kinds — reject unknown fields
// outright (never silently drop them), reject base64/attachment-shaped
// strings anywhere in free text — are enforced by one piece of code rather
// than three copies that could drift.

export interface ValidationResult<T> {
  ok: boolean;
  value?: T;
  errors: string[];
}

// Long unbroken runs of base64-alphabet characters are the shape of embedded
// image/PDF/attachment data (or any other binary blob) — none of the AI
// kinds accept those, per the "reject attachments/base64" requirement and
// docs/ROADMAP.md Part 4 §2's data-boundary principle (engine-derived
// structured data and user-typed text only, never raw documents). 300 chars
// is comfortably longer than any legitimate sentence but far shorter than
// even a tiny image, so it catches attachment-shaped payloads without
// false-positiving on normal prose.
export const BASE64_BLOB_PATTERN = /^[A-Za-z0-9+/_-]{300,}={0,2}$/;

export function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function checkUnknownKeys(obj: Record<string, unknown>, allowed: Set<string>, path: string, errors: string[]): void {
  for (const key of Object.keys(obj)) {
    if (!allowed.has(key)) {
      errors.push(`${path}.${key}: unknown field`);
    }
  }
}

export function checkStringField(
  obj: Record<string, unknown>,
  key: string,
  path: string,
  maxLength: number,
  required: boolean,
  errors: string[]
): string | undefined {
  const value = obj[key];
  if (value === undefined || value === null) {
    if (required) errors.push(`${path}.${key}: required`);
    return undefined;
  }
  if (typeof value !== "string") {
    errors.push(`${path}.${key}: must be a string`);
    return undefined;
  }
  if (value.length > maxLength) {
    errors.push(`${path}.${key}: exceeds max length ${maxLength}`);
    return undefined;
  }
  if (BASE64_BLOB_PATTERN.test(value.replace(/\s+/g, ""))) {
    errors.push(`${path}.${key}: looks like binary/base64 data, which is not accepted`);
    return undefined;
  }
  return value;
}
