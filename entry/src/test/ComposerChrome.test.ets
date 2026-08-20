import { describe, expect, it } from '@ohos/hypium';
import {
  COMPOSER_GAP_MIN, COMPOSER_GAP_TIGHT,
  composerBottomGap, composerPlaceholder, replyKeyboardVisible
} from '../main/ets/util/composerChrome';

export default function composerChromeTest() {
  describe('composerChrome', () => {
    it('键盘起来时收紧底部留白', 0, () => {
      expect(composerBottomGap(320, false, 34)).assertEqual(COMPOSER_GAP_TIGHT);
    });

    it('抽屉打开时同样收紧——哪怕键盘高度是 0', 0, () => {
      // 自定义键盘的高度系统不算作键盘高度，实测 keyboardH 全程为 0。
      // 只判断键盘高度的话这里会错误地留出整条安全区。
      expect(composerBottomGap(0, true, 34)).assertEqual(COMPOSER_GAP_TIGHT);
    });

    it('都没有时按安全区留，且不低于下限', 0, () => {
      expect(composerBottomGap(0, false, 34)).assertEqual(34);
      // 无手势条的设备安全区为 0，仍要留出下限，否则输入框贴着屏幕底边。
      expect(composerBottomGap(0, false, 0)).assertEqual(COMPOSER_GAP_MIN);
      expect(composerBottomGap(0, false, 3)).assertEqual(COMPOSER_GAP_MIN);
    });

    it('机器人键盘三个条件缺一不可', 0, () => {
      expect(replyKeyboardVisible('writable', true, false)).assertTrue();
      // 没发言权时不露脸——那时输入区已经被 join/blocked 条替换了。
      expect(replyKeyboardVisible('joinable', true, false)).assertFalse();
      expect(replyKeyboardVisible('readonly', true, false)).assertFalse();
      // 根本没收到键盘。
      expect(replyKeyboardVisible('writable', false, false)).assertFalse();
      // 用户收起来了。
      expect(replyKeyboardVisible('writable', true, true)).assertFalse();
    });

    it('对方正在输入时占位文字最优先', 0, () => {
      expect(composerPlaceholder('对方正在输入…', true, '请选择')).assertEqual('对方正在输入…');
      expect(composerPlaceholder('对方正在输入…', false, '')).assertEqual('对方正在输入…');
    });

    it('机器人键盘的提示语排第二，且要求它此刻可见', 0, () => {
      expect(composerPlaceholder('', true, '请选择一项')).assertEqual('请选择一项');
      // 收起状态下不该再显示它的提示语——会让人以为键盘还在。
      expect(composerPlaceholder('', false, '请选择一项'))
        .assertEqual('cp_message_placeholder');
    });

    it('提示语只有空白时退回默认', 0, () => {
      expect(composerPlaceholder('', true, '   ')).assertEqual('cp_message_placeholder');
      expect(composerPlaceholder('', true, '')).assertEqual('cp_message_placeholder');
    });

    it('什么都没有时是默认的「消息」', 0, () => {
      expect(composerPlaceholder('', false, '')).assertEqual('cp_message_placeholder');
    });
  });
}
