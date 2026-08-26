import { preferences } from '@kit.ArkData';
import { setCrashUploadOptOut } from '../services/crashRecordStore';
import { LIGHT_DEFAULT, THICKNESS_DEFAULT } from '../util/materialTuning';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { batteryInfo, commonEventManager } from '@kit.BasicServicesKit';
import { CACHE_LIMIT_DEFAULT } from './CacheLimit';
import { GESTURE_CLASSIC } from '../util/messageGestures';
import { logE } from '../util/log';
import { KEY_PROXY_MIRROR, KEY_PROXY_SYNC_OFF } from '../util/proxyMirror';
// ⚠️ 临时（P6 标定）：cachedCount 档位调试项，标定结束后删除，清单见
// util/debugListPerf.ets 文件末尾。
import {
  KEY_DEBUG_LIST_CACHED, LIST_CACHED_COUNT_DEFAULT, normalizeListCachedCount
} from '../util/debugListPerf';
import {
  APPEARANCE_HEX_KEYS, KEY_ACCENT_CUSTOM_ON, KEY_BUBBLE_MATERIAL_ON, KEY_MATERIAL_LIGHT_DARK,
  KEY_MATERIAL_THICKNESS_DARK, KEY_STATUS_FOLLOW_TITLE, recomputeAppearance
} from '../util/appearance';

// User settings that outlive the process. Each one is mirrored into AppStorage
// so any component can bind it with @StorageProp and re-render on change, while
// Preferences keeps the value across restarts.
//
// Only settings the app actually honours live here — a switch that changes
// nothing is worse than no switch at all.

const STORE_NAME: string = 'app_settings';

// AppStorage keys (also the Preferences keys — one name per setting).
export const KEY_TEXT_SIZE: string = 'msgTextSize';        // message font size, vp
// 平板分栏下用户拖出来的左栏宽度，vp。0 = 没拖过，用 HDS 的静息值。见 util/splitNavWidth。
export const KEY_SPLIT_NAV_WIDTH: string = 'splitNavWidthVp';
export const KEY_BUBBLE_RADIUS: string = 'bubbleRadius';   // message corner radius, vp
export const KEY_THREE_LINES: string = 'chatListThreeLines'; // chat list row shows 2 or 3 lines
export const KEY_NIGHT_MODE: string = 'nightMode';         // 'system' | 'dark' | 'light'
export const KEY_REDUCE_ANIM: string = 'reduceAnimations'; // stop autoplaying animated stickers
export const KEY_SEND_BY_ENTER: string = 'sendByEnter';    // Enter sends instead of newline
// 网页链接用内置浏览器还是交给系统。默认内置：留在应用里不丢上下文。
export const KEY_IN_APP_BROWSER: string = 'inAppBrowser';
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
// 动图头像（资料页/顶栏那种循环小片段）。单独一档而不是挂在"自动播放视频"
// 上：那个开关的用户预期是"聊天里的视频别自动播"，动机是省流量，而动图头像
// 早就下载完了，不播一点流量都省不了——只是恰好都用播放器解码而已。
export const KEY_POWER_ANIMATED_AVATAR: string = 'powerAnimatedAvatar';
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

// 浮层材质厚度与光感等级——沉浸光感的两个用户档位。取值语义、四档单调性
// 与降级路径的映射都在 util/materialTuning.ets，那边有单测钉着。
//
// 厚度存的是**相对偏移**（-2..2，0 = 出厂手感），不是绝对档位：每个面的厚度
// 是分别调过的，绝对档位会把弹窗和顶栏压成同一厚度。
export const KEY_MATERIAL_THICKNESS: string = 'materialThickness';
// 底栏是否显示「联系人」页签（交互设置）。关掉只是隐藏页签，联系人页本身还在。
export const KEY_SHOW_CONTACTS_TAB: string = 'showContactsTab';
// 会话行的左右滑操作（已读/静音/归档）。默认关：开着会吃掉横向手势，左右滑就
// 不能切文件夹了——两种用法只能二选一，默认保留切文件夹。
export const KEY_ROW_SWIPE_ACTIONS: string = 'rowSwipeActions';
// 光感等级只在 API 26 的材质路径上有意义，低于 26 时设置页不显示这一行。
export const KEY_MATERIAL_LIGHT: string = 'materialLight';
// 聊天背景模糊半径（vp）。用户可调，见 chatBackgroundRaster.ets 的
// backgroundBlurRadius —— pattern 与"需要模糊"的照片壁纸都用这一个值。
export const KEY_BG_BLUR: string = 'bgBlur';
export const BG_BLUR_DEFAULT: number = 8;
export const BG_BLUR_MIN: number = 0;
export const BG_BLUR_MAX: number = 20;

