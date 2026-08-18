import { preferences } from '@kit.ArkData';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { batteryInfo, commonEventManager } from '@kit.BasicServicesKit';
import { CACHE_LIMIT_DEFAULT } from './CacheLimit';
import { GESTURE_CLASSIC } from '../util/messageGestures';

// User settings that outlive the process. Each one is mirrored into AppStorage
// so any component can bind it with @StorageProp and re-render on change, while
// Preferences keeps the value across restarts.
//
// Only settings the app actually honours live here — a switch that changes
// nothing is worse than no switch at all.

const STORE_NAME: string = 'app_settings';

// AppStorage keys (also the Preferences keys — one name per setting).
export const KEY_TEXT_SIZE: string = 'msgTextSize';        // message font size, vp
export const KEY_BUBBLE_RADIUS: string = 'bubbleRadius';   // message corner radius, vp
export const KEY_THREE_LINES: string = 'chatListThreeLines'; // chat list row shows 2 or 3 lines
export const KEY_NIGHT_MODE: string = 'nightMode';         // 'system' | 'dark' | 'light'
export const KEY_REDUCE_ANIM: string = 'reduceAnimations'; // stop autoplaying animated stickers
export const KEY_SEND_BY_ENTER: string = 'sendByEnter';    // Enter sends instead of newline
// 聊天详情页的手势方案：'classic'（长按出菜单）或 'tapFirst'（单击出菜单、
// 长按进多选）。取值与解释见 util/messageGestures——不认识的值一律当 classic。
export const KEY_MSG_GESTURE: string = 'msgGestureScheme';
// 深色模式下压在聊天背景上的黑色遮罩，0..1。默认 0（不改变任何人现有的
// 观感），由设置里的滑杆调。只在深色模式生效，浅色模式读到也不画。
export const KEY_CHAT_DIM: string = 'chatDarkDim';
export const CHAT_DIM_MAX: number = 0.8;
// 'default' (follow system) or a BCP-47 tag. The language actually in force is
// the platform's — setAppPreferredLanguage() persists on its own and this is
// never read back to apply it. It exists because the platform can report the
// effective language but not whether the user chose it, and the settings page
// has to know which row to tick.
export const KEY_APP_LANGUAGE: string = 'appLanguage';
// Power saving. Threshold: 0 = off, 10..100 = activate at/below this SOC,
// 101 = always on. User choices are kept separately from the derived active
// flag, so leaving low-power mode restores the exact previous behaviour.
export const KEY_POWER_THRESHOLD: string = 'powerSavingThreshold';
export const KEY_POWER_ACTIVE: string = 'powerSavingActive';
export const KEY_BATTERY_PERCENT: string = 'deviceBatteryPercent';
export const KEY_POWER_STICKERS: string = 'powerAnimatedStickers';
export const KEY_POWER_EMOJI: string = 'powerAnimatedEmoji';
export const KEY_POWER_CHAT_EFFECTS: string = 'powerChatEffects';
export const KEY_POWER_CALL_ANIMATIONS: string = 'powerCallAnimations';
export const KEY_POWER_AUTOPLAY_VIDEO: string = 'powerAutoplayVideo';
export const KEY_POWER_AUTOPLAY_GIF: string = 'powerAutoplayGif';
export const KEY_POWER_PARTICLES: string = 'powerParticles';
export const KEY_POWER_SMOOTH_TRANSITIONS: string = 'powerSmoothTransitions';
export const KEY_POWER_STICKER_AUTOPLAY: string = 'powerStickerAutoplay';
export const KEY_POWER_STICKER_LOOP: string = 'powerStickerLoop';
export const KEY_POWER_EMOJI_CHAT: string = 'powerEmojiChat';
export const KEY_POWER_EMOJI_REACTIONS: string = 'powerEmojiReactions';
export const KEY_POWER_EMOJI_STATUS: string = 'powerEmojiStatus';
export const KEY_POWER_EFFECT_MESSAGE: string = 'powerEffectMessage';
export const KEY_POWER_EFFECT_REACTION: string = 'powerEffectReaction';
export const KEY_POWER_EFFECT_REPLY: string = 'powerEffectReply';
export const KEY_POWER_EFFECT_MENU: string = 'powerEffectMenu';
export const KEY_POWER_EFFECT_BLUR: string = 'powerEffectBlur';
export const KEY_POWER_EFFECT_BACKGROUND: string = 'powerEffectBackground';
// Data & storage. The current network is supplied by NetworkStateService and
// is intentionally kept in AppStorage only; user choices below are persisted.
export const KEY_CURRENT_NETWORK_TYPE: string = 'currentNetworkType'; // none | wifi | mobile | roaming | other
export const KEY_AUTOSAVE_PRIVATE: string = 'autosavePrivate';
export const KEY_AUTOSAVE_GROUP: string = 'autosaveGroup';
export const KEY_AUTOSAVE_CHANNEL: string = 'autosaveChannel';
// 缓存上限（字节）。0 = 不限，见 CacheLimit.ets。
export const KEY_CACHE_LIMIT: string = 'cacheLimit';
// 聊天背景模糊半径（vp）。用户可调，见 chatBackgroundRaster.ets 的
// backgroundBlurRadius —— pattern 与"需要模糊"的照片壁纸都用这一个值。
export const KEY_BG_BLUR: string = 'bgBlur';
export const BG_BLUR_DEFAULT: number = 8;
export const BG_BLUR_MIN: number = 0;
export const BG_BLUR_MAX: number = 20;
// 自动播放时静音。默认开启 —— 聊天列表里突然出声是最招人烦的行为。
export const KEY_AUTOPLAY_MUTED: string = 'autoplayMuted';
export const POWER_THRESHOLD_DEFAULT: number = 10;

