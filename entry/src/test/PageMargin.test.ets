import { describe, expect, it } from '@ohos/hypium';
import {
  HOME_CARD_MARGIN_PHONE_VP, PAGE_MARGIN_PHONE_VP, homeCardMarginVp, pageMarginVp
} from '../main/ets/util/pageMargin';
import {
  WIDTH_BP_LG, WIDTH_BP_MD, WIDTH_BP_SM, WIDTH_BP_XL, WIDTH_BP_XS
} from '../main/ets/util/layoutBreakpoint';

// 页面边距统一（SPEC-07）：手机 12，首页卡片保留 6；折叠屏 +4、平板 +8。
export default function pageMarginTest() {
  describe('PageMargin', () => {
    it('手机：页面 12，首页卡片 6', 0, () => {
      expect(PAGE_MARGIN_PHONE_VP).assertEqual(12);
      expect(HOME_CARD_MARGIN_PHONE_VP).assertEqual(6);
      expect(pageMarginVp(WIDTH_BP_SM)).assertEqual(12);
      expect(pageMarginVp(WIDTH_BP_XS)).assertEqual(12);
      expect(homeCardMarginVp(WIDTH_BP_SM)).assertEqual(6);
    });

    it('折叠屏 +4，平板及以上 +8', 0, () => {
      expect(pageMarginVp(WIDTH_BP_MD)).assertEqual(16);
      expect(pageMarginVp(WIDTH_BP_LG)).assertEqual(20);
      expect(pageMarginVp(WIDTH_BP_XL)).assertEqual(20);
      expect(homeCardMarginVp(WIDTH_BP_MD)).assertEqual(10);
      expect(homeCardMarginVp(WIDTH_BP_LG)).assertEqual(14);
    });

    // P0：左边距不超过屏宽 20%。各档取该档最窄的窗口宽来算，最坏情况也远在线下。
    it('各档都在屏宽 20% 以内', 0, () => {
      expect(pageMarginVp(WIDTH_BP_SM) <= 320 * 0.2).assertTrue();
      expect(pageMarginVp(WIDTH_BP_MD) <= 600 * 0.2).assertTrue();
      expect(pageMarginVp(WIDTH_BP_LG) <= 840 * 0.2).assertTrue();
    });
  });
}