// 图案壁纸的线条浓度，作为 TDLib 给的 intensity 的**乘数**（0.2~1，默认 1 =
// 原样）。服务端那个值是壁纸作者定的，不少图案在小屏上线条压得很重；这里
// 让用户自己压一档，而不是去改壁纸本身。
// 深浅两套各存一份：背景本身就是分主题选的，两张图案的线条轻重不一样，
// 共用一个浓度等于在深色下调完浅色也跟着变。
export const KEY_BG_PATTERN: string = 'bgPatternStrength';
export const KEY_BG_PATTERN_DARK: string = 'bgPatternStrengthDark';
export const BG_PATTERN_DEFAULT: number = 1;
export const BG_PATTERN_MIN: number = 0.2;

export function patternStrengthKey(forDark: boolean): string {
  return forDark ? KEY_BG_PATTERN_DARK : KEY_BG_PATTERN;
}
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
  KEY_POWER_ANIMATED_AVATAR,
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
// 上一次注册到中转的华为设备 token。存它是为了判断"要不要重新注册"——每次启动
// 都往中转发一次注册是白白的往返，还会把中转的注册限流桶打满（每 IP 有窗口配额，
// 同一个 Wi-Fi 下多台设备会互相挤掉）。见 HmsRelayRegistration.needsHmsRegistration。
export const KEY_HMS_PUSH_TOKEN: string = 'hmsPushToken';
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
// 总开关**关着**时，用户在某个会话里单独打开翻译——这一份要存在本地。
//
// 原来只写服务端的 toggleChatIsTranslatable，指望它记住。可那是 Telegram 的
// 自动翻译能力（会员相关），非会员账号服务端未必落盘，而且失败也不一定报错，
// 于是用户看到"这次开了，下次进来又是关的"。本地自己记一份，谁都不依赖。
export const KEY_TRANSLATE_OPT_IN: string = 'translateOptInChats';

// 账号默认聊天背景的快照，按深/浅色各存一份。仅为消除冷启动后第一次进入
// 聊天的白屏：进程内快照（ChatBackgroundStore）在同一次启动内够用，但跨启动
// 失效——那一次没有种子可用，背景要等 TDLib 往返（实测 +266ms），而转场动画
// 只有约 300ms，整个滑入过程就是兜底纯色。
export const KEY_CHAT_BG_SNAP_DARK: string = 'chatBgSnapshotDark';
export const KEY_CHAT_BG_SNAP_LIGHT: string = 'chatBgSnapshotLight';

const DATA_STRING_KEYS: string[] = [
  KEY_PROXY_MIRROR,
  KEY_PROXY_SYNC_OFF,
  KEY_CHAT_BG_SNAP_DARK,
  KEY_CHAT_BG_SNAP_LIGHT,
  KEY_WEBPUSH_ENDPOINT,
  KEY_WEBPUSH_P256DH,
  KEY_WEBPUSH_AUTH,
  KEY_WEBPUSH_MODE,
  KEY_HMS_PUSH_TOKEN,
  KEY_MEOW_SUBKEY,
  KEY_MEOW_SECRET,
  KEY_MEOW_NICKNAME,
  KEY_TRANSLATE_TARGET,
  KEY_TRANSLATE_OPT_OUT,
  KEY_TRANSLATE_OPT_IN
];

// 后台播放：各媒体类别切后台是否继续播放（audioPlayback 长时任务）。
export const KEY_BG_PLAY_MUSIC: string = 'bgPlayMusic';
export const KEY_BG_PLAY_VOICE: string = 'bgPlayVoice';
export const KEY_BG_PLAY_VIDEO: string = 'bgPlayVideo';
export const KEY_BG_PLAY_LIVE: string = 'bgPlayLive';

