import { describe, it, expect } from '@ohos/hypium';
import {
  pinForTranslationGrowth, registerTranslationGrowthPin, TranslationGrowthPinInput,
  translationGrowthPinWanted
} from '../main/ets/util/translationGrowthPin';

// 停在最底下时，译文 / 「翻译中」让气泡变高要钉住底部——气泡向上长
// （用户 2026-09-14）。判据与页面「原地变高时贴住底」同一组条件。

function idleAtBottom(): TranslationGrowthPinInput {
  return {
    pageVisible: true,
    didInitialScroll: true,
    atBottom: true,
    followPending: false,
    stayAtUnread: false,
    touchActive: false,
    scrollActive: false,
    viewerOpen: false,
    hasMoreNewer: false,
    jumpLanding: false
  };
}

export default function translationGrowthPinTest() {
  describe('translationGrowthPin', () => {

    it('停在底、没人碰：钉', 0, (): void => {
      expect(translationGrowthPinWanted(idleAtBottom())).assertTrue();
    });

    it('贴底跟随在途也算在底', 0, (): void => {
      const input: TranslationGrowthPinInput = idleAtBottom();
      input.atBottom = false;
      input.followPending = true;
      expect(translationGrowthPinWanted(input)).assertTrue();
    });

    it('不在底：不钉——往上翻着时行往下长是对的', 0, (): void => {
      const input: TranslationGrowthPinInput = idleAtBottom();
      input.atBottom = false;
      expect(translationGrowthPinWanted(input)).assertFalse();
    });

    // 跳转刚落地的那几百毫秒里位置归跳转所有：这时钉底就是把用户从目标拽走。
    it('跳转刚落地：不钉', 0, (): void => {
      const input: TranslationGrowthPinInput = idleAtBottom();
      input.jumpLanding = true;
      expect(translationGrowthPinWanted(input)).assertFalse();
    });

    it('手指按着或列表在滚：不钉', 0, (): void => {
      const touching: TranslationGrowthPinInput = idleAtBottom();
      touching.touchActive = true;
      expect(translationGrowthPinWanted(touching)).assertFalse();
      const scrolling: TranslationGrowthPinInput = idleAtBottom();
      scrolling.scrollActive = true;
      expect(translationGrowthPinWanted(scrolling)).assertFalse();
    });

    it('查看器开着：不动底下的列表', 0, (): void => {
      const input: TranslationGrowthPinInput = idleAtBottom();
      input.viewerOpen = true;
      expect(translationGrowthPinWanted(input)).assertFalse();
    });

    it('窗口还没到实时尾部：不钉', 0, (): void => {
      const input: TranslationGrowthPinInput = idleAtBottom();
      input.hasMoreNewer = true;
      expect(translationGrowthPinWanted(input)).assertFalse();
    });

    it('落在未读被锁住、首屏还没落定、页面不可见：都不钉', 0, (): void => {
      const unread: TranslationGrowthPinInput = idleAtBottom();
      unread.stayAtUnread = true;
      expect(translationGrowthPinWanted(unread)).assertFalse();
      const landing: TranslationGrowthPinInput = idleAtBottom();
      landing.didInitialScroll = false;
      expect(translationGrowthPinWanted(landing)).assertFalse();
      const hidden: TranslationGrowthPinInput = idleAtBottom();
      hidden.pageVisible = false;
      expect(translationGrowthPinWanted(hidden)).assertFalse();
    });

    it('分发给每个挂着的页，chatId 原样带过去', 0, (): void => {
      const got: number[] = [];
      const offA: () => void = registerTranslationGrowthPin((chatId: number): void => { got.push(chatId); });
      const offB: () => void = registerTranslationGrowthPin((chatId: number): void => { got.push(-chatId); });
      pinForTranslationGrowth(42);
      offA();
      offB();
      expect(got.length).assertEqual(2);
      expect(got[0]).assertEqual(42);
      expect(got[1]).assertEqual(-42);
    });

    it('摘掉之后不再收到，其余的照收', 0, (): void => {
      const got: number[] = [];
      const offA: () => void = registerTranslationGrowthPin((chatId: number): void => { got.push(chatId); });
      const offB: () => void = registerTranslationGrowthPin((chatId: number): void => { got.push(-chatId); });
      offA();
      pinForTranslationGrowth(7);
      offB();
      pinForTranslationGrowth(8);
      expect(got.length).assertEqual(1);
      expect(got[0]).assertEqual(-7);
    });
  });
}
