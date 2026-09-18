// 输入框的两条纯判据（用户报的 ⑤ 光标乱跳 / ⑥ 粘贴只进来一半）。
//
// 【⑤ 为什么会乱跳】TextArea 是**受控**写法：`text: this.draft` + onChange 回写 draft。
// 外部（页面）重新给 text 赋值时，组件把光标放到文本末尾——官方示例里要精确控制
// 光标用的是 TextAreaController.caretPosition(index)。我们在补全 @提及、读回草稿、
// 表情插入这些路径上都会整段改写 draft，于是用户在中间插字时光标被顶到最后。
//
// 这里只算"改写之后光标该落在哪"：比较新旧文本的公共前缀/后缀，得出这次改动的
// 区间，光标落在新内容之后。整段换掉（公共前缀后缀都为空）时落到末尾。
// 这次 draft 变化是不是**本组件自己刚发出去那一份的回声**。
//
// 【为什么需要它】输入框是受控写法：onChange 把新文本交给页面，页面存进自己的
// 状态，再作为 @Param 原样传回来。回声和"外部整段改写"（@提及补全、插表情、
// 读回草稿）走的是同一个 @Monitor，光有"和上一次发出去的那份相等"这一道判据挡
// 不住——用户连打两个字时，页面传回来的往往是**上上次**那份，于是被当成外部改写，
// caretAfterExternalEdit 按一对错位的文本算出一个落在末尾附近的位置，光标就
// "莫名跳到最后面"（用户 2026-09-18 实报：光标插到前面输入时会自己跳到末尾）。
//
// 所以记住最近发出去的**若干份**，incoming 命中其中任何一份就是回声。
export function isComposerEcho(recentEmitted: string[], incoming: string): boolean {
  return recentEmitted.indexOf(incoming) >= 0;
}

// 记一份刚发出去的文本。**返回新数组**，不改入参（仓库规矩）。
// 只留最近 limit 份：再久的回声不可能还在路上，留着反而会把一次真实的
// "撤销到几步之前"误判成回声。
export function rememberEmitted(recentEmitted: string[], value: string, limit: number): string[] {
  const next: string[] = recentEmitted.filter((item: string): boolean => item !== value);
  next.push(value);
  return next.length > limit ? next.slice(next.length - limit) : next;
}

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
