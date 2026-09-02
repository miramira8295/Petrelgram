import { AbilityConstant, Configuration, UIAbility, Want } from '@kit.AbilityKit';
import { mirrorChatEnvKey } from '../util/chatEnvMirror';
import { notificationManager } from '@kit.NotificationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window, KeyboardAvoidMode } from '@kit.ArkUI';
import { KEY_APP_DARK, darkResourceMode } from '../util/theme';
import { recomputeAppearance } from '../util/appearance';
import { initTdKit, setTdOnlineState, setUiAbilityContext } from '../tdkit/Globals';
import { installStringsFromContext, invalidateStringCache } from '../util/strings';
import { refreshLocale } from '../util/intlFormat';
import { bumpLanguageEpoch } from '../util/appLanguage';
import { backgroundGraceTask } from '../services/BackgroundGraceTask';
import { startCrashWatch } from '../services/crashReport';
import { initDiagLog } from '../util/log';
import { initSettings, refreshPowerSavingState, KEY_CACHE_LIMIT } from '../store/AppSettings';
import { migrateLegacyAppWallpaperStates } from '../store/ChatBackgroundStore';
import { CACHE_LIMIT_DEFAULT, shouldTrimNow } from '../store/CacheLimit';
import { applyCacheLimit } from '../store/StorageApi';
import { beginNetworkMonitoring, refreshNetworkState } from '../services/NetworkStateService';
import { proxyAutoSwitchService } from '../services/ProxyAutoSwitchService';
import { updateChecker } from '../services/UpdateChecker';
import { liveLocation } from '../services/LiveLocationService';
import { setInlinePhotoTargetPx } from '../util/formatMsgContent';
import { trimPixelCache } from '../util/pixelCache';
import { logE, logW } from '../util/log';

// 和 MessageBubble 的 MEDIA_MAX_WIDTH 对齐；两处要一起改。
const BUBBLE_MEDIA_MAX_VP: number = 280;

const DOMAIN = 0x0000;
// windowSizeChange 带来的密度和启动时相差超过这个比例，就判定这次回调不可信。
// 折叠屏切换屏幕那类真实变化远小于它。
const DENSITY_TOLERANCE: number = 0.2;

