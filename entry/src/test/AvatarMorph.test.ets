import { describe, expect, it } from '@ohos/hypium';
import {
  AVATAR_BASE, AVATAR_CARD_RADIUS, AVATAR_EXPANDED_H, AVATAR_PROFILE_BASE, AVATAR_PROFILE_RING,
  AVATAR_RATIO_SPAN, AVATAR_RING,
  avatarDecodeHeightOf, avatarDecodeWidthOf, avatarHeightOf, avatarOffsetYOf,
  avatarRadiusOf, avatarRatioOf, avatarRingOf, avatarUsesCardLayout, avatarWidthOf, canExpandAvatar
} from '../main/ets/util/avatarMorph';
import {
  HEIGHT_BP_LG, HEIGHT_BP_MD, HEIGHT_BP_SM, WIDTH_BP_LG, WIDTH_BP_MD, WIDTH_BP_SM
} from '../main/ets/util/layoutBreakpoint';

export default function avatarMorphTest() {
  describe('avatarMorph', () => {
    it('无静态图也无动态头像时禁止下拉放大', 0, () => {
      expect(canExpandAvatar('', '')).assertFalse();
      expect(canExpandAvatar('/data/avatar.jpg', '')).assertTrue();
      expect(canExpandAvatar('', '/data/avatar.mp4')).assertTrue();
    });

    it('卡片内缩判据排除手机横屏与强制单栏', 0, () => {
      expect(avatarUsesCardLayout(WIDTH_BP_SM, HEIGHT_BP_LG, false)).assertFalse();
      // 直板机横屏 md/sm（#125）仍按手机满铺处理
      expect(avatarUsesCardLayout(WIDTH_BP_MD, HEIGHT_BP_SM, false)).assertFalse();
      // 开启强制单栏时即使在大屏也按手机满铺处理
      expect(avatarUsesCardLayout(WIDTH_BP_LG, HEIGHT_BP_SM, true)).assertFalse();
      // 折叠屏展开 md/md、平板竖屏 md/lg、平板横屏 lg/sm 均走内缩圆角卡片
      expect(avatarUsesCardLayout(WIDTH_BP_MD, HEIGHT_BP_MD, false)).assertTrue();
      expect(avatarUsesCardLayout(WIDTH_BP_MD, HEIGHT_BP_LG, false)).assertTrue();
      expect(avatarUsesCardLayout(WIDTH_BP_LG, HEIGHT_BP_SM, false)).assertTrue();
    });

    it('我的资料与联系人/群资料各自保持静止态基线尺寸（108vp 与 130vp）', 0, () => {
      expect(avatarWidthOf(0, false, 390, AVATAR_BASE) + avatarRingOf(0, false, AVATAR_RING) * 2).assertEqual(108);
      expect(avatarWidthOf(0, false, 390, AVATAR_PROFILE_BASE) +
        avatarRingOf(0, false, AVATAR_PROFILE_RING) * 2).assertEqual(130);
      expect(avatarRadiusOf(0, false, 0, AVATAR_PROFILE_BASE)).assertEqual(58);
    });

    it('分轴形变：宽度先于高度顶满目标宽，满行程平滑衔接展开态无跳变', 0, () => {
      const midW = avatarWidthOf(90, false, 390, AVATAR_BASE);
      const midH = avatarHeightOf(90, false, AVATAR_BASE);
      expect(midW).assertEqual(390);
      expect(midH < AVATAR_EXPANDED_H).assertTrue();
      expect(avatarHeightOf(AVATAR_RATIO_SPAN, false, AVATAR_BASE)).assertEqual(AVATAR_EXPANDED_H);
      expect(avatarHeightOf(AVATAR_RATIO_SPAN, false, AVATAR_PROFILE_BASE)).assertEqual(AVATAR_EXPANDED_H);
    });

    it('手机展开圆角归零，平板展开收敛到 16vp 卡片圆角且圆环清零', 0, () => {
      expect(avatarRadiusOf(AVATAR_RATIO_SPAN, false, 0, AVATAR_BASE)).assertEqual(0);
      expect(avatarRadiusOf(0, true, AVATAR_CARD_RADIUS, AVATAR_PROFILE_BASE)).assertEqual(AVATAR_CARD_RADIUS);
      expect(avatarRingOf(AVATAR_RATIO_SPAN, false, AVATAR_PROFILE_RING)).assertEqual(0);
      expect(avatarRingOf(20, true, AVATAR_PROFILE_RING)).assertEqual(0);
    });

    it('越界上移在满行程后持续抵消 pull，把照片顶边钉死在目标顶边', 0, () => {
      const topInset = 80;
      // 满行程后照片屏幕顶坐标 = topInset + pull + offsetY === 0
      expect(topInset + 115 + avatarOffsetYOf(115, false, topInset)).assertEqual(0);
      expect(topInset + 180 + avatarOffsetYOf(180, true, topInset)).assertEqual(0);
    });

    it('解码尺寸仅在静止收起与下拉/展开两档切换，拖动途中保持恒定', 0, () => {
      expect(avatarDecodeWidthOf(0, false, 840, AVATAR_PROFILE_BASE)).assertEqual(AVATAR_PROFILE_BASE);
      expect(avatarDecodeHeightOf(0, false, AVATAR_PROFILE_BASE)).assertEqual(AVATAR_PROFILE_BASE);
      const pullingW = avatarDecodeWidthOf(5, false, 840, AVATAR_PROFILE_BASE);
      const pullingH = avatarDecodeHeightOf(5, false, AVATAR_PROFILE_BASE);
      expect(pullingW).assertEqual(840);
      expect(pullingH).assertEqual(AVATAR_EXPANDED_H);
      expect(avatarDecodeWidthOf(95, false, 840, AVATAR_PROFILE_BASE)).assertEqual(pullingW);
      expect(avatarDecodeWidthOf(0, true, 840, AVATAR_PROFILE_BASE)).assertEqual(pullingW);
      expect(avatarDecodeHeightOf(0, true, AVATAR_PROFILE_BASE)).assertEqual(pullingH);
    });

    it('负越界输入安全钳制不越界', 0, () => {
      expect(avatarRatioOf(-10, false)).assertEqual(0);
      expect(avatarOffsetYOf(-10, false, 50)).assertEqual(0);
    });
  });
}