export const TEXT_SIZE_MIN: number = 12;
export const TEXT_SIZE_MAX: number = 24;
export const TEXT_SIZE_DEFAULT: number = 16;
export const RADIUS_MIN: number = 0;
export const RADIUS_MAX: number = 20;
export const RADIUS_DEFAULT: number = 17;

export const NIGHT_SYSTEM: string = 'system';
export const NIGHT_DARK: string = 'dark';
export const NIGHT_LIGHT: string = 'light';

let store: preferences.Preferences | null = null;
let appContext: common.Context | null = null;
let batterySubscriber: commonEventManager.CommonEventSubscriber | null = null;

const POWER_BOOLEAN_DEFAULTS: string[] = [
  KEY_POWER_STICKERS,
  KEY_POWER_EMOJI,
  KEY_POWER_CHAT_EFFECTS,
  KEY_POWER_CALL_ANIMATIONS,
  KEY_POWER_AUTOPLAY_VIDEO,
  KEY_POWER_AUTOPLAY_GIF,
  KEY_POWER_PARTICLES,
  KEY_POWER_SMOOTH_TRANSITIONS,
  KEY_POWER_STICKER_AUTOPLAY,
  KEY_POWER_STICKER_LOOP,
  KEY_POWER_EMOJI_CHAT,
  KEY_POWER_EMOJI_REACTIONS,
  KEY_POWER_EMOJI_STATUS
];

const POWER_BOOLEAN_FALSE_DEFAULTS: string[] = [
  KEY_POWER_EFFECT_REACTION,
  KEY_POWER_EFFECT_REPLY,
  KEY_POWER_EFFECT_BLUR,
  KEY_POWER_EFFECT_BACKGROUND
];

const POWER_BOOLEAN_TRUE_EFFECT_DEFAULTS: string[] = [
  KEY_POWER_EFFECT_MESSAGE,
  KEY_POWER_EFFECT_MENU
];

// 本机通知开关（按会话类型）。优先级高于 TDLib 的服务端通知设置：
// 这里关掉就不弹，不受服务端/其他设备影响；这里开着才继续看服务端静音状态。
// 三项默认开启，由用户按需关闭。
export const KEY_NOTIFY_PRIVATE: string = 'notifyPrivate';
export const KEY_NOTIFY_GROUP: string = 'notifyGroup';
export const KEY_NOTIFY_CHANNEL: string = 'notifyChannel';

