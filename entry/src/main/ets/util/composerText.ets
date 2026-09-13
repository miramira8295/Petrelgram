// 输入框的两条纯判据（用户报的 ⑤ 光标乱跳 / ⑥ 粘贴只进来一半）。
//
// 【⑤ 为什么会乱跳】TextArea 是**受控**写法：`text: this.draft` + onChange 回写 draft。
// 外部（页面）重新给 text 赋值时，组件把光标放到文本末尾——官方示例里要精确控制
// 光标用的是 TextAreaController.caretPosition(index)。我们在补全 @提及、读回草稿、
// 表情插入这些路径上都会整段改写 draft，于是用户在中间插字时光标被顶到最后。
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
