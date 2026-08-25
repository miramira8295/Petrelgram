import { describe, expect, it } from '@ohos/hypium';
import {
  FALLBACK_BLUR_BASE, LIGHT_ADAPTIVE, LIGHT_EXQUISITE, LIGHT_GENTLE, LIGHT_SMOOTH,
  THICKNESS_DEFAULT, THICKNESS_OFF, THICKNESS_REGULAR, THICKNESS_ULTRA_THICK, THICKNESS_ULTRA_THIN,
  fallbackBlurRadius, interactiveOn, isThicknessOff, lightEffectOn, normalizeLightLevel,
  normalizeThickness, shiftedStyleIndex
} from '../main/ets/util/materialTuning';

// 各个面调好的基准档位，和 overlayMaterial 的 styleOf 对齐。
const BAR: number = 0;      // ULTRA_THIN
const CARD: number = 1;     // THIN
const MENU: number = 2;     // REGULAR
const DIALOG: number = 4;   // ULTRA_THICK

export default function materialTuningTest() {
  describe('materialTuning', () => {
    it('默认偏移不改变任何一个面', 0, () => {
      expect(shiftedStyleIndex(BAR, THICKNESS_DEFAULT)).assertEqual(BAR);
      expect(shiftedStyleIndex(CARD, THICKNESS_DEFAULT)).assertEqual(CARD);
      expect(shiftedStyleIndex(MENU, THICKNESS_DEFAULT)).assertEqual(MENU);
      expect(shiftedStyleIndex(DIALOG, THICKNESS_DEFAULT)).assertEqual(DIALOG);
    });

    it('偏移整体平移，保住相对次序', 0, () => {
      // 这条是这个设计的全部理由：调厚之后，顶栏仍然比菜单薄。
      const bar: number = shiftedStyleIndex(BAR, 1);
      const menu: number = shiftedStyleIndex(MENU, 1);
      expect(bar < menu).assertTrue();
      expect(bar).assertEqual(1);
      expect(menu).assertEqual(3);
    });

    it('钳到枚举两端，不会越界', 0, () => {
      expect(shiftedStyleIndex(BAR, THICKNESS_ULTRA_THIN)).assertEqual(0);
      expect(shiftedStyleIndex(DIALOG, THICKNESS_ULTRA_THICK)).assertEqual(4);
    });

    it('弹窗调到最薄也还在最厚档之内', 0, () => {
      // 弹窗是要盖住背后内容的，超薄弹窗等于坏了——基准 4 减 2 仍是 2。
      expect(shiftedStyleIndex(DIALOG, THICKNESS_ULTRA_THIN)).assertEqual(2);
    });

    it('越界偏移当作没设置', 0, () => {
      expect(normalizeThickness(7)).assertEqual(THICKNESS_DEFAULT);
      expect(normalizeThickness(-9)).assertEqual(THICKNESS_DEFAULT);
      expect(normalizeThickness(1.4)).assertEqual(1);
    });

    it('降级路径的模糊半径跟着厚度走', 0, () => {
      expect(fallbackBlurRadius(THICKNESS_DEFAULT)).assertEqual(FALLBACK_BLUR_BASE);
      expect(fallbackBlurRadius(THICKNESS_ULTRA_THIN)).assertEqual(10);
      expect(fallbackBlurRadius(THICKNESS_ULTRA_THICK)).assertEqual(34);
      // 老设备上这个设置必须有效果，不能恒为基准值。
      expect(fallbackBlurRadius(-1) !== FALLBACK_BLUR_BASE).assertTrue();
    });

    it('未知光感档位退回自适应', 0, () => {
      expect(normalizeLightLevel('nonsense')).assertEqual(LIGHT_ADAPTIVE);
      expect(normalizeLightLevel('')).assertEqual(LIGHT_ADAPTIVE);
      expect(normalizeLightLevel(LIGHT_SMOOTH)).assertEqual(LIGHT_SMOOTH);
    });

    it('精致把流光给到本来没有的面', 0, () => {
      expect(lightEffectOn(LIGHT_EXQUISITE, false, false)).assertTrue();
    });

    it('平滑一律不给', 0, () => {
      expect(lightEffectOn(LIGHT_SMOOTH, true, false)).assertFalse();
      expect(interactiveOn(LIGHT_SMOOTH, true, false)).assertFalse();
    });

    it('柔和给流光但不给形变', 0, () => {
      expect(lightEffectOn(LIGHT_GENTLE, true, false)).assertTrue();
      expect(interactiveOn(LIGHT_GENTLE, true, false)).assertFalse();
    });

    it('自适应尊重每个面自己的分档', 0, () => {
      expect(lightEffectOn(LIGHT_ADAPTIVE, true, false)).assertTrue();
      expect(lightEffectOn(LIGHT_ADAPTIVE, false, false)).assertFalse();
      expect(interactiveOn(LIGHT_ADAPTIVE, true, false)).assertTrue();
    });

    it('省电只压自适应，不改用户明确挑的档', 0, () => {
      expect(lightEffectOn(LIGHT_ADAPTIVE, true, true)).assertFalse();
      expect(interactiveOn(LIGHT_ADAPTIVE, true, true)).assertFalse();
      // 明确挑了精致就按精致来，省电不替他改主意。
      expect(lightEffectOn(LIGHT_EXQUISITE, true, true)).assertTrue();
      expect(interactiveOn(LIGHT_EXQUISITE, true, true)).assertTrue();
    });

    it('四档单调包含：平滑 ⊂ 柔和 ⊂ 自适应 ⊂ 精致', 0, () => {
      // 档位调高绝不该让任何一个面失去效果——这类"调高反而变少"的错位
      // 单看某一档看不出来，必须穷举比较。
      const levels: string[] = [LIGHT_SMOOTH, LIGHT_GENTLE, LIGHT_ADAPTIVE, LIGHT_EXQUISITE];
      const defaults: boolean[] = [false, true];
      for (const d of defaults) {
        for (let i = 1; i < levels.length; i++) {
          const lower: boolean = lightEffectOn(levels[i - 1], d, false);
          const higher: boolean = lightEffectOn(levels[i], d, false);
          expect(!lower || higher).assertTrue();
          const lowerI: boolean = interactiveOn(levels[i - 1], d, false);
          const higherI: boolean = interactiveOn(levels[i], d, false);
          expect(!lowerI || higherI).assertTrue();
        }
      }
    });
    it('厚度关闭档 -3 合法且可判，-4 仍回默认', 0, (): void => {
      expect(normalizeThickness(THICKNESS_OFF)).assertEqual(THICKNESS_OFF);
      expect(isThicknessOff(THICKNESS_OFF)).assertTrue();
      expect(isThicknessOff(THICKNESS_REGULAR)).assertFalse();
      expect(normalizeThickness(-4)).assertEqual(THICKNESS_DEFAULT);
    });
  });
}
