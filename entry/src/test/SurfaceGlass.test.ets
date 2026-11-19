import { describe, expect, it } from '@ohos/hypium';
import { KEY_APP_DARK } from '../main/ets/util/theme';
import {
  KEY_SURFACE_GLASS_LEVEL, KEY_SURFACE_GLASS_ON, KEY_BUBBLE_GLASS_LEVEL, KEY_BUBBLE_GLASS_ON,
  SURFACE_GLASS_LEVEL_DEFAULT, SURFACE_GLASS_LEVEL_VEIL, SURFACE_GLASS_ON_DEFAULT,
  BUBBLE_GLASS_ON_DEFAULT, SURFACE_GLASS_EPOCH, bumpSurfaceGlassEpoch,
  surfaceGlassFill, surfaceGlassFillHex, surfaceGlassLevel, surfaceGlassOn,
  bubbleGlassFill, bubbleGlassLevel, bubbleGlassOn, bubbleTintFillHex
} from '../main/ets/util/surfaceGlass';

function withSurfaceSettings(work: () => void): void {
  const keys: string[] = [KEY_SURFACE_GLASS_LEVEL, KEY_SURFACE_GLASS_ON,
    KEY_BUBBLE_GLASS_LEVEL, KEY_BUBBLE_GLASS_ON, KEY_APP_DARK, SURFACE_GLASS_EPOCH];
  const values: (number | boolean | undefined)[] = keys.map((key: string): number | boolean | undefined =>
    AppStorage.get<number | boolean>(key));
  try { work(); } finally {
    for (let i = 0; i < keys.length; i++) {
      const value = values[i];
      if (value === undefined) { AppStorage.delete(keys[i]); } else { AppStorage.setOrCreate(keys[i], value); }
    }
  }
}

