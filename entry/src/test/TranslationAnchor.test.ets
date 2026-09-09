import { describe, it, expect } from '@ohos/hypium';
import {
  clearTranslationInstant, markTranslationInstant, shouldHoldTranslationAnchor,
  takeTranslationInstant
} from '../main/ets/util/translationAnchor';

// 译文让气泡变高时怎么保住阅读位置。
//
// 第一版按"贴不贴底"决定动不动画，结果**只有第一屏有淡入淡出、往上翻就没了**
// （用户 2026-09-09 实测）——判据太粗。真正会把阅读位置顶下去的只有视口
// **上方**的行，所以改成按行点名。

export default function translationAnchorTest() {
  describe('translationAnchor', () => {

    it('没被点名的一律动画', 0, (): void => {
      clearTranslationInstant();
      expect(takeTranslationInstant(1)).assertFalse();
    });

    it('点名过的直接落', 0, (): void => {
      clearTranslationInstant();
      markTranslationInstant(7);
      expect(takeTranslationInstant(7)).assertTrue();
    });

    it('查一次就清——标记只对这一次落地有效', 0, (): void => {
      clearTranslationInstant();
      markTranslationInstant(7);
      takeTranslationInstant(7);
      // 同一条消息下次换语言时该正常动画
      expect(takeTranslationInstant(7)).assertFalse();
    });

    it('点名互不串台', 0, (): void => {
      clearTranslationInstant();
      markTranslationInstant(1);
      expect(takeTranslationInstant(2)).assertFalse();
      expect(takeTranslationInstant(1)).assertTrue();
    });

    it('换会话时整批清掉', 0, (): void => {
      markTranslationInstant(1);
      clearTranslationInstant();
      expect(takeTranslationInstant(1)).assertFalse();
    });

    it('贴底时不保锚点，交给列表自己', 0, (): void => {
      expect(shouldHoldTranslationAnchor(true, true)).assertFalse();
    });

    it('顶部锚定且行号新鲜时才保锚点', 0, (): void => {
      expect(shouldHoldTranslationAnchor(false, true)).assertTrue();
    });

    it('行号不新鲜时不保——拿旧行号去量会量错行', 0, (): void => {
      expect(shouldHoldTranslationAnchor(false, false)).assertFalse();
    });
  });
}