// 自定义 Web Push 中转通道。默认关闭，且必须先接受风险说明才能打开 ——
// 这条链路会把消息预览明文交给用户自建的服务器，不能默默生效。
export const KEY_WEBPUSH_ENABLED: string = 'webPushEnabled';
export const KEY_WEBPUSH_ACCEPTED: string = 'webPushAccepted';
export const KEY_WEBPUSH_ENDPOINT: string = 'webPushEndpoint';
export const KEY_WEBPUSH_P256DH: string = 'webPushP256dh';
export const KEY_WEBPUSH_AUTH: string = 'webPushAuth';
// 页面顶部模式记忆：'custom'（手工三字段）或 'meow'（用户名代填）。
export const KEY_WEBPUSH_MODE: string = 'webPushMode';
export const WEBPUSH_MODE_CUSTOM: string = 'custom';
export const WEBPUSH_MODE_MEOW: string = 'meow';
// MeoW 模式：中转服务器不认识 Telegram userId —— 主键是客户端自己生成的随机
// subKey（见 MeowPushRegistration.getOrCreateMeowSubKey，用
// CryptoArchitectureKit 的安全随机生成，首次用到时才生成并落盘）。secret 在
// 验证码确认成功那一步返回一次，之后改昵称/注销都要带上它才能生效，不带就
// 只能读。昵称一并存下来，方便回填输入框。
export const KEY_MEOW_SUBKEY: string = 'meowSubKey';
export const KEY_MEOW_SECRET: string = 'meowSecret';
export const KEY_MEOW_NICKNAME: string = 'meowNickname';

// 翻译。目标语言 '' 表示跟随系统语言；整聊天翻译是总开关，关闭时会话里
// 不出现整聊天翻译入口（单条翻译不受它控制）。
export const KEY_TRANSLATE_TARGET: string = 'translateTargetLang';
export const KEY_TRANSLATE_CHATS: string = 'translateEntireChats';
// 整聊天翻译打开后是全局生效的，这里存的是**例外**：被用户明确关掉翻译的
// 会话 id，逗号分隔。做成排除名单而不是白名单，是因为白名单意味着每进一个
// 新群都要手动点一次。纯本地设置，不占服务端的 is_translatable 字段。
export const KEY_TRANSLATE_OPT_OUT: string = 'translateOptOutChats';

// 账号默认聊天背景的快照，按深/浅色各存一份。仅为消除冷启动后第一次进入
// 聊天的白屏：进程内快照（ChatBackgroundStore）在同一次启动内够用，但跨启动
// 失效——那一次没有种子可用，背景要等 TDLib 往返（实测 +266ms），而转场动画
// 只有约 300ms，整个滑入过程就是兜底纯色。
export const KEY_CHAT_BG_SNAP_DARK: string = 'chatBgSnapshotDark';
export const KEY_CHAT_BG_SNAP_LIGHT: string = 'chatBgSnapshotLight';

const DATA_STRING_KEYS: string[] = [
  KEY_CHAT_BG_SNAP_DARK,
  KEY_CHAT_BG_SNAP_LIGHT,
  KEY_WEBPUSH_ENDPOINT,
  KEY_WEBPUSH_P256DH,
  KEY_WEBPUSH_AUTH,
  KEY_WEBPUSH_MODE,
  KEY_MEOW_SUBKEY,
  KEY_MEOW_SECRET,
  KEY_MEOW_NICKNAME,
  KEY_TRANSLATE_TARGET,
  KEY_TRANSLATE_OPT_OUT
];

// 后台播放：各媒体类别切后台是否继续播放（audioPlayback 长时任务）。
export const KEY_BG_PLAY_MUSIC: string = 'bgPlayMusic';
export const KEY_BG_PLAY_VOICE: string = 'bgPlayVoice';
export const KEY_BG_PLAY_VIDEO: string = 'bgPlayVideo';
export const KEY_BG_PLAY_LIVE: string = 'bgPlayLive';

const DATA_BOOLEAN_TRUE_DEFAULTS: string[] = [
  KEY_NOTIFY_PRIVATE,
  KEY_NOTIFY_GROUP,
  KEY_NOTIFY_CHANNEL,
  // 音乐/语音/直播默认续播（符合平台惯例）；视频默认不续播。
  KEY_BG_PLAY_MUSIC,
  KEY_BG_PLAY_VOICE,
  KEY_BG_PLAY_LIVE
];

