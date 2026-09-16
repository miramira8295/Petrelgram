import { describe, it, expect } from '@ohos/hypium';
import { bumpMaterialEpoch, MATERIAL_EPOCH } from '../main/ets/util/materialEpoch';
import { MATERIAL_EPOCH as REEXPORTED_EPOCH } from '../main/ets/util/overlayMaterial';

// 材质纪元：bump 一次加一；overlayMaterial 再导出的是同一个键（老的引用点靠它）。2026-09-15。

export default function materialEpochTest() {
  describe('materialEpoch', () => {
    it('bump 递增纪元；overlayMaterial 再导出的是同一个键', 0, () => {
      const before: number = AppStorage.get<number>(MATERIAL_EPOCH) ?? 0;
      bumpMaterialEpoch();
      expect(AppStorage.get<number>(MATERIAL_EPOCH) ?? 0).assertEqual(before + 1);
      expect(REEXPORTED_EPOCH).assertEqual(MATERIAL_EPOCH);
    });
  });
}
