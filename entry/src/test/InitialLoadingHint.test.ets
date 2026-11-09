import { describe, expect, it } from '@ohos/hypium';
import {
  INITIAL_HINT_DELAY_MS, initialHintLabelKey, showInitialLoadingHint
} from '../main/ets/util/initialLoadingHint';

// 会话首屏还一行都没有、正在加载时的提示（#219-10）。
export default function initialLoadingHintTest() {
  describe('InitialLoadingHint', () => {
    // 这一档原来谁都不画：状态卡要求 loadState !== 'loading'，顶部胶囊在
    // 0 行时直接返回 TL_NONE，两边都以为对方会说。
    it('0 行且正在首次加载时显示', 0, () => {
      expect(showInitialLoadingHint(false, 'loading')).assertTrue();
    });

    it('有行了、或已加载完/失败时不显示（后两种交给状态卡）', 0, () => {
      expect(showInitialLoadingHint(true, 'loading')).assertFalse();
      expect(showInitialLoadingHint(false, 'ready')).assertFalse();
      expect(showInitialLoadingHint(false, 'error')).assertFalse();
    });

    // 本地命中时几十毫秒就出内容，延时不够会闪一下。
    it('延时不短于 300ms', 0, () => {
      expect(INITIAL_HINT_DELAY_MS >= 300).assertTrue();
    });

    it('等网络 / 连接中给一行文字，与首页标题下同一套文案', 0, () => {
      expect(initialHintLabelKey('connectionStateWaitingForNetwork')).assertEqual('cl_waiting_network');
      expect(initialHintLabelKey('connectionStateConnecting')).assertEqual('cl_connecting');
      expect(initialHintLabelKey('connectionStateConnectingToProxy')).assertEqual('cl_connecting');
    });

    // 已连上（或还不知道）时只转圈，不写字——那时慢是 TDLib 在取，不是网络问题。
    it('已连上或未知时只转圈', 0, () => {
      expect(initialHintLabelKey('connectionStateReady')).assertEqual('');
      expect(initialHintLabelKey('connectionStateUpdating')).assertEqual('');
      expect(initialHintLabelKey('')).assertEqual('');
    });
  });
}