const DATA_BOOLEAN_FALSE_DEFAULTS: string[] = [
  KEY_WEBPUSH_ENABLED,
  KEY_WEBPUSH_ACCEPTED,
  KEY_BG_PLAY_VIDEO,
  KEY_AUTOSAVE_PRIVATE,
  KEY_AUTOSAVE_GROUP,
  KEY_AUTOSAVE_CHANNEL,
  KEY_TRANSLATE_CHATS
];

function applyPowerState(percent: number): void {
  const safePercent = Math.max(0, Math.min(100, Math.round(percent)));
  const threshold = AppStorage.get<number>(KEY_POWER_THRESHOLD) ?? POWER_THRESHOLD_DEFAULT;
  const active = threshold === 101 || (threshold > 0 && safePercent <= threshold);
  AppStorage.setOrCreate(KEY_BATTERY_PERCENT, safePercent);
  AppStorage.setOrCreate(KEY_POWER_ACTIVE, active);
}

// Read the authoritative SOC instead of trusting event payload field names,
// which differ between OpenHarmony releases.
export function refreshPowerSavingState(): void {
  try {
    applyPowerState(batteryInfo.batterySOC);
  } catch (e) {
    console.error(`AppSettings.refreshPowerSavingState failed: ${e}`);
  }
}

function beginBatteryMonitoring(): void {
  if (batterySubscriber !== null) {
    return;
  }
  const info: commonEventManager.CommonEventSubscribeInfo = {
    events: [
      commonEventManager.Support.COMMON_EVENT_BATTERY_CHANGED,
      commonEventManager.Support.COMMON_EVENT_POWER_CONNECTED,
      commonEventManager.Support.COMMON_EVENT_POWER_DISCONNECTED
    ]
  };
  commonEventManager.createSubscriber(info).then(
    (subscriber: commonEventManager.CommonEventSubscriber): void => {
      batterySubscriber = subscriber;
      commonEventManager.subscribe(subscriber, (error, _data): void => {
        // HarmonyOS returns null (rather than undefined) for a successful
        // AsyncCallback error argument on some device releases.
        if (error !== undefined && error !== null && error.code !== 0) {
          console.error(`AppSettings battery event failed: ${error.message}`);
          return;
        }
        refreshPowerSavingState();
      });
    }
  ).catch((e: Object): void => {
    console.error(`AppSettings battery subscribe failed: ${JSON.stringify(e)}`);
  });
}

function colorModeOf(nightMode: string): ConfigurationConstant.ColorMode {
  if (nightMode === NIGHT_DARK) {
    return ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }
  if (nightMode === NIGHT_LIGHT) {
    return ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  }
  return ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET; // follow the system
}

// Push the stored night mode to the app — NOT_SET means "follow the system".
export function applyNightMode(nightMode: string): void {
  if (appContext === null) {
    return;
  }
  try {
    (appContext as common.Context).getApplicationContext().setColorMode(colorModeOf(nightMode));
  } catch (e) {
    console.error(`AppSettings.applyNightMode failed: ${e}`);
  }
}

