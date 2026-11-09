export interface ContactNameKey {
  letter: string;
  value: string;
}

// Keep symbols/numbers in #; only whitespace is ignored before the initial.
export function contactNameKey(name: string, transliterate: (text: string) => string): ContactNameKey {
  const source = name.trim();
  let latin = source;
  try { latin = transliterate(source).trim(); } catch (_) { /* Keep a stable fallback. */ }
  const value = latin.toUpperCase().replace(/\s+/g, ' ');
  const first = value.charAt(0);
  return { letter: /^[A-Z]$/.test(first) ? first : '#', value: value };
}

export function compareContactNames(a: ContactNameKey, b: ContactNameKey, aId: number, bId: number): number {
  if (a.letter !== b.letter) {
    if (a.letter === '#') { return 1; }
    if (b.letter === '#') { return -1; }
    return a.letter < b.letter ? -1 : 1;
  }
  if (a.value !== b.value) { return a.value < b.value ? -1 : 1; }
  return aId - bId;
}
