// 输入框的两条纯判据（用户报的 ⑤ 光标乱跳 / ⑥ 粘贴只进来一半）。
//
// 【⑤ 为什么会乱跳】给 TextArea 的 text 重新赋值，组件就把光标放到末尾。
// 真正的元凶是**打字本身的回声**：原来是受控写法 `text: this.draft`，每打一个字
// 页面都把同一份文本经 @Param 传回来，输入框再被赋一次值（#219-1，[Caret] 探针
// 实测：光标先落对、4ms 后被挪到末尾，期间我们一次都没调 caretPosition）。
// 已改成组件自有 @Local + `!!` 双向绑定（ChatComposerInput.editorText），打字不再回灌。
// 09-18 那版"记住最近几份、认出回声就不挪光标"方向错了，已删。
//
// 页面**真的**整段改写草稿时（@提及补全、读回草稿、插表情）仍然要自己摆光标，
// 官方做法是 TextAreaController.caretPosition(index)，位置由下面这个函数算。
//
// 这里只算"改写之后光标该落在哪"：比较新旧文本的公共前缀/后缀，得出这次改动的
// 区间，光标落在新内容之后。整段换掉（公共前缀后缀都为空）时落到末尾。
export function caretAfterExternalEdit(before: string, after: string, caret: number): number {
  if (before === after) {
    return caret;
  }
  let prefix: number = 0;
  const maxPrefix: number = Math.min(before.length, after.length);
  while (prefix < maxPrefix && before.charAt(prefix) === after.charAt(prefix)) {
    prefix++;
  }
  let suffix: number = 0;
  while (suffix < maxPrefix - prefix &&
    before.charAt(before.length - 1 - suffix) === after.charAt(after.length - 1 - suffix)) {
    suffix++;
  }
  // 改动区间在新文本里是 [prefix, after.length - suffix)，光标落在它之后。
  return after.length - suffix;
}

// 【⑥ 为什么只进来一半】TextArea 上挂着 maxLength(4096)（Telegram 单条文本的上限），
// 超出的部分被组件**静默截掉**——用户粘一大段进来，看到的就是"粘了一半"。
// 判据分两支：够不够放得下；放不下时按上限切段，交给调用方逐条发送而不是丢字。
export function pasteFitsLimit(currentLength: number, pasteLength: number, limit: number): boolean {
  return currentLength + pasteLength <= limit;
}

export function splitPasteAtLimit(text: string, limit: number): string[] {
  if (text === '' || limit <= 0) {
    return [];
  }
  const out: string[] = [];
  for (let start = 0; start < text.length; start += limit) {
    out.push(text.substring(start, Math.min(text.length, start + limit)));
  }
  return out;
}