// Load everything into AppStorage. Call once at startup, before the first page
// renders, so components never flash the default value.
export async function initSettings(context: common.Context): Promise<void> {
  appContext = context;
  try {
    store = await preferences.getPreferences(context, STORE_NAME);
    const s = store as preferences.Preferences;
    AppStorage.setOrCreate(KEY_TEXT_SIZE, await s.get(KEY_TEXT_SIZE, TEXT_SIZE_DEFAULT) as number);
    AppStorage.setOrCreate(KEY_BUBBLE_RADIUS, await s.get(KEY_BUBBLE_RADIUS, RADIUS_DEFAULT) as number);
    AppStorage.setOrCreate(KEY_THREE_LINES, await s.get(KEY_THREE_LINES, false) as boolean);
    AppStorage.setOrCreate(KEY_REDUCE_ANIM, await s.get(KEY_REDUCE_ANIM, false) as boolean);
    AppStorage.setOrCreate(KEY_SEND_BY_ENTER, await s.get(KEY_SEND_BY_ENTER, false) as boolean);
    AppStorage.setOrCreate(KEY_APP_LANGUAGE, await s.get(KEY_APP_LANGUAGE, 'default') as string);
    // 默认老交互：升级上来的人不该被换掉肌肉记忆，新方案由设置里主动开。
    AppStorage.setOrCreate(KEY_MSG_GESTURE, await s.get(KEY_MSG_GESTURE, GESTURE_CLASSIC) as string);
    AppStorage.setOrCreate(KEY_CHAT_DIM, await s.get(KEY_CHAT_DIM, 0) as number);
    AppStorage.setOrCreate(
      KEY_POWER_THRESHOLD,
      await s.get(KEY_POWER_THRESHOLD, POWER_THRESHOLD_DEFAULT) as number
    );
    for (const key of POWER_BOOLEAN_DEFAULTS) {
      AppStorage.setOrCreate(key, await s.get(key, true) as boolean);
    }
    for (const key of POWER_BOOLEAN_TRUE_EFFECT_DEFAULTS) {
      AppStorage.setOrCreate(key, await s.get(key, true) as boolean);
    }
    for (const key of POWER_BOOLEAN_FALSE_DEFAULTS) {
      AppStorage.setOrCreate(key, await s.get(key, false) as boolean);
    }
    for (const key of DATA_BOOLEAN_TRUE_DEFAULTS) {
      AppStorage.setOrCreate(key, await s.get(key, true) as boolean);
    }
    for (const key of DATA_BOOLEAN_FALSE_DEFAULTS) {
      AppStorage.setOrCreate(key, await s.get(key, false) as boolean);
    }
    AppStorage.setOrCreate(KEY_CACHE_LIMIT, await s.get(KEY_CACHE_LIMIT, CACHE_LIMIT_DEFAULT) as number);
    AppStorage.setOrCreate(KEY_BG_BLUR, await s.get(KEY_BG_BLUR, BG_BLUR_DEFAULT) as number);
    AppStorage.setOrCreate(KEY_AUTOPLAY_MUTED, await s.get(KEY_AUTOPLAY_MUTED, true) as boolean);
    for (const key of DATA_STRING_KEYS) {
      AppStorage.setOrCreate(key, await s.get(key, '') as string);
    }
    AppStorage.setOrCreate(KEY_CURRENT_NETWORK_TYPE, 'other');
    AppStorage.setOrCreate(KEY_POWER_ACTIVE, false);
    AppStorage.setOrCreate(KEY_BATTERY_PERCENT, 100);
    const night = await s.get(KEY_NIGHT_MODE, NIGHT_SYSTEM) as string;
    AppStorage.setOrCreate(KEY_NIGHT_MODE, night);
    applyNightMode(night);
    refreshPowerSavingState();
    beginBatteryMonitoring();
  } catch (e) {
    console.error(`AppSettings.initSettings failed: ${e}`);
    // Defaults still populate AppStorage so the UI works without persistence.
    AppStorage.setOrCreate(KEY_TEXT_SIZE, TEXT_SIZE_DEFAULT);
    AppStorage.setOrCreate(KEY_BUBBLE_RADIUS, RADIUS_DEFAULT);
    AppStorage.setOrCreate(KEY_THREE_LINES, false);
    AppStorage.setOrCreate(KEY_NIGHT_MODE, NIGHT_SYSTEM);
    AppStorage.setOrCreate(KEY_REDUCE_ANIM, false);
    AppStorage.setOrCreate(KEY_SEND_BY_ENTER, false);
    AppStorage.setOrCreate(KEY_POWER_THRESHOLD, POWER_THRESHOLD_DEFAULT);
    for (const key of POWER_BOOLEAN_DEFAULTS) {
      AppStorage.setOrCreate(key, true);
    }
    for (const key of POWER_BOOLEAN_TRUE_EFFECT_DEFAULTS) {
      AppStorage.setOrCreate(key, true);
    }
    for (const key of POWER_BOOLEAN_FALSE_DEFAULTS) {
      AppStorage.setOrCreate(key, false);
    }
    for (const key of DATA_BOOLEAN_TRUE_DEFAULTS) {
      AppStorage.setOrCreate(key, true);
    }
    for (const key of DATA_BOOLEAN_FALSE_DEFAULTS) {
      AppStorage.setOrCreate(key, false);
    }
    for (const key of DATA_STRING_KEYS) {
      AppStorage.setOrCreate(key, '');
    }
    AppStorage.setOrCreate(KEY_CURRENT_NETWORK_TYPE, 'other');
    AppStorage.setOrCreate(KEY_POWER_ACTIVE, false);
    AppStorage.setOrCreate(KEY_BATTERY_PERCENT, 100);
    refreshPowerSavingState();
    beginBatteryMonitoring();
  }
}

