import { describe, expect, it } from '@ohos/hypium';
import {
  TRANSLATE_DONE, TRANSLATE_EMPTY, TRANSLATE_FAILED,
  TranslateToggle, sheetStateOf, toggleTranslation, translationActive
} from '../main/ets/util/translationMode';

// 两个真相来源、极性相反，全靠总开关选路。
export default function translationModeTest() {
  describe('translationMode', () => {
    it('总开关关着时只认本地加入名单', 0, () => {
      expect(translationActive(false, false, false, true)).assertTrue();
      expect(translationActive(false, false, false, false)).assertFalse();
      // 总开关关着时排除名单不该有任何影响。
      expect(translationActive(false, true, false, true)).assertTrue();
      expect(translationActive(false, true, false, false)).assertFalse();
    });

    // 回归：服务端位曾经和本地名单取或，于是"全局关闭"关不干净——用户在
    // 官方端开过翻译的会话照样翻，只能一个个进去关。
    it('总开关关着时服务端 is_translatable 单独点不亮会话', 0, () => {
      expect(translationActive(false, false, true, false)).assertFalse();
      expect(translationActive(false, true, true, false)).assertFalse();
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
      const on: TranslateToggle = toggleTranslation(false, false, false, false);
      expect(on.active).assertTrue();
      expect(on.writesOptOut).assertFalse();
      expect(on.translatable).assertTrue();
      const off: TranslateToggle = toggleTranslation(false, false, true, true);
      expect(off.active).assertFalse();
      expect(off.translatable).assertFalse();
    });

    it('切换永远是当前态取反，两种模式下都成立', 0, () => {
      const flags: boolean[] = [false, true];
      for (const g of flags) {
        for (const o of flags) {
          for (const t of flags) {
            for (const i of flags) {
              expect(toggleTranslation(g, o, t, i).active)
                .assertEqual(!translationActive(g, o, t, i));
            }
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
