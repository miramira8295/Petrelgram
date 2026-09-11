import { describe, expect, it } from '@ohos/hypium';
import { backgroundBlurRadius, combineDimming } from '../main/ets/util/chatBackgroundRaster';

// backgroundBlurRadius(path, isPattern, blurred, userBlur) — userBlur is the
// user's own Chat Background slider setting (KEY_BG_BLUR, AppSettings.ets,
// default 8). Covers all four background shapes at two different slider
// settings each, including 0 (fully sharp).
export default function backgroundBlurTest() {
  describe('BackgroundBlur', (): void => {
    it('a_tiled_pattern_uses_the_user_setting_regardless_of_the_blurred_flag', 0, (): void => {
      expect(backgroundBlurRadius('/cache/pattern.png', true, false, 8)).assertEqual(8);
    });
    it('a_tiled_pattern_uses_the_user_setting_even_when_blurred_flag_set', 0, (): void => {
      expect(backgroundBlurRadius('/cache/pattern.png', true, true, 8)).assertEqual(8);
    });
    it('a_tiled_pattern_follows_the_user_setting_up_to_the_slider_max', 0, (): void => {
      expect(backgroundBlurRadius('/cache/pattern.png', true, false, 20)).assertEqual(20);
    });
    it('a_tiled_pattern_stays_sharp_when_the_user_dials_the_slider_to_zero', 0, (): void => {
      expect(backgroundBlurRadius('/cache/pattern.png', true, true, 0)).assertEqual(0);
    });
    it('a_plain_photo_wallpaper_stays_sharp_unless_flagged_blurred', 0, (): void => {
      expect(backgroundBlurRadius('/cache/wall.jpg', false, false, 8)).assertEqual(0);
    });
    it('a_plain_photo_wallpaper_stays_sharp_unless_flagged_blurred_at_another_setting', 0, (): void => {
      expect(backgroundBlurRadius('/cache/wall.jpg', false, false, 20)).assertEqual(0);
    });
    it('a_flagged_blurred_photo_wallpaper_uses_the_user_setting', 0, (): void => {
      expect(backgroundBlurRadius('/cache/wall.jpg', false, true, 8)).assertEqual(8);
    });
    it('a_flagged_blurred_photo_wallpaper_follows_a_different_user_setting', 0, (): void => {
      expect(backgroundBlurRadius('/cache/wall.jpg', false, true, 20)).assertEqual(20);
    });
    it('a_flagged_blurred_photo_wallpaper_stays_sharp_when_the_user_dials_to_zero', 0, (): void => {
      expect(backgroundBlurRadius('/cache/wall.jpg', false, true, 0)).assertEqual(0);
    });
    it('a_pure_gradient_stays_sharp_regardless_of_the_user_setting', 0, (): void => {
      expect(backgroundBlurRadius('', false, false, 8)).assertEqual(0);
    });
    it('a_pure_gradient_stays_sharp_even_with_blurred_flag_and_a_nonzero_setting', 0, (): void => {
      expect(backgroundBlurRadius('', false, true, 20)).assertEqual(0);
    });
    it('successive_dark_masks_flatten_to_the_same_opacity', 0, (): void => {
      expect(Math.round(combineDimming(0.2, 0.3) * 100)).assertEqual(44);
    });
    it('flattened_dark_masks_clamp_invalid_inputs', 0, (): void => {
      expect(combineDimming(-1, 2)).assertEqual(1);
    });
  });
}
