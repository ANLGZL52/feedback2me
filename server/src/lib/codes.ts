import { randomBytes } from 'node:crypto';

/** Flutter `_shortCode()` ile aynı fikir: 8 hex karakter */
export function generateLinkCode(): string {
  return randomBytes(4).toString('hex');
}
