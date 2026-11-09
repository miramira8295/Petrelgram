import { describe, expect, it } from '@ohos/hypium';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { isDarkColorMode } from '../main/ets/util/theme';

export default function themeTest() {
  describe('Theme', (): void => {
    // COLOR_MODE_DARK === 0, the value most APIs would expect to mean
    // "light" or "off" — this is the exact confusion that caused the
    // original bug (see background-diagnosis-report.md), so it is pinned
    // down explicitly here.
    it('treats_color_mode_dark_as_dark', 0, (): void => {
      expect(isDarkColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK)).assertTrue();
    });
    it('treats_color_mode_light_as_not_dark', 0, (): void => {
      expect(isDarkColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT)).assertFalse();
    });
    it('treats_color_mode_not_set_as_not_dark', 0, (): void => {
      expect(isDarkColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET)).assertFalse();
    });
  });
}
