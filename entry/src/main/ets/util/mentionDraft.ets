// Draft-text helpers for mentioning a group member. Kept out of ChatPage so
// the string handling is unit-testable on its own.

// The text a mention inserts: '@username' when the member has a public one,
// otherwise the bare display name (matching the '@' suggestion panel — the
// send path is plain text, so a name-only mention carries no entity).
export function mentionToken(name: string, username: string): string {
  if (username !== '') {
    return `@${username}`;
  }
  return name.trim();
}

// Append `token` to `draft`, separated by a single space, always leaving a
// trailing space so the next word does not glue onto the mention. Repeating
// the mention that already trails the draft is a no-op.
export function appendMention(draft: string, token: string): string {
  if (token === '') {
    return draft;
  }
  if (alreadyTrailing(draft, token)) {
    return draft.endsWith(' ') ? draft : `${draft} `;
  }
  if (draft === '' || endsWithSpace(draft)) {
    return `${draft}${token} `;
  }
  return `${draft} ${token} `;
}

function endsWithSpace(text: string): boolean {
  const last = text.charAt(text.length - 1);
  return last.trim() === '';
}

// True when the draft's last non-space run is exactly this mention — guarded
// by a word boundary so '@alicia' does not swallow a fresh '@alice'.
function alreadyTrailing(draft: string, token: string): boolean {
  const trimmed = draft.replace(/\s+$/, '');
  if (!trimmed.endsWith(token)) {
    return false;
  }
  const head = trimmed.substring(0, trimmed.length - token.length);
  return head === '' || endsWithSpace(head);
}

// 草稿末尾正在输入的 @ 提及查询；不是在输入提及就返回 null。
//
// **issue #95**：原本内联写着 /(?:^|\s)@([a-zA-Z0-9_]*)$/，只认 ASCII——用户打
// 「@张」直接不匹配，候选面板根本不出，于是只能按用户名 @，按名字 @ 不了。
// 后端 searchChatMembers 本来就同时按用户名和显示名匹配，卡住的一直是这个判定。
//
// 现在放宽成"除空白和 @ 之外的任意字符"：
//
//   · **@ 必须在开头或空白之后** —— 否则 mail@example.com 会被当成提及；
//   · **查询里不含空白** —— 后面打了空格就说明提及输完了，面板该收起来。
//     Telegram 允许名字里有空格，但那样就没法判断提及在哪儿结束，会把后面
//     整句话都吃进查询里；宁可让用户少打几个字后从候选里选。
//   · **查询里不含 @** —— 第二个 @ 应该开启一次新的提及，而不是被吞进上一个。
//
// 这个判定原来在 ChatPage 里出现两次（触发一次、请求回来防抖校验一次），
// 两边必须完全一致，否则会出现"面板弹出来了但结果被丢掉"。收成一个函数。
export function mentionQueryOf(draft: string): string | null {
  const m = draft.match(/(?:^|\s)@([^\s@]*)$/);
  return m !== null ? m[1] : null;
}
