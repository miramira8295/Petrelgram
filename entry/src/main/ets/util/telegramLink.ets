// Domain used for links we hand OUT (QR codes, copyable profile links) — these
// get opened by other people, often in a browser, so they must resolve.
//
// t.me was put on serverHold by the registry (2026-07) and no longer resolves;
// the official clients moved to telegram.me, so we follow. Links we RECEIVE are
// unaffected: linkNav accepts t.me / telegram.me / telegram.dog alike, and
// TDLib parses invite links locally rather than fetching the domain, so an
// incoming t.me link still opens in-app.
const PUBLIC_LINK_HOST: string = 'telegram.me';

// Shareable link to a public username (user, group, channel or bot).
export function publicLink(username: string): string {
  const name = username.trim().replace('@', '');
  return name !== '' ? `https://${PUBLIC_LINK_HOST}/${name}` : '';
}
