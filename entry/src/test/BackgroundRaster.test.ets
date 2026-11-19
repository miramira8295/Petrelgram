import { describe, expect, it } from '@ohos/hypium';
import {
  BackgroundRasterParams, combineDimming, patternOpacity, rasterSignature, wallpaperTakesUserDim
} from '../main/ets/util/chatBackgroundRaster';

function sampleBackground(): BackgroundRasterParams {
  return { colors: ['#102030', '#506070'], angle: 45, path: '/cache/pattern.png',
    isPattern: true, imageOpacity: 0.4, dimming: 0.2, width: 360, height: 800 };
}

export default function backgroundRasterTest() {
  describe('BackgroundRaster', (): void => {
    it('successive_dark_masks_flatten_to_the_same_opacity', 0, (): void => {
      expect(Math.round(combineDimming(0.2, 0.3) * 100)).assertEqual(44);
    });
    it('flattened_dark_masks_clamp_invalid_inputs', 0, (): void => {
      expect(combineDimming(-1, 2)).assertEqual(1);
    });
    it('solid_and_system_backgrounds_do_not_take_user_dim', 0, (): void => {
      expect(wallpaperTakesUserDim([], '')).assertFalse();
      expect(wallpaperTakesUserDim(['#1C1C1E'], '')).assertFalse();
    });
    it('gradients_patterns_and_photos_keep_user_dim', 0, (): void => {
      expect(wallpaperTakesUserDim(['#000000', '#222222'], '')).assertTrue();
      expect(wallpaperTakesUserDim(['#1C1C1E'], '/cache/p.svg')).assertTrue();
      expect(wallpaperTakesUserDim([], '/files/photo.jpg')).assertTrue();
    });
    it('sharp_rasters_do_not_reuse_the_old_blurred_disk_cache_namespace', 0, (): void => {
      const signature: string = rasterSignature(sampleBackground());
      expect(signature.startsWith('v8_sharp_')).assertTrue();
      expect(signature.includes('_blur')).assertFalse();
      expect(rasterSignature(sampleBackground())).assertEqual(signature);
    });
    it('each_pixel_affecting_input_invalidates_the_cached_raster', 0, (): void => {
      const source: BackgroundRasterParams = sampleBackground();
      const old: string = rasterSignature(source);
      const variants: BackgroundRasterParams[] = [
        sampleBackground(), sampleBackground(), sampleBackground(), sampleBackground(),
        sampleBackground(), sampleBackground(), sampleBackground(), sampleBackground()
      ];
      variants[0].colors = ['#ffffff'];
      variants[1].angle = 90;
      variants[2].path = '/cache/other.png';
      variants[3].isPattern = false;
      variants[4].imageOpacity = 0.5;
      variants[5].dimming = 0.2001;
      variants[6].width = 361;
      variants[7].height = 801;
      for (const variant of variants) {
        expect(rasterSignature(variant) === old).assertFalse();
      }
    });
    it('pattern_intensity_and_user_strength_remain_multiplicative', 0, (): void => {
      expect(patternOpacity(true, 0.4, 0.5)).assertEqual(0.2);
    });
    it('pattern_strength_keeps_visible_floor_and_opaque_ceiling', 0, (): void => {
      expect(patternOpacity(true, 0.4, 0)).assertEqual(0.04);
      expect(patternOpacity(true, 0.4, 4)).assertEqual(1);
    });
    it('photo_opacity_is_not_multiplied_by_pattern_strength', 0, (): void => {
      expect(patternOpacity(false, 1, 0)).assertEqual(1);
      expect(patternOpacity(false, 0.8, 0.5)).assertEqual(0.8);
    });
  });
}
