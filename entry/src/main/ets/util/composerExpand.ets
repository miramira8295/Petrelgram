// 「全屏编辑」入口什么时候出现。
//
// 【为什么不常驻】输入条上已经有附件、表情、机器人菜单、语音/发送四到六个
// 图标，再常驻一个只有长文才用得上的按钮，短消息场景每次都要多避开一个。
// 判据取"这段文字已经在小框里看不全了"：字数过阈值，或者已经折了多行。
export const COMPOSER_EXPAND_MIN_CHARS: number = 120;
export const COMPOSER_EXPAND_MIN_LINES: number = 3;

export function shouldOfferFullscreenEdit(text: string, lines: number): boolean {
  if (text.length >= COMPOSER_EXPAND_MIN_CHARS) {
    return true;
  }
  if (lines >= COMPOSER_EXPAND_MIN_LINES) {
    return true;
  }
  // 行数还没量到（editorLines 为 0）时用换行符兜底：粘贴一段多行文本的那一帧
  // 就该出现入口，而不是等下一次重排。
  let breaks: number = 0;
  for (let i = 0; i < text.length; i++) {
    if (text.charAt(i) === '\n') {
      breaks++;
      if (breaks >= COMPOSER_EXPAND_MIN_LINES - 1) {
        return true;
      }
    }
  }
  return false;
}