export default class EntryAbility extends UIAbility {
  // 启动时算出的显示密度，作为后续 windowSizeChange 的校验基准。
  private uiDensity: number = 0;
  // 上一次见到的系统语言，用来判断配置变更里语言到底变没变。
  private lastLanguage: string = '';
  private windowStageRef: window.WindowStage | null = null;
  // loadContent 回调之前窗口还没有内容，setWindowBackgroundColor 必失败
  // （"This window state is abnormal"）——原来每次冷启动都在诊断日志里留一行。
  private contentLoaded: boolean = false;
  // 上一次跑缓存收缩的时间戳；配合 CACHE_TRIM_MIN_INTERVAL_MS 防止频繁切前台反复触发重操作。
  private lastCacheTrimAt: number = 0;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // Before anything that formats text: stores build chat previews during
    // startup, and without a source installed those would come out as raw keys.
    // 日志落盘目录尽早设好：在这之前 logI/logW/logE 只在内存里攒（模块加载时
    // 就已经在攒了），设好之后才开始轮转到文件。启动期恰好是最难查的一段，
    // 早一点设就多留住一点。
    initDiagLog(this.context.filesDir);
    // 崩溃观察者要在**业务逻辑之前**注册：应用没主动捕获时，崩溃事件是在下次
    // 启动才回调的，注册晚了那一次就漏了（官方《订阅崩溃事件》写明这一点）。
    startCrashWatch(this.context);
    // ApplicationContext rather than this.context — the lookup is not tied to
    // any Ability or window, and locale is application-level configuration.
    installStringsFromContext(this.context.getApplicationContext());
    // Loads persisted settings into AppStorage and applies the stored night
    // mode (which subsumes the old unconditional COLOR_MODE_NOT_SET).
    initSettings(this.context).then((): void => {
      migrateLegacyAppWallpaperStates();
      proxyAutoSwitchService.settingsChanged();
    }).catch((error: Error): void => {
      // initSettings 自己已经装好默认值；这里防住未来实现改成向外抛错时的未处理
      // Promise，启动不能因为一次设置迁移失败而中断。
      logE(`EntryAbility initSettings failed: ${error.message}`);
    });
    initTdKit(this.context);
    // 实时位置共享要跨会话、跨前后台存活，服务需要 Ability 上下文申请长时任务。
    liveLocation.init(this.context);
    // 版本号与上次的检查结果先读出来，红点在网络请求回来之前就是对的。
    updateChecker.init(this.context).catch((): void => {});
    setUiAbilityContext(this.context);
    beginNetworkMonitoring();
    // Cold start via a tg:// deep link — stash it; Index routes it once auth
    // reaches Ready (the UI/router aren't up yet here).
    this.stashDeepLink(want);
    AppStorage.setOrCreate('appIsForeground', false);
    AppStorage.setOrCreate('appForegroundEpoch', 0);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  // Warm start: the app is already running (foreground or background) when a
  // tg:// link arrives. Index's @Watch picks up the new value and routes it.
  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    this.stashDeepLink(want);
  }

  // Fires when the system language (or colour mode, font scale, …) changes
  // while the app is running. Resources re-resolve themselves; the Intl
  // formatters are cached in-process and do not, so they would keep rendering
  // dates in the language the user just left.
  onConfigurationUpdate(config: Configuration): void {
    refreshLocale();
    // Only on an actual language change. This fires for every configuration
    // change — dark mode, font scale, orientation — and the epoch is embedded
    // in list row keys, so bumping it renames every row in the app. Doing that
    // for a colour-mode change (or whatever the system reports when an app
    // returns to the foreground) left the lists rebuilding for no reason, and
    // renamed rows out from under LazyForEach.
    const language: string = config.language ?? '';
    if (language !== this.lastLanguage) {
      this.lastLanguage = language;
      invalidateStringCache();
      bumpLanguageEpoch();
    }
    // 深浅色切换时状态栏的图标要跟着反色，否则白图标留在浅色页面上会看不见。
    this.applyImmersiveStatusBar();
  }

  // 状态栏沉浸。
  //
  // setWindowLayoutFullScreen(true) 只让**布局**铺满，状态栏自己仍然画一层
  // 不透明底色——深色模式下是纯黑，压在应用的深蓝灰之上就是一条明显的分界，
  // 浅色模式下则是浅灰压在白色 chrome 上。底色要单独设成透明才真正沉浸。
  //
  // 内容色（时钟和图标）必须跟着深浅色走：深色模式下应用背景是暗的，图标要
  // 白的才看得见；浅色反之。系统不会替我们判断，因为它不知道页面底下画了什么。
  private applyWindowBackground(win: window.Window, dark: boolean): void {
    if (!this.contentLoaded) {
      return;
    }
    try {
      win.setWindowBackgroundColor(dark ? '#17212B' : '#EFEFF4');
    } catch (e) {
      logE(`setWindowBackgroundColor failed: ${(e as Error).message}`);
    }
  }

  private applyImmersiveStatusBar(): void {
    if (this.windowStageRef === null) {
      return;
    }
    const win = this.windowStageRef.getMainWindowSync();
    const dark: boolean = darkResourceMode(this.context);
    // 界面侧用 @StorageProp(KEY_APP_DARK) 订阅。这里是全应用唯一一处真正知道
    // 模式变了的地方（onConfigurationUpdate 也会走到这个函数）。
    AppStorage.setOrCreate(KEY_APP_DARK, dark);
    // 主色/气泡色是按模式分存的，模式一变就得重算当前那份。
    recomputeAppearance();
    // 窗口底色。状态栏透明之后，它下面露出来的就是这一层；悬浮的文件夹条
    // 背后也是它。从没设过，所以一直是系统默认的黑——深色模式下 app 是
    // #17212B 的深蓝灰，顶上压着一条纯黑，就是"状态栏不沉浸"的真相。
    //
    // 这两个值必须与 resources/{base,dark}/element/color.json 的 page_bg 一致。
    // 不用 getColorSync 从资源里取：那条路在本项目实测会在深色模式下仍然
    // 返回浅色值（theme.ets:31 的注释记着这个坑）。
    this.applyWindowBackground(win, dark);
    win.setWindowSystemBarProperties({
      statusBarColor: '#00000000',
      statusBarContentColor: dark ? '#FFFFFF' : '#000000',
      navigationBarColor: '#00000000',
      navigationBarContentColor: dark ? '#FFFFFF' : '#000000'
    }).catch((e: Error): void => {
      logE(`setWindowSystemBarProperties failed: ${e.message}`);
    });
  }

  // Publish the launch URI for the UI layer. Cleared to '' first so re-opening
  // the SAME link still registers as a change and re-triggers routing.
  private stashDeepLink(want: Want): void {
    this.stashNotifyTarget(want);
    const uri = want.uri ?? '';
    // 诊断：用户报浏览器点 t.me 链接进来提示"无法识别"，而日志里连一次解析
    // 尝试都没有。先看 want 到底带了什么——uri 为空的话这里就静默 return 了，
    // 浏览器可能把地址放在别的字段。
    if (uri === '') {
      return;
    }
    AppStorage.setOrCreate('pendingDeepLink', '');
    AppStorage.setOrCreate('pendingDeepLink', uri);
  }

  // 点击本地通知拉起时携带的目标会话。与 pendingDeepLink 相同的
  // 清零-再置位模式，保证重复点击同一会话的通知也触发路由。
  private stashNotifyTarget(want: Want): void {
    const chatId = want.parameters !== undefined
      ? (want.parameters['notifyChatId'] as number | undefined) ?? 0 : 0;
    if (chatId === 0) {
      return;
    }
    const messageId = want.parameters !== undefined
      ? (want.parameters['notifyMessageId'] as number | undefined) ?? 0 : 0;
    // 消息 id 先写：Index 监听的是 chatId，翻到它的那一刻两个值都得就位。
    AppStorage.setOrCreate('pendingNotifyMessageId', messageId);
    AppStorage.setOrCreate('pendingNotifyChatId', 0);
    AppStorage.setOrCreate('pendingNotifyChatId', chatId);
  }

  onDestroy(): void {
    setTdOnlineState(false);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');
    // 本地通知授权：先查是否已启用，未启用才弹授权框（重复调用/系统开关
    // 关闭时 requestEnableNotification 会报 Internal error，故先判断）。
    notificationManager.isNotificationEnabled().then((enabled: boolean): void => {
      if (enabled) {
        return;
      }
      notificationManager.requestEnableNotification(this.context).catch((e: Error): void => {
        logE(`requestEnableNotification failed: ${e.message}`);
      });
    }).catch((e: Error): void => {
      logE(`isNotificationEnabled failed: ${e.message}`);
    });

    try {
      this.windowStageRef = windowStage;
      const win = windowStage.getMainWindowSync();
      win.setWindowLayoutFullScreen(true);
      this.applyImmersiveStatusBar();
      const avoid = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      AppStorage.setOrCreate('topSafeHeight', px2vp(avoid.topRect.height));
      // Bottom inset (gesture navigation bar) — pages pad their bottom bars by this.
      const navAvoid = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      AppStorage.setOrCreate('bottomSafeHeight', px2vp(navAvoid.bottomRect.height));
      const cutoutAvoid = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_CUTOUT);
      AppStorage.setOrCreate('cutoutTopSafeHeight', px2vp(cutoutAvoid.topRect.height));
      AppStorage.setOrCreate('cutoutLeftSafeWidth', px2vp(cutoutAvoid.leftRect.width));
      AppStorage.setOrCreate('cutoutRightSafeWidth', px2vp(cutoutAvoid.rightRect.width));
      AppStorage.setOrCreate('screenWidthVp', px2vp(win.getWindowProperties().windowRect.width));
      AppStorage.setOrCreate('screenHeightVp', px2vp(win.getWindowProperties().windowRect.height));
      mirrorChatEnvKey('screenWidthVp', px2vp(win.getWindowProperties().windowRect.width));
      mirrorChatEnvKey('screenHeightVp', px2vp(win.getWindowProperties().windowRect.height));
      // 气泡里的媒体最宽 MEDIA_MAX_WIDTH(280vp)，按它的物理像素挑图片尺寸，
      // 别再固定取第二小的那档。用窗口宽算密度，比猜一个屏宽比例准——多挑一档
      // 就是多几倍的解码像素，滑动时那笔账要在主线程上还。
      const rectPx: number = win.getWindowProperties().windowRect.width;
      const density: number = rectPx / Math.max(1, px2vp(rectPx));
      // 记住启动时的密度，windowSizeChange 里拿它做换算和校验。见下面的注释。
      this.uiDensity = density;
      // 启动时把窗口度量打一行出来。**分栏与否完全由 vp 宽决定**（600vp 断点），
      // 而 vp 宽 = 物理像素 / 密度——光看分辨率会得出错误结论。2026-08-22 手机
      // 模拟器上就撞过：1320px 屏按 3x 密度算是 440vp（该单栏），按 2x 算是 660vp
      // （该分栏），两者行为天差地别，而当时没有任何一处日志能把这个数说清楚。
      // hilog 的 %{public}f 在本机不生效（打出来是字面的 "}f"），先在 JS 里格式化
      // 成字符串再交给它。
      const heightPx: number = win.getWindowProperties().windowRect.height;
      const metrics: string =
        `${rectPx}px x ${heightPx}px, density ${density} -> ` +
        `${px2vp(rectPx)}vp x ${px2vp(heightPx)}vp`;
      hilog.info(DOMAIN, 'testTag', '[Layout] window %{public}s', metrics);
      setInlinePhotoTargetPx(Math.min(rectPx, BUBBLE_MEDIA_MAX_VP * density));
      win.on('avoidAreaChange', (data) => {
        if (data.type === window.AvoidAreaType.TYPE_SYSTEM) {
          AppStorage.setOrCreate('topSafeHeight', px2vp(data.area.topRect.height));
        } else if (data.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
          AppStorage.setOrCreate('bottomSafeHeight', px2vp(data.area.bottomRect.height));
        } else if (data.type === window.AvoidAreaType.TYPE_CUTOUT) {
          AppStorage.setOrCreate('cutoutTopSafeHeight', px2vp(data.area.topRect.height));
          AppStorage.setOrCreate('cutoutLeftSafeWidth', px2vp(data.area.leftRect.width));
          AppStorage.setOrCreate('cutoutRightSafeWidth', px2vp(data.area.rightRect.width));
        }
      });
      // Keyboard height: when the IME is up the window is already resized
      // above it, so pages must drop their gesture-bar bottom padding.
      win.on('keyboardHeightChange', (h: number) => {
        AppStorage.setOrCreate('keyboardHeightVp', px2vp(h));
        mirrorChatEnvKey('keyboardHeightVp', px2vp(h));
      });
      // 悬浮小窗 ↔ 全屏来回时系统会重置状态栏的内容色，而上面那套只在启动和
      // 配置变更时设过一次——从小窗恢复后图标就不是白的了（issue #136）。
      // 窗口模式一变就再设一遍。
      win.on('windowStatusChange', (status: window.WindowStatusType): void => {
        logW(`windowStatus ${status}`);
        this.applyImmersiveStatusBar();
      });
      win.on('windowSizeChange', (size) => {
        // px2vp 依赖当前显示密度。灭屏/亮屏那一瞬间这个回调会带着尚未恢复的
        // 密度过来，密度当成 1 时 px2vp 直接把物理像素原样返回——屏宽从 385
        // 跳到 1316，气泡的 maxWidth（屏宽 × 0.78）变成 1026 远超可用宽度，
        // 整条消息就摊平到整行。等下一次正常回调到达才自己恢复。
        //
        // 所以这里不直接信 px2vp：拿它反推一次密度，和启动时那个对不上就
        // 判定这次回调不可信，跳过。密度真正变化只发生在折叠屏切换屏幕那
        // 类场景，那时误差远小于这个阈值，仍然会被接受并刷新基准。
        const candidate: number = px2vp(size.width);
        const derived: number = size.width / Math.max(1, candidate);
        const base: number = this.uiDensity > 0 ? this.uiDensity : derived;
        if (Math.abs(derived - base) / base > DENSITY_TOLERANCE) {
          hilog.warn(DOMAIN, 'testTag',
            'windowSizeChange ignored: density %{public}f vs %{public}f (px=%{public}d)',
            derived, base, size.width);
          return;
        }
        this.uiDensity = derived;
        hilog.info(DOMAIN, 'testTag',
          'windowSizeChange accepted: px=%{public}d vp=%{public}f density=%{public}f',
          size.width, candidate, derived);
        AppStorage.setOrCreate('screenWidthVp', candidate);
        AppStorage.setOrCreate('screenHeightVp', px2vp(size.height));
        mirrorChatEnvKey('screenWidthVp', candidate);
        mirrorChatEnvKey('screenHeightVp', px2vp(size.height));
      });
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set full-screen layout. Cause: %{public}s', JSON.stringify(err));
    }

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      // IME avoidance: RESIZE shrinks the page above the keyboard, so fixed
      // headers (chat title bar) stay put and only the scrolling content and
      // input bar move. The default OFFSET translates the WHOLE page up.
      try {
        windowStage.getMainWindowSync().getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
      } catch (e) {
        hilog.error(DOMAIN, 'testTag', 'setKeyboardAvoidMode failed: %{public}s', JSON.stringify(e));
      }
      // 窗口底色要等内容加载完才设得上，见 contentLoaded。
      this.contentLoaded = true;
      try {
        this.applyWindowBackground(windowStage.getMainWindowSync(), darkResourceMode(this.context));
      } catch (e) {
        logE(`applyWindowBackground after loadContent failed: ${(e as Error).message}`);
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    refreshPowerSavingState();
    refreshNetworkState(true);
    AppStorage.setOrCreate('appIsForeground', true);
    // 回前台：释放短时任务配额（下次切后台再申请）。
    backgroundGraceTask.end();
    AppStorage.setOrCreate('appForegroundEpoch', Date.now());
    setTdOnlineState(true);
    const limit: number = AppStorage.get<number>(KEY_CACHE_LIMIT) ?? CACHE_LIMIT_DEFAULT;
    const now = Date.now();
    if (shouldTrimNow(limit, this.lastCacheTrimAt, now)) {
      this.lastCacheTrimAt = now;
      // applyCacheLimit 内部已吞掉 TdError，这里的 catch 只兜底 Promise 层面的意外异常。
      applyCacheLimit(limit).catch((e: Error): void => {
        logE(`EntryAbility cache trim failed: ${e.message}`);
      });
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    AppStorage.setOrCreate('appIsForeground', false);
    setTdOnlineState(false);
    // 申请短时任务：切后台后多存活几分钟，这段时间内新消息仍能实时收到并通知。
    backgroundGraceTask.begin();
    // 解码后的位图很占内存（几十 MB 量级），后台留着只会抬高被系统查杀的概率。
    // 还挂在组件上的那些由引用计数保住，回前台重新解码代价很小。
    trimPixelCache();
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
