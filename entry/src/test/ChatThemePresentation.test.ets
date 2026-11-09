import { describe, expect, it } from '@ohos/hypium';
import { TdObject } from '../main/ets/tdkit/TdTypes';
import { chatThemePreviewOf } from '../main/ets/util/chatThemePresentation';

function theme(name: string): TdObject {
  const bgFill: TdObject = { '@type': 'backgroundFillFreeformGradient' };
  bgFill['colors'] = [0x111111, 0x222222];
  const bgType: TdObject = { '@type': 'backgroundTypeFill' };
  bgType['fill'] = bgFill;
  const background: TdObject = { '@type': 'background' };
  background['id'] = '7';
  background['type'] = bgType;
  const outFill: TdObject = { '@type': 'backgroundFillSolid' };
  outFill['color'] = 0x00AA55;
  const settings: TdObject = { '@type': 'themeSettings' };
  settings['accent_color'] = 0x3390EC;
  settings['background'] = background;
  settings['outgoing_message_fill'] = outFill;
  const value: TdObject = { '@type': 'chatTheme' };
  value['name'] = name;
  value['light_settings'] = settings;
  value['dark_settings'] = settings;
  return value;
}

export default function chatThemePresentationTest() {
  describe('ChatThemePresentation', (): void => {
    it('maps_theme_to_preview_colors', 0, (): void => {
      const preview = chatThemePreviewOf(theme('🐥'), false);
      expect(preview !== null).assertTrue();
      expect(preview?.name).assertEqual('🐥');
      expect(preview?.backgroundColors.join(',')).assertEqual('#111111,#222222');
      expect(preview?.bubbleColors.join(',')).assertEqual('#00AA55');
      expect(preview?.accent).assertEqual('#3390EC');
    });
    it('uses_dark_settings_when_requested', 0, (): void => {
      const value = theme('🌙');
      const darkFill: TdObject = { '@type': 'backgroundFillSolid' };
      darkFill['color'] = 0x000033;
      const darkType: TdObject = { '@type': 'backgroundTypeFill' };
      darkType['fill'] = darkFill;
      const darkBg: TdObject = { '@type': 'background' };
      darkBg['type'] = darkType;
      const darkSettings: TdObject = { '@type': 'themeSettings' };
      darkSettings['background'] = darkBg;
      value['dark_settings'] = darkSettings;
      const preview = chatThemePreviewOf(value, true);
      expect(preview?.backgroundColors.join(',')).assertEqual('#000033');
    });
    it('rejects_theme_without_name', 0, (): void => {
      const value: TdObject = { '@type': 'chatTheme' };
      expect(chatThemePreviewOf(value, false) === null).assertTrue();
    });
  });
}
