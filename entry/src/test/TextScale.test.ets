import { describe, expect, it } from '@ohos/hypium';
import {
  TEXT_SCALE_CAP_FOLD, TEXT_SCALE_CAP_TABLET, msgTextScale, scaledMsgTextSize
} from '../main/ets/util/textScale';
import {
  KEY_WIDTH_BREAKPOINT, WIDTH_BP_LG, WIDTH_BP_MD, WIDTH_BP_SM, WIDTH_BP_XL, WIDTH_BP_XS
} from '../main/ets/util/layoutBreakpoint';
import { chatEnv, mirrorChatEnvKey } from '../main/ets/util/chatEnvMirror';
import { KEY_TEXT_SIZE } from '../main/ets/store/AppSettings';

// 大屏消息正文按断点适度放大（官方 SPEC-13，2026-09-23 用户确认）。
export default function textScaleTest() {
  describe('TextScale', () => {
    it('手机不放大', 0, () => {
      expect(msgTextScale(WIDTH_BP_XS)).assertEqual(1);
      expect(msgTextScale(WIDTH_BP_SM)).assertEqual(1);
      expect(scaledMsgTextSize(16, WIDTH_BP_SM)).assertEqual(16);
    });

    // P0：折叠屏展开 ≤ 1.2 倍，平板 ≤ 1.5 倍；且都不小于 1 倍。
    it('各档倍数在官方上限以内且不缩小', 0, () => {
      expect(msgTextScale(WIDTH_BP_MD) >= 1).assertTrue();
      expect(msgTextScale(WIDTH_BP_MD) <= TEXT_SCALE_CAP_FOLD).assertTrue();
      for (const bp of [WIDTH_BP_LG, WIDTH_BP_XL]) {
        expect(msgTextScale(bp) >= msgTextScale(WIDTH_BP_MD)).assertTrue();
        expect(msgTextScale(bp) <= TEXT_SCALE_CAP_TABLET).assertTrue();
      }
    });

    it('放大后按半 vp 取整', 0, () => {
      expect(scaledMsgTextSize(16, WIDTH_BP_MD)).assertEqual(17.5);
      expect(scaledMsgTextSize(16, WIDTH_BP_LG)).assertEqual(19);
    });

    it('非法原值原样返回', 0, () => {
      expect(scaledMsgTextSize(0, WIDTH_BP_LG)).assertEqual(0);
    });

    // 镜像层：用户设置的原值与断点任何一个变化都要重算；设置页看到的仍是原值。
    it('会话环境镜像里的字号 = 设置原值 × 断点倍数', 0, () => {
      mirrorChatEnvKey(KEY_TEXT_SIZE, 16);
      mirrorChatEnvKey(KEY_WIDTH_BREAKPOINT, WIDTH_BP_LG);
      expect(chatEnv.msgTextSize).assertEqual(19);
      mirrorChatEnvKey(KEY_TEXT_SIZE, 20);
      expect(chatEnv.msgTextSize).assertEqual(24);
      mirrorChatEnvKey(KEY_WIDTH_BREAKPOINT, WIDTH_BP_SM);
      expect(chatEnv.msgTextSize).assertEqual(20);
    });
  });
}