// Write-through: AppStorage first (instant UI), Preferences after (durable).
function persist(key: string, value: preferences.ValueType): void {
  if (store === null) {
    return;
  }
  const s = store as preferences.Preferences;
  s.put(key, value).then(() => s.flush()).catch((e: Object) => {
    console.error(`AppSettings.persist(${key}) failed: ${JSON.stringify(e)}`);
  });
}

export function setNumber(key: string, value: number): void {
  AppStorage.setOrCreate(key, value);
  persist(key, value);
  if (key === KEY_POWER_THRESHOLD) {
    refreshPowerSavingState();
  }
}

export function setBoolean(key: string, value: boolean): void {
  AppStorage.setOrCreate(key, value);
  persist(key, value);
}

export function setString(key: string, value: string): void {
  AppStorage.setOrCreate(key, value);
  persist(key, value);
}

function boolValue(key: string, fallback: boolean): boolean {
  return AppStorage.get<boolean>(key) ?? fallback;
}

// --- 整聊天翻译的会话例外 -----------------------------------------------
//
// 名单存成逗号分隔的字符串而不是数组：preferences 只收基本类型，而这个名单
// 通常是空的或只有几项，解析成本可以忽略。

function optOutList(): string[] {
  const raw = AppStorage.get<string>(KEY_TRANSLATE_OPT_OUT) ?? '';
  return raw === '' ? [] : raw.split(',');
}

export function translateOptedOut(chatId: number): boolean {
  return optOutList().indexOf(`${chatId}`) >= 0;
}

export function setTranslateOptedOut(chatId: number, optedOut: boolean): void {
  const id = `${chatId}`;
  const list = optOutList();
  const at = list.indexOf(id);
  if (optedOut && at < 0) {
    list.push(id);
  } else if (!optedOut && at >= 0) {
    list.splice(at, 1);
  } else {
    return; // 已经是目标状态
  }
  setString(KEY_TRANSLATE_OPT_OUT, list.join(','));
}

export function autosaveEnabled(scope: string): boolean {
  if (scope === 'channel') { return boolValue(KEY_AUTOSAVE_CHANNEL, false); }
  if (scope === 'group') { return boolValue(KEY_AUTOSAVE_GROUP, false); }
  return boolValue(KEY_AUTOSAVE_PRIVATE, false);
}

export function setNightMode(value: string): void {
  AppStorage.setOrCreate(KEY_NIGHT_MODE, value);
  persist(KEY_NIGHT_MODE, value);
  applyNightMode(value);
}

// Read helpers for non-component code (components use @StorageProp instead).
export function textSize(): number {
  return AppStorage.get<number>(KEY_TEXT_SIZE) ?? TEXT_SIZE_DEFAULT;
}

export function reduceAnimations(): boolean {
  return AppStorage.get<boolean>(KEY_REDUCE_ANIM) ?? false;
}

export function powerSavingActive(): boolean {
  return AppStorage.get<boolean>(KEY_POWER_ACTIVE) ?? false;
}

export function powerFeatureEnabled(key: string): boolean {
  return (AppStorage.get<boolean>(key) ?? true) && !powerSavingActive();
}

export function powerGroupFeatureEnabled(groupKey: string, key: string): boolean {
  return powerFeatureEnabled(groupKey) && powerFeatureEnabled(key);
}

export function powerAnimationDuration(key: string, duration: number): number {
  return powerFeatureEnabled(key) ? duration : 0;
}

export function powerGroupAnimationDuration(groupKey: string, key: string, duration: number): number {
  return powerGroupFeatureEnabled(groupKey, key) ? duration : 0;
}
