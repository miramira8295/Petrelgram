import { describe, expect, it } from '@ohos/hypium';
import {
  caretAfterExternalEdit, isComposerEcho, rememberEmitted
} from '../main/ets/util/composerText';

// 输入框是受控写法：onChange 把文本交给页面，页面再作为 @Param 原样传回来。
// 回声必须认得出来，否则会被当成"外部整段改写"去挪光标——用户 2026-09-18 报的
// 「光标插到前面输入时会莫名跳到最后面」就是这么来的。

export default function composerEchoTest() {
  describe('ComposerEcho', () => {
    it('刚发出去的那份是回声', 0, (): void => {
      const emitted: string[] = rememberEmitted([], 'abc', 6);
      expect(isComposerEcho(emitted, 'abc')).assertTrue();
      expect(isComposerEcho(emitted, 'abd')).assertFalse();
    });

    // 这条是这个判据存在的理由：连打两个字时，页面传回来的往往是**上上次**那份。
    // 只比"上一次"挡不住它。
    it('上上次那份同样是回声', 0, (): void => {
      let emitted: string[] = rememberEmitted([], 'X', 6);
      emitted = rememberEmitted(emitted, 'XY', 6);
      emitted = rememberEmitted(emitted, 'XYZ', 6);
      expect(isComposerEcho(emitted, 'X')).assertTrue();
      expect(isComposerEcho(emitted, 'XY')).assertTrue();
      expect(isComposerEcho(emitted, 'XYZ')).assertTrue();
    });

    it('只留最近若干份，太久的不再算回声', 0, (): void => {
      let emitted: string[] = [];
      for (let i = 0; i < 10; i++) {
        emitted = rememberEmitted(emitted, `v${i}`, 3);
      }
      expect(emitted.length).assertEqual(3);
      expect(isComposerEcho(emitted, 'v9')).assertTrue();
      expect(isComposerEcho(emitted, 'v7')).assertTrue();
      expect(isComposerEcho(emitted, 'v6')).assertFalse();
    });

    it('重复发同一份不占两格，且仍是最新的', 0, (): void => {
      let emitted: string[] = rememberEmitted([], 'a', 3);
      emitted = rememberEmitted(emitted, 'b', 3);
      emitted = rememberEmitted(emitted, 'a', 3);
      expect(emitted.length).assertEqual(2);
      expect(emitted[emitted.length - 1]).assertEqual('a');
    });

    it('rememberEmitted 不改入参', 0, (): void => {
      const original: string[] = ['a'];
      const next: string[] = rememberEmitted(original, 'b', 3);
      expect(original.length).assertEqual(1);
      expect(next.length).assertEqual(2);
    });

    // 真·外部改写仍然要把光标带到改动之后（插表情、@提及补全走这条）。
    it('外部在光标处插入时，光标落在插入内容之后', 0, (): void => {
      expect(caretAfterExternalEdit('ab', 'aXb', 1)).assertEqual(2);
      expect(caretAfterExternalEdit('', '😀', 0)).assertEqual(2);
    });
  });
}
