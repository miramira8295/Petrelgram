import { describe, it, expect } from '@ohos/hypium';
import { caretAfterExternalEdit, pasteFitsLimit, splitPasteAtLimit } from '../main/ets/util/composerText';

// 输入框两条（用户报）：
// ⑤ 粘贴一段文字后点中间某个字再输入，光标会乱跳到末尾；
// ⑥ 复制内容较多时粘贴只进来一半。
export default function composerCaretTest(): void {
  describe('composerText', (): void => {
    it('外部改写文本后的光标：按前后缀的公共部分推，插入点落在新内容之后', 0, (): void => {
      // 在 "abcd" 的 b 后面插入 "XY" → 光标应落在 3（X Y 之后）
      expect(caretAfterExternalEdit('abcd', 'abXYcd', 2)).assertEqual(4);
      // 末尾追加
      expect(caretAfterExternalEdit('abc', 'abcde', 3)).assertEqual(5);
      // 整段替换（换了会话/读回草稿）：落到末尾
      expect(caretAfterExternalEdit('abc', 'zzz', 1)).assertEqual(3);
      // 没变：光标不动
      expect(caretAfterExternalEdit('abc', 'abc', 1)).assertEqual(1);
      // 删除
      expect(caretAfterExternalEdit('abcd', 'ad', 3)).assertEqual(1);
      // 插在中间 / 空框插 emoji（代理对占两个 UTF-16 单元）
      expect(caretAfterExternalEdit('ab', 'aXb', 1)).assertEqual(2);
      expect(caretAfterExternalEdit('', '😀', 0)).assertEqual(2);
    });
    it('粘贴长度判定：现有文本 + 粘贴内容是否超过上限', 0, (): void => {
      expect(pasteFitsLimit(10, 5, 20)).assertTrue();
      expect(pasteFitsLimit(18, 5, 20)).assertFalse();
      expect(pasteFitsLimit(0, 20, 20)).assertTrue();
    });
    it('超限时按上限切成多段，不静默丢字', 0, (): void => {
      const parts: string[] = splitPasteAtLimit('abcdefghij', 4);
      expect(parts.length).assertEqual(3);
      expect(parts[0]).assertEqual('abcd');
      expect(parts[2]).assertEqual('ij');
      expect(splitPasteAtLimit('abc', 10).length).assertEqual(1);
      expect(splitPasteAtLimit('', 10).length).assertEqual(0);
    });
  });
}
