import { describe, expect, it } from '@ohos/hypium';
import {
  chatEnv, mirrorChatEnvKey, mirroredChatEnvKeys, seedChatEnvFromStorage
} from '../main/ets/util/chatEnvMirror';
import {
  KEY_TEXT_SIZE, KEY_BUBBLE_RADIUS, KEY_REDUCE_ANIM, KEY_POWER_ACTIVE,
  KEY_POWER_CHAT_EFFECTS, KEY_POWER_EFFECT_MESSAGE, KEY_POWER_EFFECT_REACTION,
  KEY_POWER_EMOJI, KEY_POWER_EMOJI_REACTIONS, KEY_MSG_GESTURE,
  KEY_POWER_EMOJI_CHAT, KEY_POWER_STICKERS, KEY_POWER_STICKER_AUTOPLAY,
  KEY_POWER_AUTOPLAY_GIF, KEY_POWER_STICKER_LOOP, KEY_POWER_EMOJI_STATUS,
  KEY_POWER_AUTOPLAY_VIDEO
} from '../main/ets/store/AppSettings';
import { LINK_NAV_BUSY_KEY } from '../main/ets/util/linkTapGuard';
import { APPEARANCE_EPOCH } from '../main/ets/util/appearance';
// 气泡玻璃的开关源头已从「气泡材质」换成「界面模糊质感」（见 chatEnvMirror
// 里 bubbleMaterialOn 那段注释）。
// 气泡走自己的开关：整体那一面（KEY_SURFACE_GLASS_ON）不进这条镜像。
import { KEY_BUBBLE_GLASS_ON } from '../main/ets/util/surfaceGlass';
import { LANGUAGE_EPOCH } from '../main/ets/util/appLanguage';
import { MATERIAL_EPOCH } from '../main/ets/util/overlayMaterial';
import { CHAT_CONTENT_WIDTH_KEY } from '../main/ets/util/chatContentWidth';

export default function chatEnvMirrorTest() {
  describe('chatEnvMirror', () => {
    it('字面量键与真常量一致（镜像不引常量是为了免循环依赖，靠这里兜底）', 0, (): void => {
      const keys = mirroredChatEnvKeys();
      const constants: string[] = [
        APPEARANCE_EPOCH, MATERIAL_EPOCH, LANGUAGE_EPOCH, KEY_BUBBLE_GLASS_ON,
        CHAT_CONTENT_WIDTH_KEY, 'keyboardHeightVp', 'screenWidthVp', 'screenHeightVp',
        KEY_TEXT_SIZE, KEY_BUBBLE_RADIUS, KEY_REDUCE_ANIM, KEY_POWER_ACTIVE,
        KEY_POWER_CHAT_EFFECTS, KEY_POWER_EFFECT_MESSAGE, KEY_POWER_EFFECT_REACTION,
        KEY_POWER_EMOJI, KEY_POWER_EMOJI_REACTIONS, KEY_MSG_GESTURE,
        KEY_POWER_EMOJI_CHAT, KEY_POWER_STICKERS, KEY_POWER_STICKER_AUTOPLAY,
        KEY_POWER_AUTOPLAY_GIF, KEY_POWER_AUTOPLAY_VIDEO, KEY_POWER_STICKER_LOOP, KEY_POWER_EMOJI_STATUS,
        'appIsForeground', LINK_NAV_BUSY_KEY
      ];
      expect(keys.length).assertEqual(constants.length);
      for (const constant of constants) {
        expect(keys.indexOf(constant) >= 0).assertTrue();
      }
    });
    it('按键写入落到对应字段', 0, (): void => {
      mirrorChatEnvKey(KEY_TEXT_SIZE, 19);
      expect(chatEnv.msgTextSize).assertEqual(19);
      mirrorChatEnvKey(KEY_POWER_ACTIVE, true);
      expect(chatEnv.powerSaving).assertTrue();
      mirrorChatEnvKey(KEY_MSG_GESTURE, 'classic');
      expect(chatEnv.gestureScheme).assertEqual('classic');
      mirrorChatEnvKey(APPEARANCE_EPOCH, 7);
      expect(chatEnv.appearanceEpoch).assertEqual(7);
      // 未列管的键静默忽略，不抛不写。
      mirrorChatEnvKey('someUnrelatedKey', 42);
      expect(chatEnv.msgTextSize).assertEqual(19);
    });
    it('播种读 AppStorage 现值，缺失的键保持原样', 0, (): void => {
      AppStorage.setOrCreate(KEY_BUBBLE_RADIUS, 13);
      mirrorChatEnvKey(KEY_TEXT_SIZE, 15);
      seedChatEnvFromStorage();
      expect(chatEnv.bubbleRadius).assertEqual(13);
    });
  });
}