// 崩溃上报。默认**开**——这一项存在的全部意义就是"应用打不开时也能知道为什么"，
// 默认关等于没有。载荷里没有任何用户内容（见 services/crashReport），用户可以
// 在设置里关掉。
export const KEY_CRASH_UPLOAD: string = 'crashUpload';

const DATA_BOOLEAN_TRUE_DEFAULTS: string[] = [
  KEY_CRASH_UPLOAD,
  KEY_SHOW_CONTACTS_TAB,
  KEY_NOTIFY_PRIVATE,
  KEY_NOTIFY_GROUP,
  KEY_NOTIFY_CHANNEL,
  // 音乐/语音/直播默认续播（符合平台惯例）；视频默认不续播。
  KEY_BG_PLAY_MUSIC,
  KEY_BG_PLAY_VOICE,
  KEY_BG_PLAY_LIVE
];

const DATA_BOOLEAN_FALSE_DEFAULTS: string[] = [
  KEY_STATUS_FOLLOW_TITLE,
  KEY_ROW_SWIPE_ACTIONS,
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
    logE(`AppSettings.refreshPowerSavingState failed: ${e}`);
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
          logE(`AppSettings battery event failed: ${error.message}`);
          return;
        }
        refreshPowerSavingState();
      });
    }
  ).catch((e: Object): void => {
    logE(`AppSettings battery subscribe failed: ${JSON.stringify(e)}`);
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
    logE(`AppSettings.applyNightMode failed: ${e}`);
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
    AppStorage.setOrCreate(KEY_SPLIT_NAV_WIDTH, await s.get(KEY_SPLIT_NAV_WIDTH, 0) as number);
    AppStorage.setOrCreate(KEY_BUBBLE_RADIUS, await s.get(KEY_BUBBLE_RADIUS, RADIUS_DEFAULT) as number);
    AppStorage.setOrCreate(KEY_THREE_LINES, await s.get(KEY_THREE_LINES, false) as boolean);
    AppStorage.setOrCreate(KEY_REDUCE_ANIM, await s.get(KEY_REDUCE_ANIM, false) as boolean);
    AppStorage.setOrCreate(KEY_SEND_BY_ENTER, await s.get(KEY_SEND_BY_ENTER, false) as boolean);
    AppStorage.setOrCreate(KEY_IN_APP_BROWSER, await s.get(KEY_IN_APP_BROWSER, true) as boolean);
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
    // ⚠️ 临时（P6 标定）：走 normalize 而不是直接信落盘值——档位表将来收窄时，
    // 旧值会变成野值，而 cachedCount 收到野值不报错，只是行为不可解释。
    AppStorage.setOrCreate(KEY_DEBUG_LIST_CACHED,
      normalizeListCachedCount(await s.get(KEY_DEBUG_LIST_CACHED, LIST_CACHED_COUNT_DEFAULT) as number));
    AppStorage.setOrCreate(KEY_MATERIAL_THICKNESS,
      await s.get(KEY_MATERIAL_THICKNESS, THICKNESS_DEFAULT) as number);
    AppStorage.setOrCreate(KEY_MATERIAL_LIGHT,
      await s.get(KEY_MATERIAL_LIGHT, LIGHT_DEFAULT) as string);
    AppStorage.setOrCreate(KEY_MATERIAL_THICKNESS_DARK,
      await s.get(KEY_MATERIAL_THICKNESS_DARK, THICKNESS_DEFAULT) as number);
    AppStorage.setOrCreate(KEY_MATERIAL_LIGHT_DARK,
      await s.get(KEY_MATERIAL_LIGHT_DARK, LIGHT_DEFAULT) as string);
    AppStorage.setOrCreate(KEY_ACCENT_CUSTOM_ON, await s.get(KEY_ACCENT_CUSTOM_ON, false) as boolean);
    AppStorage.setOrCreate(KEY_BUBBLE_MATERIAL_ON, await s.get(KEY_BUBBLE_MATERIAL_ON, false) as boolean);
    for (const key of APPEARANCE_HEX_KEYS) {
      AppStorage.setOrCreate(key, await s.get(key, '') as string);
    }
    AppStorage.setOrCreate(KEY_BG_BLUR, await s.get(KEY_BG_BLUR, BG_BLUR_DEFAULT) as number);
    AppStorage.setOrCreate(KEY_BG_PATTERN, await s.get(KEY_BG_PATTERN, BG_PATTERN_DEFAULT) as number);
    AppStorage.setOrCreate(KEY_BG_PATTERN_DARK,
      await s.get(KEY_BG_PATTERN_DARK, BG_PATTERN_DEFAULT) as number);
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
    recomputeAppearance();
    refreshPowerSavingState();
    beginBatteryMonitoring();
  } catch (e) {
    logE(`AppSettings.initSettings failed: ${e}`);
    // Defaults still populate AppStorage so the UI works without persistence.
    AppStorage.setOrCreate(KEY_TEXT_SIZE, TEXT_SIZE_DEFAULT);
    AppStorage.setOrCreate(KEY_SPLIT_NAV_WIDTH, 0);
    AppStorage.setOrCreate(KEY_BUBBLE_RADIUS, RADIUS_DEFAULT);
    AppStorage.setOrCreate(KEY_THREE_LINES, false);
    AppStorage.setOrCreate(KEY_NIGHT_MODE, NIGHT_SYSTEM);
    AppStorage.setOrCreate(KEY_REDUCE_ANIM, false);
    AppStorage.setOrCreate(KEY_SEND_BY_ENTER, false);
    AppStorage.setOrCreate(KEY_IN_APP_BROWSER, true);
    AppStorage.setOrCreate(KEY_MATERIAL_THICKNESS, THICKNESS_DEFAULT);
    AppStorage.setOrCreate(KEY_MATERIAL_LIGHT, LIGHT_DEFAULT);
    AppStorage.setOrCreate(KEY_MATERIAL_THICKNESS_DARK, THICKNESS_DEFAULT);
    AppStorage.setOrCreate(KEY_MATERIAL_LIGHT_DARK, LIGHT_DEFAULT);
    AppStorage.setOrCreate(KEY_ACCENT_CUSTOM_ON, false);
    AppStorage.setOrCreate(KEY_BUBBLE_MATERIAL_ON, false);
    for (const key of APPEARANCE_HEX_KEYS) {
      AppStorage.setOrCreate(key, '');
    }
    AppStorage.setOrCreate(KEY_DEBUG_LIST_CACHED, LIST_CACHED_COUNT_DEFAULT); // ⚠️ 临时（P6 标定）
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
    logE(`AppSettings.persist(${key}) failed: ${JSON.stringify(e)}`);
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
  if (key === KEY_CRASH_UPLOAD) {
    // 崩溃上报的开关额外落一个标记文件。扩展进程读不到 AppStorage、也不能
    // import 这个模块（会把 ArkUI 依赖拖进那个没有 ArkUI 的进程），标记文件
    // 是它唯一能看见用户选择的方式。见 services/crashRecordStore。
    setCrashUploadOptOut(!value);
  }
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

function chatIdList(key: string): string[] {
  const raw = AppStorage.get<string>(key) ?? '';
  return raw === '' ? [] : raw.split(',');
}

function setChatIdInList(key: string, chatId: number, member: boolean): void {
  const id = `${chatId}`;
  const list = chatIdList(key);
  const at = list.indexOf(id);
  if (member && at < 0) {
    list.push(id);
  } else if (!member && at >= 0) {
    list.splice(at, 1);
  } else {
    return; // 已经是目标状态
  }
  setString(key, list.join(','));
}

export function translateOptedOut(chatId: number): boolean {
  return chatIdList(KEY_TRANSLATE_OPT_OUT).indexOf(`${chatId}`) >= 0;
}

export function setTranslateOptedOut(chatId: number, optedOut: boolean): void {
  setChatIdInList(KEY_TRANSLATE_OPT_OUT, chatId, optedOut);
}

export function translateOptedIn(chatId: number): boolean {
  return chatIdList(KEY_TRANSLATE_OPT_IN).indexOf(`${chatId}`) >= 0;
}

export function setTranslateOptedIn(chatId: number, optedIn: boolean): void {
  setChatIdInList(KEY_TRANSLATE_OPT_IN, chatId, optedIn);
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
