import fs from 'node:fs';
import path from 'node:path';

// The `_deprecated` destination for an existing canonical artifact whose address is about to change, or null when
// there is nothing to keep: no file yet, a suffixed (non-canonical) name, the same address being rewritten, or the
// outgoing address already retired under some `_deprecated` name. Retired generations are numbered `_deprecated`,
// then `_deprecated1`, `_deprecated2`, ...; a new one goes after the highest suffix in use, never into a gap, so the
// numbering stays chronological even where an earlier rollout skipped a number.
export function deprecatedPathFor({dest, name, address}) {
  if (name.includes('__') || !fs.existsSync(dest)) return null;
  let existing;
  try { existing = JSON.parse(fs.readFileSync(dest, 'utf8')); } catch { return null; }
  const outgoing = String(existing.address || '').toLowerCase();
  if (outgoing === String(address).toLowerCase()) return null;

  const dir = path.dirname(dest);
  const pattern = new RegExp(`^${name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}_deprecated(\\d*)\\.json$`);
  let highest = -1;
  for (const file of fs.readdirSync(dir)) {
    const match = file.match(pattern);
    if (!match) continue;
    try {
      const retired = JSON.parse(fs.readFileSync(path.join(dir, file), 'utf8'));
      if (String(retired.address || '').toLowerCase() === outgoing) return null;
    } catch { /* an unreadable record still occupies its number */ }
    highest = Math.max(highest, match[1] === '' ? 0 : Number(match[1]));
  }
  const next = highest + 1;
  return path.join(dir, `${name}_deprecated${next === 0 ? '' : next}.json`);
}
