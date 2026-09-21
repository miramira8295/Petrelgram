// 量输入条行高时，该拿哪一段文字去量（issue #209）。
//
// 【为什么不能量 'A'】原来 lineHeightVp() 写死 `textContent: 'A'`。'A' 既没有
// 下伸部也没有上方标记，是拉丁字母里最"矮"的那一档。而输入框真正要画的是
// 草稿，草稿为空时画的是 placeholder——而 placeholder 里塞的是「<昵称> 正在
// 输入…」。昵称带天城文元音符号、泰文上标、或某些 emoji 时，真实行盒比 'A' 高。
//
// 盒子高度是 `.height(editorHeight())` 显式写死的，按 'A' 算就装不下真实内容，
// 文字被挤在固定盒子里往下掉——用户报的「文本位置整体下移」。
//
// 【为什么不是钉一个更大的行高】2026-09-11 已经试过并回退：写死 .lineHeight(22)
// 之后系统换手写体，a/g/p/q/y 这几个下伸最深的字母**整个不画**（占宽度、一点墨
// 都没有）。行盒必须由字体和实际字形决定，我们只负责量。判据见
// ChatComposerInput.lineHeightVp 上方那段注释。
//
// 【为什么只取第一行】要的是"一行有多高"，不是"整段有多高"。measureTextSize 不
// 给约束宽度时按单行排版，带换行符的草稿会被量成多行，那个数乘以行数就错得离谱。
//
// 【为什么要截断】草稿可能上千字，而这个函数在每次 build 里被调用若干次。行高
// 只取决于**出现了哪些字形**，不取决于有多少个——头 64 个字符足够覆盖昵称和
// 绝大多数正文的字形种类，再长也不会让某一行更高。
export const COMPOSER_PROBE_MAX_CHARS: number = 64;

export function composerLineProbe(
  draft: string, placeholder: string, maxChars: number = COMPOSER_PROBE_MAX_CHARS
): string {
  // 画的是哪一段就量哪一段：草稿非空时 placeholder 不显示，反之亦然。
  const shown: string = draft !== '' ? draft : placeholder;
  const breakAt: number = shown.indexOf('\n');
  const firstLine: string = breakAt >= 0 ? shown.substring(0, breakAt) : shown;
  const limit: number = maxChars > 0 ? maxChars : COMPOSER_PROBE_MAX_CHARS;
  return firstLine.length > limit ? firstLine.substring(0, limit) : firstLine;
}
