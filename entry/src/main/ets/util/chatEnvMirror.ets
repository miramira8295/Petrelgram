// 聊天环境值的 @ObservedV2 镜像（P4 批 0，见 docs/superpowers/specs/
// 2026-09-02-p4-bubble-v2-survey.md 与 08-26 P3 survey 的方案 A）。
//
// V2 组件没有 @StorageProp 的等价物（官方 FAQ 明说），而气泡子树迁 V2 后
// 仍要响应这些全局单值。做法：AppStorage 的**写入点**旁路一份进这个镜像，
// V2 组件读 `chatEnv.x`（@Trace 自带观察）。AppStorage 本身一行不动，
// V1 世界的 513 处读点零影响。
//
// key 用字符串字面量而不是 import 常量：常量分散在 AppSettings/appearance/
// appLanguage/overlayMaterial，而这些模块都要 import 本文件做双写——引常量
// 就是循环依赖。字面量与常量的一致性由 ChatEnvMirror.test 拿真常量断言兜底。
//
// 本批（批 0）尚无读者：纯双写，零行为变化。

@ObservedV2
export class ChatEnvMirror {
  @Trace appearanceEpoch: number = 0;
  @Trace materialEpoch: number = 0;
  @Trace langEpoch: number = 0;
  // 气泡玻璃的总开关。**源头已经从「气泡材质」换成「界面模糊质感」**
  // （KEY_SURFACE_GLASS_ON）——旧那个开关指望的是 systemMaterial，而系统收回了
  // HdsNav 级别以外的材质，它在这台设备上永远画不出东西。字段名保留，
  // 因为气泡侧读的就是这个名字，改名只会制造一次无意义的大 diff。
  @Trace bubbleMaterialOn: boolean = false;
  @Trace chatContentWidth: number = 360;
  @Trace keyboardHeightVp: number = 0;
  @Trace screenWidthVp: number = 360;
  @Trace screenHeightVp: number = 780;
  @Trace msgTextSize: number = 0;
  @Trace bubbleRadius: number = 0;
  @Trace reduceAnim: boolean = false;
  @Trace powerSaving: boolean = false;
  @Trace chatEffects: boolean = true;
  @Trace messageEffects: boolean = true;
  @Trace reactionEffects: boolean = false;
  @Trace animatedEmoji: boolean = true;
  @Trace emojiReactions: boolean = true;
  @Trace gestureScheme: string = '';
  // —— P4 批 3a 扩容（MessageBubble 迁移的读者预备）——
  @Trace emojiChat: boolean = true;
  @Trace stickers: boolean = true;
  @Trace stickerAutoplay: boolean = true;
  @Trace autoplayGif: boolean = true;
  @Trace autoplayVideo: boolean = true;
  @Trace stickerLoop: boolean = true;
  @Trace emojiStatus: boolean = true;
  @Trace appIsForeground: boolean = true;
  @Trace linkNavBusy: string = '';
}

export const chatEnv: ChatEnvMirror = new ChatEnvMirror();

// 镜像列管的键。数值型与布尔/字符串分开写是为了免去逐字段的类型断言噪音。
const MIRRORED_KEYS: string[] = [
  'appearanceEpoch', 'materialEpoch', 'languageEpoch', 'bubbleGlassOn',
  'chatContentWidthVp', 'keyboardHeightVp', 'screenWidthVp', 'screenHeightVp',
  'msgTextSize', 'bubbleRadius', 'reduceAnimations', 'powerSavingActive',
  'powerChatEffects', 'powerEffectMessage', 'powerEffectReaction',
  'powerAnimatedEmoji', 'powerEmojiReactions', 'msgGestureScheme',
  'powerEmojiChat', 'powerAnimatedStickers', 'powerStickerAutoplay',
  'powerAutoplayGif', 'powerAutoplayVideo', 'powerStickerLoop', 'powerEmojiStatus',
  'appIsForeground', 'linkNavBusyUrl'
];

export function mirroredChatEnvKeys(): string[] {
  return MIRRORED_KEYS.slice();
}

