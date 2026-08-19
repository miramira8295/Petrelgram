import { describe, expect, it } from '@ohos/hypium';
import {
  TRANSLATE_DONE, TRANSLATE_EMPTY, TRANSLATE_FAILED,
  TranslateToggle, sheetStateOf, toggleTranslation, translationActive
} from '../main/ets/util/translationMode';

// 两个真相来源、极性相反，全靠总开关选路。
export default function translationModeTest() {
  describe('translationMode', () => {
    it('总开关关着时看会话自己的 is_translatable', 0, () => {
      expect(translationActive(false, false, true)).assertTrue();
      expect(translationActive(false, false, false)).assertFalse();
      // 总开关关着时排除名单不该有任何影响。
      expect(translationActive(false, true, true)).assertTrue();
      expect(translationActive(false, true, false)).assertFalse();
    });

    it('总开关开着时看排除名单，且极性是反的', 0, () => {
      expect(translationActive(true, false, false)).assertTrue();
      expect(translationActive(true, true, true)).assertFalse();
    });

    it('切换：总开关模式写排除名单', 0, () => {
      // 当前在翻（没被排除）→ 关掉 → 要写进排除名单。
      const off: TranslateToggle = toggleTranslation(true, false, false);
      expect(off.active).assertFalse();
      expect(off.writesOptOut).assertTrue();
      expect(off.optOut).assertTrue();
      // 当前被排除 → 打开 → 移出排除名单。
      const on: TranslateToggle = toggleTranslation(true, true, false);
      expect(on.active).assertTrue();
      expect(on.writesOptOut).assertTrue();
      expect(on.optOut).assertFalse();
    });

    it('切换：非总开关模式写 is_translatable', 0, () => {
      const on: TranslateToggle = toggleTranslation(false, false, false);
      expect(on.active).assertTrue();
      expect(on.writesOptOut).assertFalse();
      expect(on.translatable).assertTrue();
      const off: TranslateToggle = toggleTranslation(false, false, true);
      expect(off.active).assertFalse();
      expect(off.translatable).assertFalse();
    });

    it('切换永远是当前态取反，两种模式下都成立', 0, () => {
      const flags: boolean[] = [false, true];
      for (const g of flags) {
        for (const o of flags) {
          for (const t of flags) {
            expect(toggleTranslation(g, o, t).active)
              .assertEqual(!translationActive(g, o, t));
          }
        }
      }
    });

    it('null 是失败，空串和原文原样返回都是"没东西可看"', 0, () => {
      expect(sheetStateOf(null, '原文')).assertEqual(TRANSLATE_FAILED);
      expect(sheetStateOf('', '原文')).assertEqual(TRANSLATE_EMPTY);
      expect(sheetStateOf('原文', '原文')).assertEqual(TRANSLATE_EMPTY);
      expect(sheetStateOf('translated', '原文')).assertEqual(TRANSLATE_DONE);
    });

    it('原文为空时，任何非空译文仍算成功', 0, () => {
      expect(sheetStateOf('something', '')).assertEqual(TRANSLATE_DONE);
      expect(sheetStateOf('', '')).assertEqual(TRANSLATE_EMPTY);
    });
  });
}
