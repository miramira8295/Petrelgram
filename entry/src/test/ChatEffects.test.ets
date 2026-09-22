import { describe, expect, it } from '@ohos/hypium';
import {
  KEY_POWER_ACTIVE, KEY_POWER_CHAT_EFFECTS, KEY_POWER_EFFECT_BLUR, KEY_POWER_EFFECT_MENU,
  KEY_POWER_EFFECT_REPLY, KEY_POWER_SMOOTH_TRANSITIONS, powerGroupAnimationDuration,
  POWER_BOOLEAN_FALSE_DEFAULTS, POWER_BOOLEAN_TRUE_EFFECT_DEFAULTS
} from '../main/ets/store/AppSettings';
import { chatEffectDurationOf } from '../main/ets/util/chatEffects';
import { STICKER_FLY_MS } from '../main/ets/util/chatPageTuning';

// `chatEffectDurationOf` 是 B1 从 ChatPage 的 `private chatEffectDuration` 搬出来的
// 纯函数（唯一改动：`this.reduceAnimations` 变成第一个显式参数）。它有三道闸，
// 任何一道关上就返回 0：
//   1. 无障碍「减弱动效」（reduceAnimations 参数）
//   2. 省电总开关下的「平滑过渡」 KEY_POWER_SMOOTH_TRANSITIONS
//   3. powerGroupAnimationDuration(KEY_POWER_CHAT_EFFECTS, key, ms)：组闸 + 单项闸
//
// 第 2、3 道闸读 AppStorage（`powerFeatureEnabled` = `AppStorage.get(key) ?? true`
// 且 `!powerSavingActive()`），所以每条用例先用 `AppStorage.setOrCreate` 把相关键
// 摆到确定状态再断言——缺省值是 true/false 的隐式依赖，不摆就不可复现。

// 三道闸全开：这是"用户什么都没关"的出厂状态。
function allOn(): void {
  AppStorage.setOrCreate(KEY_POWER_ACTIVE, false);
  AppStorage.setOrCreate(KEY_POWER_SMOOTH_TRANSITIONS, true);
  AppStorage.setOrCreate(KEY_POWER_CHAT_EFFECTS, true);
  AppStorage.setOrCreate(KEY_POWER_EFFECT_MENU, true);
  AppStorage.setOrCreate(KEY_POWER_EFFECT_REPLY, true);
  AppStorage.setOrCreate(KEY_POWER_EFFECT_BLUR, true);
}