// 【每个 case 都先比再写】看着啰嗦，但这条短路是必要的：
// store/AppSettings.applyPowerState 在**每一次** COMMON_EVENT_BATTERY_CHANGED 上
// 都无条件重写省电键并调本函数，而充电中电量变化是很频繁的。裸赋值意味着
// 每次都动一下 @Trace 字段——若 ArkUI V2 对同值赋值不短路，下游那些
// @Monitor('env.powerSaving', ...) 就会被无谓地叫醒。
// TgsStickerView 的 onPowerChanged 正是这样一个订阅者，它被叫醒时会重启动画
// （贴纸播到一半跳回开头的成因之一）。
// 官方没有承诺 @Trace 的同值短路行为，与其赌，不如在写入侧自己挡掉。
//
// 写入点旁路：AppStorage.setOrCreate 的同时调它一次。未列管的 key 静默忽略
// ——设置漏斗（setNumber/setBoolean/setString）会把所有设置键都送过来。
export function mirrorChatEnvKey(key: string, value: number | boolean | string): void {
  switch (key) {
    case 'appearanceEpoch':
      if (chatEnv.appearanceEpoch !== (value as number)) { chatEnv.appearanceEpoch = value as number; }
      break;
    case 'materialEpoch':
      if (chatEnv.materialEpoch !== (value as number)) { chatEnv.materialEpoch = value as number; }
      break;
    case 'languageEpoch':
      if (chatEnv.langEpoch !== (value as number)) { chatEnv.langEpoch = value as number; }
      break;
    // 气泡走自己的开关（KEY_BUBBLE_GLASS_ON）：整体那一面开不开与气泡无关。
    case 'bubbleGlassOn':
      if (chatEnv.bubbleMaterialOn !== (value as boolean)) { chatEnv.bubbleMaterialOn = value as boolean; }
      break;
    case 'chatContentWidthVp':
      if (chatEnv.chatContentWidth !== (value as number)) { chatEnv.chatContentWidth = value as number; }
      break;
    case 'keyboardHeightVp':
      if (chatEnv.keyboardHeightVp !== (value as number)) { chatEnv.keyboardHeightVp = value as number; }
      break;
    case 'screenWidthVp':
      if (chatEnv.screenWidthVp !== (value as number)) { chatEnv.screenWidthVp = value as number; }
      break;
    case 'screenHeightVp':
      if (chatEnv.screenHeightVp !== (value as number)) { chatEnv.screenHeightVp = value as number; }
      break;
    case 'msgTextSize':
      if (chatEnv.msgTextSize !== (value as number)) { chatEnv.msgTextSize = value as number; }
      break;
    case 'bubbleRadius':
      if (chatEnv.bubbleRadius !== (value as number)) { chatEnv.bubbleRadius = value as number; }
      break;
    case 'reduceAnimations':
      if (chatEnv.reduceAnim !== (value as boolean)) { chatEnv.reduceAnim = value as boolean; }
      break;
    case 'powerSavingActive':
      if (chatEnv.powerSaving !== (value as boolean)) { chatEnv.powerSaving = value as boolean; }
      break;
    case 'powerChatEffects':
      if (chatEnv.chatEffects !== (value as boolean)) { chatEnv.chatEffects = value as boolean; }
      break;
    case 'powerEffectMessage':
      if (chatEnv.messageEffects !== (value as boolean)) { chatEnv.messageEffects = value as boolean; }
      break;
    case 'powerEffectReaction':
      if (chatEnv.reactionEffects !== (value as boolean)) { chatEnv.reactionEffects = value as boolean; }
      break;
    case 'powerAnimatedEmoji':
      if (chatEnv.animatedEmoji !== (value as boolean)) { chatEnv.animatedEmoji = value as boolean; }
      break;
    case 'powerEmojiReactions':
      if (chatEnv.emojiReactions !== (value as boolean)) { chatEnv.emojiReactions = value as boolean; }
      break;
    case 'msgGestureScheme':
      if (chatEnv.gestureScheme !== (value as string)) { chatEnv.gestureScheme = value as string; }
      break;
    case 'powerEmojiChat':
      if (chatEnv.emojiChat !== (value as boolean)) { chatEnv.emojiChat = value as boolean; }
      break;
    case 'powerAnimatedStickers':
      if (chatEnv.stickers !== (value as boolean)) { chatEnv.stickers = value as boolean; }
      break;
    case 'powerStickerAutoplay':
      if (chatEnv.stickerAutoplay !== (value as boolean)) { chatEnv.stickerAutoplay = value as boolean; }
      break;
    case 'powerAutoplayGif':
      if (chatEnv.autoplayGif !== (value as boolean)) { chatEnv.autoplayGif = value as boolean; }
      break;
    case 'powerAutoplayVideo':
      if (chatEnv.autoplayVideo !== (value as boolean)) { chatEnv.autoplayVideo = value as boolean; }
      break;
    case 'powerStickerLoop':
      if (chatEnv.stickerLoop !== (value as boolean)) { chatEnv.stickerLoop = value as boolean; }
      break;
    case 'powerEmojiStatus':
      if (chatEnv.emojiStatus !== (value as boolean)) { chatEnv.emojiStatus = value as boolean; }
      break;
    case 'appIsForeground':
      if (chatEnv.appIsForeground !== (value as boolean)) { chatEnv.appIsForeground = value as boolean; }
      break;
    case 'linkNavBusyUrl':
      if (chatEnv.linkNavBusy !== (value as string)) { chatEnv.linkNavBusy = value as string; }
      break;
    default: break;
  }
}

// 整体播种：initSettings 收尾时调一次，把启动期在双写接线之前落进 AppStorage
// 的现值补齐。之后的一切变化都由写入点双写维护。
export function seedChatEnvFromStorage(): void {
  for (const key of MIRRORED_KEYS) {
    const value: number | boolean | string | undefined =
      AppStorage.get<number | boolean | string>(key);
    if (value !== undefined) {
      mirrorChatEnvKey(key, value);
    }
  }
}
