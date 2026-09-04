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

// 写入点旁路：AppStorage.setOrCreate 的同时调它一次。未列管的 key 静默忽略
// ——设置漏斗（setNumber/setBoolean/setString）会把所有设置键都送过来。
export function mirrorChatEnvKey(key: string, value: number | boolean | string): void {
  switch (key) {
    case 'appearanceEpoch': chatEnv.appearanceEpoch = value as number; break;
    case 'materialEpoch': chatEnv.materialEpoch = value as number; break;
    case 'languageEpoch': chatEnv.langEpoch = value as number; break;
    // 气泡走自己的开关（KEY_BUBBLE_GLASS_ON）：整体那一面开不开与气泡无关。
    case 'bubbleGlassOn': chatEnv.bubbleMaterialOn = value as boolean; break;
    case 'chatContentWidthVp': chatEnv.chatContentWidth = value as number; break;
    case 'keyboardHeightVp': chatEnv.keyboardHeightVp = value as number; break;
    case 'screenWidthVp': chatEnv.screenWidthVp = value as number; break;
    case 'screenHeightVp': chatEnv.screenHeightVp = value as number; break;
    case 'msgTextSize': chatEnv.msgTextSize = value as number; break;
    case 'bubbleRadius': chatEnv.bubbleRadius = value as number; break;
    case 'reduceAnimations': chatEnv.reduceAnim = value as boolean; break;
    case 'powerSavingActive': chatEnv.powerSaving = value as boolean; break;
    case 'powerChatEffects': chatEnv.chatEffects = value as boolean; break;
    case 'powerEffectMessage': chatEnv.messageEffects = value as boolean; break;
    case 'powerEffectReaction': chatEnv.reactionEffects = value as boolean; break;
    case 'powerAnimatedEmoji': chatEnv.animatedEmoji = value as boolean; break;
    case 'powerEmojiReactions': chatEnv.emojiReactions = value as boolean; break;
    case 'msgGestureScheme': chatEnv.gestureScheme = value as string; break;
    case 'powerEmojiChat': chatEnv.emojiChat = value as boolean; break;
    case 'powerAnimatedStickers': chatEnv.stickers = value as boolean; break;
    case 'powerStickerAutoplay': chatEnv.stickerAutoplay = value as boolean; break;
    case 'powerAutoplayGif': chatEnv.autoplayGif = value as boolean; break;
    case 'powerAutoplayVideo': chatEnv.autoplayVideo = value as boolean; break;
    case 'powerStickerLoop': chatEnv.stickerLoop = value as boolean; break;
    case 'powerEmojiStatus': chatEnv.emojiStatus = value as boolean; break;
    case 'appIsForeground': chatEnv.appIsForeground = value as boolean; break;
    case 'linkNavBusyUrl': chatEnv.linkNavBusy = value as string; break;
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