export default function chatEffectsTest() {
  describe('chatEffectDurationOf', () => {
    it('减弱动效恒返回 0——它比任何省电开关都优先', 0, (): void => {
      allOn();
      // 闸全开也一样是 0：无障碍诉求不该被"省电没开"救回来。
      expect(chatEffectDurationOf(true, KEY_POWER_EFFECT_MENU, STICKER_FLY_MS)).assertEqual(0);
      expect(chatEffectDurationOf(true, KEY_POWER_EFFECT_REPLY, 320)).assertEqual(0);
      expect(chatEffectDurationOf(true, KEY_POWER_EFFECT_BLUR, 300)).assertEqual(0);
    });

    it('闸全开时原样透传时长', 0, (): void => {
      allOn();
      // 贴纸飞行 260ms（STICKER_FLY_MS）与引用回弹 320ms 是两个不同 key 的真实调用点。
      expect(chatEffectDurationOf(false, KEY_POWER_EFFECT_MENU, STICKER_FLY_MS))
        .assertEqual(STICKER_FLY_MS);
      expect(chatEffectDurationOf(false, KEY_POWER_EFFECT_REPLY, 320)).assertEqual(320);
    });

    it('与它内部调用的 powerGroupAnimationDuration 结果逐字一致', 0, (): void => {
      allOn();
      expect(chatEffectDurationOf(false, KEY_POWER_EFFECT_MENU, STICKER_FLY_MS))
        .assertEqual(powerGroupAnimationDuration(KEY_POWER_CHAT_EFFECTS, KEY_POWER_EFFECT_MENU,
          STICKER_FLY_MS));
      // 单项闸关掉时两边也必须一起变 0——转发层不许自己"兜底"出一个非零值。
      AppStorage.setOrCreate(KEY_POWER_EFFECT_BLUR, false);
      expect(chatEffectDurationOf(false, KEY_POWER_EFFECT_BLUR, 300))
        .assertEqual(powerGroupAnimationDuration(KEY_POWER_CHAT_EFFECTS, KEY_POWER_EFFECT_BLUR, 300));
      expect(chatEffectDurationOf(false, KEY_POWER_EFFECT_BLUR, 300)).assertEqual(0);
      allOn();
    });

    it('关掉「平滑过渡」总闸，所有 key 一起归零', 0, (): void => {
      allOn();
      AppStorage.setOrCreate(KEY_POWER_SMOOTH_TRANSITIONS, false);
      expect(chatEffectDurationOf(false, KEY_POWER_EFFECT_MENU, STICKER_FLY_MS)).assertEqual(0);
      expect(chatEffectDurationOf(false, KEY_POWER_EFFECT_REPLY, 320)).assertEqual(0);
      allOn();
    });

    it('关掉「聊天动效」组闸，所有 key 一起归零', 0, (): void => {
      allOn();
      AppStorage.setOrCreate(KEY_POWER_CHAT_EFFECTS, false);
      expect(chatEffectDurationOf(false, KEY_POWER_EFFECT_MENU, STICKER_FLY_MS)).assertEqual(0);
      expect(chatEffectDurationOf(false, KEY_POWER_EFFECT_BLUR, 300)).assertEqual(0);
      allOn();
    });

    it('单项闸只掐自己那一项，不牵连别的 key', 0, (): void => {
      allOn();
      AppStorage.setOrCreate(KEY_POWER_EFFECT_MENU, false);
      expect(chatEffectDurationOf(false, KEY_POWER_EFFECT_MENU, STICKER_FLY_MS)).assertEqual(0);
      expect(chatEffectDurationOf(false, KEY_POWER_EFFECT_REPLY, 320)).assertEqual(320);
      allOn();
    });

    it('省电模式生效时，即使各闸都是 true 也归零', 0, (): void => {
      allOn();
      // powerFeatureEnabled 的第二个合取项是 `!powerSavingActive()`：低电自动降级
      // 不需要逐个改用户开关，一个总旗子就把动效全停。
      AppStorage.setOrCreate(KEY_POWER_ACTIVE, true);
      expect(chatEffectDurationOf(false, KEY_POWER_EFFECT_MENU, STICKER_FLY_MS)).assertEqual(0);
      expect(chatEffectDurationOf(false, KEY_POWER_EFFECT_REPLY, 320)).assertEqual(0);
      allOn();
    });

    it('时长为 0 时不会被放大成非零', 0, (): void => {
      allOn();
      expect(chatEffectDurationOf(false, KEY_POWER_EFFECT_MENU, 0)).assertEqual(0);
    });
  });

  // 【为什么把一个"默认值"钉成用例】2026-09-22：跳转落点的气泡脉冲上线以来
  // **一次都没被看见过**——KEY_POWER_EFFECT_REPLY 当时和背景动效、模糊缩放并列
  // 在默认关那一组，于是 chatEffectDurationOf 恒返回 0，JumpFlashState 整段动画
  // 连起步都没有（真机探针 rise=0 settle=0）。这种"功能在，但默认值把它掐死了"
  // 的缺陷编译和其余单测全抓不到，只能靠钉分组。
  describe('power effect defaults', () => {
    it('跳转落点脉冲所在的开关默认开', 0, (): void => {
      expect(POWER_BOOLEAN_TRUE_EFFECT_DEFAULTS.indexOf(KEY_POWER_EFFECT_REPLY) >= 0).assertTrue();
      expect(POWER_BOOLEAN_FALSE_DEFAULTS.indexOf(KEY_POWER_EFFECT_REPLY) < 0).assertTrue();
    });

    // 默认关那一组剩下三项是**持续**开销（背景动效、模糊缩放）或**每条消息都
    // 可能触发**的（回应动画），默认关是有意的，别顺手一起翻。
    it('持续型特效仍然默认关', 0, (): void => {
      expect(POWER_BOOLEAN_FALSE_DEFAULTS.length).assertEqual(3);
      expect(POWER_BOOLEAN_FALSE_DEFAULTS.indexOf(KEY_POWER_EFFECT_BLUR) >= 0).assertTrue();
    });
  });
}