export default function surfaceGlassTest() {
  describe('surfaceGlass', () => {
    it('both_tint_switches_default_off_and_preserve_solid_fill', 0, () => withSurfaceSettings((): void => {
      AppStorage.delete(KEY_SURFACE_GLASS_ON); AppStorage.delete(KEY_BUBBLE_GLASS_ON);
      expect(SURFACE_GLASS_ON_DEFAULT).assertFalse(); expect(BUBBLE_GLASS_ON_DEFAULT).assertFalse();
      expect(surfaceGlassOn()).assertFalse(); expect(bubbleGlassOn()).assertFalse();
      expect(surfaceGlassFill('#112233')).assertEqual('#112233');
      expect(bubbleGlassFill('#445566')).assertEqual('#445566');
    }));
    it('light_surface_and_bubble_use_identical_rgba_at_every_level', 0, () => withSurfaceSettings((): void => {
      AppStorage.setOrCreate(KEY_APP_DARK, false);
      AppStorage.setOrCreate(KEY_SURFACE_GLASS_ON, true); AppStorage.setOrCreate(KEY_BUBBLE_GLASS_ON, true);
      for (const level of [-2, -1, 0, 1, 2]) {
        AppStorage.setOrCreate(KEY_SURFACE_GLASS_LEVEL, level); AppStorage.setOrCreate(KEY_BUBBLE_GLASS_LEVEL, level);
        expect(surfaceGlassFillHex()).assertEqual(bubbleTintFillHex(false, level));
        expect(surfaceGlassFill('#000000')).assertEqual(bubbleGlassFill('#000000'));
        expect(surfaceGlassFillHex().substring(3)).assertEqual('FFFFFF');
      }
    }));
    it('dark_surface_and_bubble_use_identical_rgba_at_every_level', 0, () => withSurfaceSettings((): void => {
      AppStorage.setOrCreate(KEY_APP_DARK, true);
      AppStorage.setOrCreate(KEY_SURFACE_GLASS_ON, true); AppStorage.setOrCreate(KEY_BUBBLE_GLASS_ON, true);
      for (const level of [-2, -1, 0, 1, 2]) {
        AppStorage.setOrCreate(KEY_SURFACE_GLASS_LEVEL, level); AppStorage.setOrCreate(KEY_BUBBLE_GLASS_LEVEL, level);
        expect(surfaceGlassFillHex()).assertEqual(bubbleTintFillHex(true, level));
        expect(surfaceGlassFill('#000000')).assertEqual(bubbleGlassFill('#000000'));
        expect(surfaceGlassFillHex().substring(3)).assertEqual('232E3C');
      }
    }));
    it('five_levels_have_distinct_increasing_opacity_and_standard_is_80_percent', 0, () => withSurfaceSettings((): void => {
      const expected: string[] = ['99', 'B3', 'CC', 'E6', 'F2'];
      let previous: number = 0;
      for (let level = -2; level <= 2; level++) {
        AppStorage.setOrCreate(KEY_SURFACE_GLASS_LEVEL, level);
        const alpha: string = surfaceGlassFillHex().substring(1, 3);
        expect(alpha).assertEqual(expected[level + 2]);
        expect(Number.parseInt(alpha, 16) > previous).assertTrue(); previous = Number.parseInt(alpha, 16);
      }
    }));
    it('unset_and_legacy_veil_levels_normalize_to_standard_without_changing_switches', 0, () => withSurfaceSettings((): void => {
      expect(SURFACE_GLASS_LEVEL_DEFAULT).assertEqual(0);
      for (const key of [KEY_SURFACE_GLASS_LEVEL, KEY_BUBBLE_GLASS_LEVEL]) { AppStorage.delete(key); }
      expect(surfaceGlassLevel()).assertEqual(0); expect(bubbleGlassLevel()).assertEqual(0);
      AppStorage.setOrCreate(KEY_SURFACE_GLASS_ON, true); AppStorage.setOrCreate(KEY_BUBBLE_GLASS_ON, false);
      AppStorage.setOrCreate(KEY_SURFACE_GLASS_LEVEL, SURFACE_GLASS_LEVEL_VEIL);
      AppStorage.setOrCreate(KEY_BUBBLE_GLASS_LEVEL, SURFACE_GLASS_LEVEL_VEIL);
      expect(surfaceGlassLevel()).assertEqual(0); expect(bubbleGlassLevel()).assertEqual(0);
      expect(surfaceGlassFillHex().substring(1, 3)).assertEqual('CC');
      expect(surfaceGlassOn()).assertTrue(); expect(bubbleGlassOn()).assertFalse();
    }));
    it('invalid_and_old_off_levels_cannot_index_outside_the_tint_palette', 0, () => withSurfaceSettings((): void => {
      for (const level of [-3, -99, 99, Number.NaN, Number.POSITIVE_INFINITY, Number.NEGATIVE_INFINITY]) {
        AppStorage.setOrCreate(KEY_SURFACE_GLASS_LEVEL, level); AppStorage.setOrCreate(KEY_BUBBLE_GLASS_LEVEL, level);
        expect(surfaceGlassLevel()).assertEqual(0); expect(bubbleGlassLevel()).assertEqual(0);
        expect(surfaceGlassFillHex().length).assertEqual(9);
        expect(surfaceGlassFillHex().substring(1, 3)).assertEqual('CC');
      }
    }));
    it('surface_and_bubble_on_off_switches_remain_independent', 0, () => withSurfaceSettings((): void => {
      for (const surface of [false, true]) { for (const bubble of [false, true]) {
        AppStorage.setOrCreate(KEY_SURFACE_GLASS_ON, surface); AppStorage.setOrCreate(KEY_BUBBLE_GLASS_ON, bubble);
        expect(surfaceGlassOn()).assertEqual(surface); expect(bubbleGlassOn()).assertEqual(bubble);
        expect(surfaceGlassFill('#123456') === '#123456').assertEqual(!surface);
        expect(bubbleGlassFill('#123456') === '#123456').assertEqual(!bubble);
      } }
    }));
    it('surface_and_bubble_levels_remain_independent', 0, () => withSurfaceSettings((): void => {
      AppStorage.setOrCreate(KEY_SURFACE_GLASS_LEVEL, -2); AppStorage.setOrCreate(KEY_BUBBLE_GLASS_LEVEL, 2);
      expect(surfaceGlassLevel()).assertEqual(-2); expect(bubbleGlassLevel()).assertEqual(2);
      AppStorage.setOrCreate(KEY_SURFACE_GLASS_LEVEL, 1); expect(bubbleGlassLevel()).assertEqual(2);
      AppStorage.setOrCreate(KEY_BUBBLE_GLASS_LEVEL, -1); expect(surfaceGlassLevel()).assertEqual(1);
    }));
    it('disabled_fill_preserves_resource_color_identity', 0, () => withSurfaceSettings((): void => {
      const solid: ResourceColor = $r('app.color.chat_bg');
      AppStorage.setOrCreate(KEY_SURFACE_GLASS_ON, false); AppStorage.setOrCreate(KEY_BUBBLE_GLASS_ON, false);
      expect(surfaceGlassFill(solid) === solid).assertTrue(); expect(bubbleGlassFill(solid) === solid).assertTrue();
    }));
    it('epoch_change_notifies_without_rewriting_selected_levels', 0, () => withSurfaceSettings((): void => {
      AppStorage.setOrCreate(SURFACE_GLASS_EPOCH, 9);
      AppStorage.setOrCreate(KEY_SURFACE_GLASS_LEVEL, -1); AppStorage.setOrCreate(KEY_BUBBLE_GLASS_LEVEL, 1);
      bumpSurfaceGlassEpoch(); expect(AppStorage.get<number>(SURFACE_GLASS_EPOCH)).assertEqual(10);
      bumpSurfaceGlassEpoch(); expect(AppStorage.get<number>(SURFACE_GLASS_EPOCH)).assertEqual(11);
      expect(surfaceGlassLevel()).assertEqual(-1); expect(bubbleGlassLevel()).assertEqual(1);
    }));
  });
}
