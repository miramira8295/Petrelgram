import { describe, expect, it } from '@ohos/hypium';
import { THICKNESS_OFF } from '../main/ets/util/materialTuning';
import {
  KEY_SURFACE_GLASS_LEVEL, KEY_SURFACE_GLASS_ON, SURFACE_GLASS_LEVEL_DEFAULT, SURFACE_GLASS_LEVEL_VEIL,
  SURFACE_GLASS_ON_DEFAULT, surfaceGlassBlurStyle, surfaceGlassFillHex, surfaceGlassLevel, surfaceGlassOn, surfaceGlassScrim
} from '../main/ets/util/surfaceGlass';

export default function surfaceGlassTest() {
  describe('surfaceGlass', () => {
    it('默认关：这是性能与功耗的取舍，必须用户主动开', 0, () => {
      AppStorage.delete(KEY_SURFACE_GLASS_ON);
      expect(SURFACE_GLASS_ON_DEFAULT).assertFalse();
      expect(surfaceGlassOn()).assertFalse();
      // 关掉时不给材质，调用方不需要自己判断开关。
      expect(surfaceGlassBlurStyle() === undefined).assertTrue();
    });

    // 打开之后**默认就带薄纱**：薄纱是构成里的一个成分，不是另一个开关。
    it('打开之后默认带薄纱：合成罩偏亮而不是纯压暗', 0, () => {
      AppStorage.setOrCreate(KEY_SURFACE_GLASS_ON, true);
      const hex: string = surfaceGlassScrim() as string;
      const r: number = Number.parseInt(hex.substring(3, 5), 16);
      // 纯压暗的话 RGB 会是 0；带薄纱才会有可观的亮度。
      expect(r > 0x80).assertTrue();
    });

    // 五个档位必须映射到**五个不同**的材质档：曾经用 base+offset 算，
    // "超薄"和"薄"落到同一档、"超厚"到不了 ULTRA_THICK（用户实测"这超薄和
    // 超厚还有区别吗"）。
    it('五个档位互不相同，量程用满', 0, () => {
      AppStorage.setOrCreate(KEY_SURFACE_GLASS_ON, true);
      const seen: BlurStyle[] = [];
      for (const lv of [-2, -1, 0, 1, 2]) {
        AppStorage.setOrCreate(KEY_SURFACE_GLASS_LEVEL, lv);
        const st = surfaceGlassBlurStyle();
        expect(st !== undefined).assertTrue();
        expect(seen.indexOf(st as BlurStyle) < 0).assertTrue();
        seen.push(st as BlurStyle);
      }
      expect(seen.length).assertEqual(5);
    });

    it('开着时按档位给不同的材质档', 0, () => {
      AppStorage.setOrCreate(KEY_SURFACE_GLASS_ON, true);
      AppStorage.setOrCreate(KEY_SURFACE_GLASS_LEVEL, -2);
      const thin = surfaceGlassBlurStyle();
      AppStorage.setOrCreate(KEY_SURFACE_GLASS_LEVEL, 0);
      const regular = surfaceGlassBlurStyle();
      AppStorage.setOrCreate(KEY_SURFACE_GLASS_LEVEL, 2);
      const thick = surfaceGlassBlurStyle();
      expect(thin !== undefined).assertTrue();
      expect(thin === regular).assertFalse();
      expect(regular === thick).assertFalse();
    });

    // **别再改回和 SURFACE_GLASS_LEVEL_DEFAULT 比。** 加了「薄纱」档之后这是
    // 两件不同的事：DEFAULT 是"没存过值时用哪一档"（现在是薄纱 -3），而越界
    // 归一化交给 normalizeThickness，它把野值收回**厚度量程的中点 0**（常规）。
    // 原来两者恰好都是 0，才看起来像同一件事。
    it('档位越界一律收回常规档，不把野值交给渲染', 0, () => {
      AppStorage.setOrCreate(KEY_SURFACE_GLASS_LEVEL, 99);
      expect(surfaceGlassLevel()).assertEqual(0);
      AppStorage.setOrCreate(KEY_SURFACE_GLASS_LEVEL, -99);
      expect(surfaceGlassLevel()).assertEqual(0);
    });

    // 薄纱档必须原样透出：它落在 normalizeThickness 的量程之外，被归一化
    // 就会悄悄变成"超薄"，纱色照旧但模糊又挂回来了。
    it('薄纱档原样透出，且一次模糊都不挂', 0, () => {
      AppStorage.setOrCreate(KEY_SURFACE_GLASS_ON, true);
      AppStorage.setOrCreate(KEY_SURFACE_GLASS_LEVEL, SURFACE_GLASS_LEVEL_VEIL);
      expect(surfaceGlassLevel()).assertEqual(SURFACE_GLASS_LEVEL_VEIL);
      expect(surfaceGlassBlurStyle() === undefined).assertTrue();
    });

    // 薄纱的哨兵值**必须和「关闭」档不同**。第一版两者都是 -3，于是设置里
    // 两个选项的 value 相同，点薄纱被判成点关闭（用户实测）。
    it('薄纱档的哨兵值不能和「关闭」档撞车', 0, () => {
      expect(SURFACE_GLASS_LEVEL_VEIL === THICKNESS_OFF).assertFalse();
    });

    it('没存过值时默认就是薄纱档', 0, () => {
      expect(SURFACE_GLASS_LEVEL_DEFAULT).assertEqual(SURFACE_GLASS_LEVEL_VEIL);
    });

    it('总开关压过档位：关掉时任何档位都不给材质', 0, () => {
      AppStorage.setOrCreate(KEY_SURFACE_GLASS_ON, false);
      AppStorage.setOrCreate(KEY_SURFACE_GLASS_LEVEL, 2);
      expect(surfaceGlassBlurStyle() === undefined).assertTrue();
    });

    // 档位不只改模糊半径，底色的不透明度也跟着走——决定"卡片和壁纸之间那条缝
    // 扎不扎眼"的是亮度差，不是模糊有多糊。
    it('底色不透明度跟着档位：越厚越实', 0, () => {
      AppStorage.setOrCreate(KEY_SURFACE_GLASS_ON, true);
      AppStorage.setOrCreate(KEY_SURFACE_GLASS_LEVEL, -2);
      const thin: string = surfaceGlassFillHex();
      AppStorage.setOrCreate(KEY_SURFACE_GLASS_LEVEL, 0);
      const regular: string = surfaceGlassFillHex();
      AppStorage.setOrCreate(KEY_SURFACE_GLASS_LEVEL, 2);
      const thick: string = surfaceGlassFillHex();
      const a = (hex: string): number => Number.parseInt(hex.substring(1, 3), 16);
      expect(a(thin) < a(regular)).assertTrue();
      expect(a(regular) < a(thick)).assertTrue();
    });

    // 默认档必须和改动前逐字节等价（原来恒定是 dock_glass = #8CFFFFFF）。
    it('默认档的 alpha 就是原来的 0x8C', 0, () => {
      AppStorage.setOrCreate(KEY_SURFACE_GLASS_ON, true);
      AppStorage.setOrCreate(KEY_SURFACE_GLASS_LEVEL, 0);
      expect(surfaceGlassFillHex().substring(1, 3)).assertEqual('8C');
    });

    // 罩子必须**极淡**：backgroundColor 画在材质之上，给重了就把材质盖住，
    // 卡片会变成不透明的一块。这条钉住上限，防止以后有人"再压黑一点"压过头。
    // 薄纱 + 压暗合成之后仍然要"极淡"：backgroundColor 画在材质之上，
    // 给重了就把材质盖住，卡片会变成不透明的一块。
    it('合成罩的不透明度必须低于 25%，否则材质会被盖住', 0, () => {
      const hex: string = surfaceGlassScrim() as string;
      const alpha: number = Number.parseInt(hex.substring(1, 3), 16);
      expect(alpha > 0).assertTrue();
      expect(alpha < 0x40).assertTrue();
    });
  });
}
