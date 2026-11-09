// Abbreviate a member/subscriber count like Telegram: 33163 → "33.1K", 1500000 → "1.5M".
// Values are truncated (not rounded), matching the official clients.
function trimTo1(x: number): string {
  const t = Math.floor(x * 10) / 10;
  if (t === Math.floor(t)) {
    return `${Math.floor(t)}`;
  }
  return `${t}`;
}

export function formatMemberCount(n: number): string {
  if (n >= 1000000) {
    return `${trimTo1(n / 1000000)}M`;
  }
  if (n >= 1000) {
    return `${trimTo1(n / 1000)}K`;
  }
  return `${n}`;
}
