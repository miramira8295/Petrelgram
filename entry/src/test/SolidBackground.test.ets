import { describe, expect, it } from '@ohos/hypium';
import { emptyChatBackground, ChatBackgroundState } from '../main/ets/store/ChatBackgroundStore';
import {
  SOLID_DARK_COLORS, SOLID_LIGHT_COLORS, hexColorToInt, isSolidBackgroundOf, isSystemBackground,
  solidBackgroundState, solidPaletteFor, systemChatColor
} from '../main/ets/util/solidBackground';

// 纯色背景（2026-09-27）：色板、颜色换算，以及设置页「当前选中哪一格」的判据。
export default function solidBackgroundTest() {
  describe('SolidBackground', () => {
    it('色板按深浅色各一套，且都是合法的 #RRGGBB', 0, () => {
      expect(solidPaletteFor(false)).assertEqual(SOLID_LIGHT_COLORS);
      expect(solidPaletteFor(true)).assertEqual(SOLID_DARK_COLORS);
      for (const c of SOLID_LIGHT_COLORS.concat(SOLID_DARK_COLORS)) {
        expect(hexColorToInt(c) >= 0).assertTrue();
      }
    });

    it('#RRGGBB 换成 TDLib 的 24 位整数，格式不对给 -1', 0, () => {
      expect(hexColorToInt('#000000')).assertEqual(0);
      expect(hexColorToInt('#FFFFFF')).assertEqual(0xFFFFFF);
      expect(hexColorToInt('#1c1c1e')).assertEqual(0x1C1C1E);
      expect(hexColorToInt('1C1C1E')).assertEqual(-1);
      expect(hexColorToInt('#FFF')).assertEqual(-1);
      expect(hexColorToInt('')).assertEqual(-1);
    });

    it('纯色状态是一个大写颜色、无文件、非图案', 0, () => {
      const s: ChatBackgroundState = solidBackgroundState('#e4eef8');
      expect(s.custom).assertTrue();
      expect(s.colors.length).assertEqual(1);
      expect(s.colors[0]).assertEqual('#E4EEF8');
      expect(s.path).assertEqual('');
      expect(s.isPattern).assertFalse();
    });

    it('空状态就是跟随系统', 0, () => {
      expect(isSystemBackground(emptyChatBackground())).assertTrue();
      expect(isSystemBackground(solidBackgroundState('#FFFFFF'))).assertFalse();
    });

    it('选中判据：同色纯色才算，图案与整图不算', 0, () => {
      const solid: ChatBackgroundState = solidBackgroundState('#0F1C2B');
      expect(isSolidBackgroundOf(solid, '#0f1c2b')).assertTrue();
      expect(isSolidBackgroundOf(solid, '#000000')).assertFalse();
      const pattern: ChatBackgroundState = solidBackgroundState('#0F1C2B');
      pattern.isPattern = true;
      pattern.path = '/tmp/p.svg';
      expect(isSolidBackgroundOf(pattern, '#0F1C2B')).assertFalse();
      const gradient: ChatBackgroundState = emptyChatBackground();
      gradient.colors = ['#0F1C2B', '#000000'];
      expect(isSolidBackgroundOf(gradient, '#0F1C2B')).assertFalse();
    });

    it('跟随系统的色块取 chat_bg 的浅 / 深两值', 0, () => {
      expect(systemChatColor(false)).assertEqual('#EFEFF4');
      expect(systemChatColor(true)).assertEqual('#0E1621');
    });
  });
}
