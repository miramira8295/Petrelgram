// Only a picked suggestion creates a sender filter. Typed @text stays text.
export function senderSearchToken(name: string, username: string, userId: number): string {
  return `@${username.trim() || name.trim() || userId.toString()}`;
}

// Editing the completed identity cancels its binding; editing keywords does not.
export function senderSearchKeywords(query: string, token: string, start: number): string | null {
  if (token === '' || start < 0 || query.substring(start, start + token.length) !== token) {
    return null;
  }
  if (start > 0 && !/\s/.test(query.charAt(start - 1))) { return null; }
  const end: number = start + token.length;
  if (end < query.length && !/\s/.test(query.charAt(end))) { return null; }
  return `${query.substring(0, start)}${query.substring(end)}`.trim();
}
