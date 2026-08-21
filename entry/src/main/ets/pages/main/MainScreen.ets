import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { getTdClient, getUnreadCountStore, getCallSession, getChatStore, getChatThemeStore } from '../../tdkit/Globals';
import { CallSnapshot } from '../../services/CallSession';
import { callKeepAliveTask } from '../../services/CallKeepAliveTask';
import { bindAccentPrimary } from '../../util/accentTheme';
import { ProfileStore } from '../../store/ProfileStore';
import { AvatarView } from '../chatlist/AvatarView';
import { ChatListPage, NAV_BAR_WIDTH_KEY, CHAT_NAV_BAR_VISIBLE_KEY } from '../chatlist/ChatListPage';
import { ContactsPage } from './ContactsPage';
import { SettingsPage } from './SettingsPage';
import { MyProfilePage } from './MyProfilePage';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import {
  COLOR_DIVIDER, COLOR_PRIMARY, COLOR_TAB_UNSELECTED, darkResourceMode
} from '../../util/theme';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import { updateChecker, STORAGE_UPDATE_AVAILABLE } from '../../services/UpdateChecker';
import { str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { BG_PATTERN_DEFAULT, patternStrengthKey } from '../../store/AppSettings';
import { ChatBackgroundState, preloadDefaultChatBackground } from '../../store/ChatBackgroundStore';
import { rasterizeBackground, patternOpacity } from '../../util/chatBackgroundRaster';
import { KEY_BG_BLUR, BG_BLUR_DEFAULT } from '../../store/AppSettings';
import { overlayBackdropBlur, MATERIAL_EPOCH } from '../../util/overlayMaterial';
import { materialModifier } from '../../util/materialModifier';
import { logE } from '../../util/log';

// Translucent tint over a backdrop blur — the frosted-glass dock material.
const DOCK_BG: ResourceColor = $r('app.color.dock_glass');
// 「有新版本」那颗小圆点。它和未读数不是一回事，所以有自己的颜色：绿色表示
// "有更新可拿"，跟着强调色走反而会和未读混成一个信号。
const UPDATE_DOT_BG: string = '#4CD964';
// 56：图标 24 + 间距 2 + 文字 10 = 36，加上 item 自己的 5 上下内缩正好 46，
// 余下 10 是胶囊的呼吸。原先 64 多出来的那 8 是空的。
const DOCK_H: number = 56;      // capsule height
// 底距。一路试下来：bottomSafe + 12（太远）→ max(8, bottomSafe)（还是远）→
// 半个 bottomSafe（太低）→ 现在取七成，落在后两者中间。别再往下：底部那条是
// 系统的返回/主页手势带，胶囊下沿贴太近，下半截的点击会被系统先吃掉。
const DOCK_GAP: number = 6;     // minimum gap below the capsule
const DOCK_ITEM_INSET: number = 5;
const DOCK_SWITCH_DURATION: number = 240;
// dock 进出会话时的淡入淡出时长。比切页签的 240 短：这不是一次「切换」，
// 只是让 dock 别在 NavDestination 滑入的那一瞬间硬生生消失。
const DOCK_FADE_DURATION: number = 160;

// Root screen after login: a floating capsule dock (聊天/联系人/设置/个人资料)
// over four keep-alive tab bodies. The dock is a rounded pill that hovers above
// full-screen content; content reserves bottom space so nothing hides behind it.
// Tabs use scrollable(false) so swiping never fights ChatListPage's inner folder
// Tabs — only dock taps switch tabs.
@Component
export struct MainScreen {
  // 材质档位（厚度/光感）改变时重绘。overlayMaterial 是 util，订阅不了
  // AppStorage，只能由调用方订阅，同 LANGUAGE_EPOCH 的做法。
  @StorageProp(MATERIAL_EPOCH) private materialEpoch: number = 0;
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @StorageProp('screenWidthVp') screenW: number = 360;
  // 聊天页签分栏时左栏的实际宽度（vp，0 = 还没量到）。由 ChatListPage 在自己的
  // 布局回调里写入——HdsNavigation 不回调宽度，拖分割线又会改它，只能这么拿。
  @StorageProp(NAV_BAR_WIDTH_KEY) private navBarWidth: number = 0;
  // 聊天页签的 navBar 此刻可不可见。false 只可能出现在「单栏 **且** 聊天栈非空」
  // ——也就是手机上打开了会话/资料/话题列表/归档的时候。见 CHAT_NAV_BAR_VISIBLE_KEY。
  @StorageProp(CHAT_NAV_BAR_VISIBLE_KEY) @Watch('syncDock') private chatNavBarVisible: boolean = true;
  // dock 的**交互态**：false 的那一刻起就不再接收任何点击，不等淡出结束。
  // 与 dockMounted 分开是本次修复的核心，理由见 syncDock()。
  @State private dockShown: boolean = true;
  // dock 的**渲染态**：淡出动画跑完才落 false，节点在这之前必须留在树上，
  // 否则没有东西可淡。
  @State private dockMounted: boolean = true;
  @StorageProp('screenHeightVp') screenH: number = 780;
  @StorageProp(KEY_BG_BLUR) bgBlur: number = BG_BLUR_DEFAULT;
  @StorageProp(STORAGE_UPDATE_AVAILABLE) updateAvailable: boolean = false;
  // 回前台补偿：后台期间的来电 push 可能被系统拒绝，前台一刻重查一次。
  @StorageProp('appIsForeground') @Watch('onAppForegroundChanged') appIsForeground: boolean = true;
  // 镜像到 AppStorage：Index.onBackPress 的三级递退（先回聊天页签，再回
  // "所有"文件夹，最后二次确认退出）要读它、也要写它。外部写入由 @Watch
  // 落到 TabsController 上。
  @StorageLink('mainTabIndex') @Watch('onTabExternallyChanged') tab: number = 0;
  private appliedTab: number = 0;
  @State unread: number = 0;
  @State myId: number = 0;
  @State meAvatar: string = '';
  @State meInitials: string = '?';
  private controller: TabsController = new TabsController();
  private store: ProfileStore | null = null;
  private unsubStore: (() => void) | null = null;
  private unsubUnread: (() => void) | null = null;
  private unsubAccent: (() => void) | null = null;
  private unsubCall: (() => void) | null = null;
  private callPagePushed: boolean = false;

  aboutToAppear(): void {
    // 已登录才查更新（MainScreen 只在登录后渲染），内部按 6 小时节流。
    updateChecker.check(false).catch((): void => {});
    // 背景（尤其是图案）要下载并解压 .tgv，放到开会话时做就是点击到首帧之间
    // 的卡顿。这里趁进主界面先跑一遍，结果进 TDLib 文件缓存和进程内的
    // inflatedPatterns，之后每个会话都是命中。
    preloadDefaultChatBackground(
      getTdClient(), getChatStore(), getChatThemeStore(),
      (): boolean => darkResourceMode(getContext(this) as common.UIAbilityContext),
      // 顺带把合成也做掉：第一次进会话时这张 jpg 已经在缓存里，不用再等
      // 离屏渲染 + 编码。
      (state: ChatBackgroundState): void => {
        rasterizeBackground(this.getUIContext(), {
          colors: state.colors, angle: state.angle, path: state.path,
          isPattern: state.isPattern,
          imageOpacity: patternOpacity(state.isPattern, state.imageOpacity,
            AppStorage.get<number>(patternStrengthKey(
              darkResourceMode(getContext(this) as common.UIAbilityContext)
            )) ?? BG_PATTERN_DEFAULT),
          dimming: state.dimming, blurred: state.blurred, userBlur: this.bgBlur,
          width: this.screenW, height: this.screenH
        }, (getContext(this) as common.UIAbilityContext).cacheDir);
      });
    // 来电（应用存活时）：常驻订阅通话状态，响铃即弹入通话页。
    this.unsubCall = getCallSession().subscribe((s: CallSnapshot): void => {
      // 通话期保活：接通流程开始挂 voip 长时任务，结束即释放。
      if (s.phase === 'connecting' || s.phase === 'active') {
        callKeepAliveTask.start(getContext(this) as common.UIAbilityContext);
      } else if (s.phase === 'ended' || s.phase === 'idle') {
        callKeepAliveTask.stop();
      }
      if (s.phase === 'ringing' && !s.isOutgoing) {
        if (this.callPagePushed) {
          return;
        }
        this.callPagePushed = true;
        router.pushUrl({ url: 'pages/call/CallPage' }).catch((error: Error): void => {
          logE(`MainScreen incoming call navigation failed: ${error.message}`);
        });
      } else if (s.phase === 'idle' || s.phase === 'ended') {
        this.callPagePushed = false;
      }
    });
    this.unsubAccent = bindAccentPrimary(getContext(this) as common.UIAbilityContext);
    this.unread = getUnreadCountStore().getUnread('main');
    this.unsubUnread = getUnreadCountStore().subscribe(() => {
      this.unread = getUnreadCountStore().getUnread('main');
    });
    const req: TdRequest = { '@type': 'getMe' };
    getTdClient().send(req).then((me: TdObject) => {
      this.myId = (me['id'] as number | undefined) ?? 0;
      if (this.myId === 0) {
        return;
      }
      const store = new ProfileStore(getTdClient(), this.myId);
      this.store = store;
      this.unsubStore = store.subscribe(() => {
        this.meAvatar = store.avatarPath;
        this.meInitials = store.initials;
      });
      store.open();
    }).catch((e: TdError) => {
      logE(`MainScreen.getMe failed: ${e.message}`);
    });
  }

  aboutToDisappear(): void {
    if (this.unsubAccent !== null) { this.unsubAccent(); this.unsubAccent = null; }
    if (this.unsubUnread !== null) { this.unsubUnread(); this.unsubUnread = null; }
    if (this.unsubStore !== null) { this.unsubStore(); this.unsubStore = null; }
    if (this.unsubCall !== null) { this.unsubCall(); this.unsubCall = null; }
    if (this.store !== null) { this.store.close(); this.store = null; }
  }

  onAppForegroundChanged(): void {
    if (!this.appIsForeground) {
      return;
    }
    const s = getCallSession().current();
    if (s.phase === 'ringing' && !s.isOutgoing && !this.callPagePushed) {
      this.callPagePushed = true;
      router.pushUrl({ url: 'pages/call/CallPage' }).catch((error: Error): void => {
        this.callPagePushed = false;
        logE(`MainScreen foreground call check failed: ${error.message}`);
      });
    }
  }

  private select(index: number): void {
    if (index === this.tab) {
      return;
    }
    this.appliedTab = index;
    animateTo({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, DOCK_SWITCH_DURATION),
      curve: Curve.EaseOut
    }, (): void => { this.tab = index; });
    this.controller.changeIndex(index);
  }

  // AppStorage 侧被外部改写（返回键递退）时，把 Tabs 真正切过去。自己内部
  // 的写入先记 appliedTab，这里就不会重复 changeIndex。
  private onTabExternallyChanged(): void {
    if (this.tab !== this.appliedTab) {
      this.appliedTab = this.tab;
      this.controller.changeIndex(this.tab);
    }
    // dockVisible() 也读 tab，所以切页签同样要重算一次。
    this.syncDock();
  }

  // 把 dock 的两个状态推到 dockVisible() 要求的目标上。
  //
  // 【为什么是两个状态而不是一个 if】上一版写的是
  // `if (this.dockVisible()) { this.dock(); }` 加一个 TransitionEffect.OPACITY。
  // 稳态没问题（节点真的不在树上），**但退场那 160ms 是个空档**：过渡期间节点
  // 仍在渲染树里参与合成与命中测试，而 ArkUI 默认 HitTestMode.Default、
  // **透明度不影响命中测试**；dock 在 Stack 里写在 Tabs 之后、z 序更高，正悬浮
  // 在 ChatPage 输入区上方。于是「点开会话后手快点附件没反应」——偶发、难复现。
  //
  // 光加 hitTestBehavior 修不了：`if` 分支一旦转 false，那棵子树就不再被 build，
  // 过渡期间保留的是它**最后一次构建时**的属性（那时还是可点的）。也就是说
  // 条件渲染 + 过渡这个组合，结构上就没法在退场时改任何属性。所以改成常驻节点，
  // 由两个状态分别管交互和渲染：
  //
  //   dockShown   t=0 立刻翻 —— 决定 opacity 目标、enabled、hitTestBehavior
  //   dockMounted t=末尾才翻 —— 决定 visibility，节点撤不撤出布局与渲染
  //
  // 【进场方向是有意不对称的】隐藏时 t=0 就断交互，显示时 t=0 就恢复交互（两者
  // 都由 dockShown 一个量给出）。理由：dock 淡入时位置已经是终态、只有透明度在
  // 变，而它底下那块是 ChatListView 用 reserveDockSpace 特意留空的死区，点那里
  // 不可能是想点别的东西。此时不响应就是另一种「点了没反应」——把要修的毛病镜像
  // 了一遍。迁移前整页路由弹回时 dock 也是立刻可点的。
  private syncDock(): void {
    const want: boolean = this.dockVisible();
    if (want === this.dockShown) {
      return;
    }
    const duration: number =
      powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, DOCK_FADE_DURATION);
    if (want) {
      // 先挂树再淡入：节点不在树上时改 opacity 没有任何东西可动。
      this.dockMounted = true;
      animateTo({ duration: duration, curve: Curve.EaseOut },
        (): void => { this.dockShown = true; });
      return;
    }
    animateTo({
      duration: duration,
      curve: Curve.EaseOut,
      // 淡出跑完才撤出渲染。这里必须再确认一次 dockShown：160ms 内用户可能已经
      // 返回了（快速进出会话），那时节点刚重新挂上，不能被这个迟到的回调摘掉。
      onFinish: (): void => {
        if (!this.dockShown) {
          this.dockMounted = false;
        }
      }
    }, (): void => { this.dockShown = false; });
  }

  @Styles
  dockItemNormalStyle() {
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  // 按压反馈只能自己画。'control' 档材质确实自带 interactive 形变和 lightEffect
  // 触点光晕，但那层光感和它渲染的玻璃是同一块——挂到格子上，四个按钮底下就
  // 各多一块圆底（真机实测）。材质属于胶囊那一层，格子只负责缩放。
  @Styles
  dockItemPressedStyle() {
    .opacity(0.72)
    .scale({ x: 0.92, y: 0.92 })
  }

  // label 是 ResourceStr 而不是 string：$r() 由框架在渲染时解析，天然跟随
  // 语言切换。原来传 str() 出来的普通字符串，切语言后要重启才更新 —— 依赖
  // langEpoch 触发重建的做法在这里不可靠，因为 setAppPreferredLanguage 是
  // 应用级设置，未必触发 Ability 的配置变更回调。
  @Builder
  dockItem(index: number, icon: string, label: ResourceStr, labelKey: string) {
    Column({ space: 2 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        // 系统符号动效，不是自己写的 scale：选中时整体向上弹一下，动画曲线
        // 由系统给，和其它系统图标一致。第二个参数是布尔触发器——false→true
        // 的那一刻播一次，所以只有"变成选中"会弹，重复点已选中的不会。
        SymbolGlyph($r(icon)).fontSize(24)
          .fontColor([this.tab === index ? COLOR_PRIMARY : COLOR_TAB_UNSELECTED])
          .symbolEffect(
            new BounceSymbolEffect(EffectScope.WHOLE, EffectDirection.UP),
            this.tab === index
          )
          .effectStrategy(SymbolEffectStrategy.NONE);
        // 设置页签的红点：和「关于」那一行是同一个信号，一路引到更新入口。
        if (index === 2 && this.updateAvailable) {
          Circle({ width: 8, height: 8 }).fill(UPDATE_DOT_BG).offset({ x: 6, y: -2 });
        }
        if (index === 0 && this.unread > 0) {
          Row() {
            Text(this.unread > 99 ? '99+' : `${this.unread}`)
              .fontSize(10).fontColor(Color.White).fontWeight(FontWeight.Medium);
          }
            .constraintSize({ minWidth: 18 }).height(18)
            .padding({ left: 5, right: 5 })
            .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
            // 未读数跟强调色。原来这里写死成 #4CD964，用户换了强调色也不变
            // ——而聊天列表行里的未读气泡一直是 COLOR_PRIMARY，两处对不上。
            .backgroundColor(COLOR_PRIMARY).borderRadius(9)
            .offset({ x: 12, y: -7 });
        }
      }
      Text(label).fontSize(10)
        .fontColor(this.tab === index ? COLOR_PRIMARY : COLOR_TAB_UNSELECTED);
    }
    .layoutWeight(1).height('100%')
    .justifyContent(FlexAlign.Center)
    .borderRadius((DOCK_H - DOCK_ITEM_INSET * 2) / 2)
    .stateStyles({
      normal: this.dockItemNormalStyle,
      pressed: this.dockItemPressedStyle
    })
    // 无障碍文本必须是普通字符串，所以这里另外收一个资源 key 现场取词；
    // 可见文案走上面的 $r()，两者语言一致。
    .accessibilityText(index === 0 && this.unread > 0
      ? str('a11y_tab_unread', this.dockLabel(labelKey), this.unread,
        this.tab === index ? str('a11y_selected') : '')
      : str('a11y_option_state', this.dockLabel(labelKey),
        this.tab === index ? str('a11y_selected') : ''))
    .onClick(() => { this.select(index); });
  }

  @Builder
  profileDockItem() {
    Column({ space: 2 }) {
      Stack() {
        AvatarView({ avatarPath: this.meAvatar, initials: this.meInitials, colorSeed: this.myId, avatarSize: 24 });
      }
      .width(32).height(32).borderRadius(16).padding(2)
      // A constant border width avoids a size jump when this tab is selected.
      .border({ width: 2, color: this.tab === 3 ? COLOR_PRIMARY : Color.Transparent });
      Text($r('app.string.tab_profile')).fontSize(10)
        .fontColor(this.tab === 3 ? COLOR_PRIMARY : COLOR_TAB_UNSELECTED);
    }
    .layoutWeight(1).height('100%')
    .justifyContent(FlexAlign.Center)
    .borderRadius((DOCK_H - DOCK_ITEM_INSET * 2) / 2)
    .stateStyles({
      normal: this.dockItemNormalStyle,
      pressed: this.dockItemPressedStyle
    })
    .accessibilityText(str('a11y_option_state', str('tab_profile'), this.tab === 3 ? str('a11y_selected') : ''))
    .onClick(() => { this.select(3); });
  }

  // Dock 标签必须经这里取：str() 出来的是普通字符串，节点只有在"构建时读过
  // 某个状态"才会随它重建 —— langEpoch 光声明不读，语言切换时 dock 纹丝不动
  // （用户实测要重启才生效）。这里显式读一次 langEpoch 建立依赖。
  private dockLabel(key: string): string {
    void this.langEpoch;
    return str(key);
  }

  // 分栏时 dock 归左栏：它导航的就是左栏内容，横跨整屏正好压在右栏的聊天输入框
  // 上（真机截图确认）。宽度不能写死——enableDragBar(true) 允许用户拖分割线。
  //
  // 只认聊天页签：联系人/设置/个人资料三个页签都显式 .mode(NavigationMode.Stack)
  // 强制单栏，它们在屏上时整页就是整屏宽，dock 缩在左边一条是错的。
  // 手机（单栏）下 navBarWidth 量到的就是整屏宽，自然退化为改造前的行为；
  // 还没量到（0）时同样退化，不会先闪一下窄条。
  private dockWidth(): Length {
    return this.tab === 0 && this.navBarWidth > 0 ? this.navBarWidth : '100%';
  }

  // dock 该不该在屏上。
  //
  // 【为什么需要这个判断】会话页迁到 HdsNavDestination（commit 8046f73）之前，
  // ChatPage 是 main_pages.json 里的整页 router 页，整屏盖在 MainScreen 之上，
  // dock 根本不可见。迁移之后 ChatPage 渲染在 chatStack 里，而 chatStack 在
  // 本组件的 Tabs 之内——dock 是 Tabs 的兄弟节点且写在后面，于是常驻在会话页
  // 之上，正压住底部输入栏。归档/资料/群资料/话题列表四个页面同理。
  //
  // 【为什么条件是这个】要藏的是「单栏 **且** 栈非空」这个组合，不是单看栈深。
  // 分栏（平板）下栈非空是常态，那时 dock 在左栏、不需要任何避让（Task 8 已把
  // 它约束在左栏宽度内）。chatNavBarVisible 正好就是这个组合的反面——navBar
  // 只在单栏推入 NavDestination 时才会被系统隐藏，分栏下恒可见。
  //
  // 【为什么还要看 tab】联系人/设置/个人资料三个页签有各自的 HdsNavigation，
  // 都不带 NavPathStack、永远不推目的地，chatNavBarVisible 与它们无关。停在
  // 这三个页签上时 dock 必须照常显示，哪怕聊天栈里还留着一个会话。
  private dockVisible(): boolean {
    return this.tab !== 0 || this.chatNavBarVisible;
  }

  // Floating capsule: outer Column carries the horizontal padding + bottom
  // margin (width('100%') + horizontal margin conflict on the same node in
  // ArkUI), inner Row is the pill itself.
  @Builder
  dock() {
    Column() {
      // 选中不再画底。原先是一块跟着 tab 滑的药丸，在玻璃胶囊上等于第二层
      // 不透明底色，正好压在材质上面。现在靠主色 + 图标自己的弹跳表示选中，
      // 外面那层 Stack（唯一作用是给药丸定位）也一并去掉了。
      Row() {
        this.dockItem(0, 'sys.symbol.message', $r('app.string.tab_chats'), 'tab_chats');
        this.dockItem(1, 'sys.symbol.person_2', $r('app.string.tab_contacts'), 'tab_contacts');
        this.dockItem(2, 'sys.symbol.gearshape', $r('app.string.settings_title'), 'settings_title');
        this.profileDockItem();
      }
      .alignItems(VerticalAlign.Center)
      .width('100%').height(DOCK_H)
      .backgroundColor(DOCK_BG)
      // backdropBlur over a light tint: COMPONENT_* material styles carry an
      // opaque built-in backboard that reads as solid gray, so blur the
      // backdrop directly instead. The immersive material has no such backboard
      // and supersedes this — overlayBackdropBlur() drops to 0 where it applies.
      .backdropBlur(overlayBackdropBlur('bar'))
      .borderRadius(DOCK_H / 2)
      .clip(true)
      .border({ width: 0.5, color: COLOR_DIVIDER })
      .shadow({ radius: 14, color: '#24000000', offsetX: 0, offsetY: 4 })
      .attributeModifier(materialModifier('bar'))
      ;
    }
    .width(this.dockWidth())
    // 两侧留白 16 → 28 → 40，胶囊再窄一档。四个格子是 layoutWeight 均分的，
    // 收窄只吃格子宽度，图标和文字尺寸不动——但「联系人」是最长的一条，
    // 再窄就该撞它了。
    .padding({ left: 40, right: 40 })
    .margin({ bottom: Math.max(DOCK_GAP, Math.round(this.bottomSafe * 0.7)) })
    // 进出会话时的淡入淡出。迁移前是整页 router 覆盖，dock 消失得没有过渡；
    // 这里补一段短淡出，免得 NavDestination 从右侧滑入的那两百多毫秒里，
    // 底下的会话列表突然秃一块。动画由 syncDock() 的 animateTo 驱动，时长跟随
    // 「流畅动效」开关，关掉即为 0。
    .opacity(this.dockShown ? 1 : 0)
    // 下面这两行是**退场空档**的正解，缺一不可，都在 dockShown 翻 false 的那一
    // 帧立即生效（两者都不是可动画属性，animateTo 不会把它们摊到 160ms 上）：
    //
    //   enabled(false)          官方「禁用控制」：设置了它的组件**及其子组件**
    //                           不发起触摸测试，直接返回父组件继续测试——正好
    //                           让点击落到兄弟节点 Tabs（也就是 ChatPage）上。
    //                           四个格子的 onClick 都在子节点上，只靠下面那行
    //                           是盖不住的（HitTestMode.None 的原文是「自身不接收
    //                           事件，但**不会阻塞子组件**继续做触摸测试」）。
    //   hitTestBehavior(None)   把 dock 自己这一层也从响应链里摘掉，免得它命中
    //                           后按 Default 的规则阻塞兄弟节点。
    //
    // 没有视觉副作用：Column/Row/Text/SymbolGlyph/Image 都没有内置禁用态样式
    // （官方 enabled 示例里那个变灰是自己额外写的 opacity(0.4)）。
    .enabled(this.dockShown)
    .hitTestBehavior(this.dockShown ? HitTestMode.Default : HitTestMode.None)
    // 淡出跑完再撤出布局与渲染。用 visibility 而不是 `if`：节点留在组件树里，
    // 属性才会继续跟着状态更新——`if` 摘掉的子树在过渡期间是冻结的，那正是
    // 上一版修不掉退场空档的原因（见 syncDock）。
    .visibility(this.dockMounted ? Visibility.Visible : Visibility.None);
  }

  build() {
    // BottomStart 而不是 Bottom：dock 分栏时是一条定宽的左栏内容，居中就飘到
    // 两栏中间去了。Tabs 是 width/height 100%，换对齐方式影响不到它。
    // Start 会跟着布局方向镜像，和 navBar 默认的 NavBarPosition.Start 一致。
    Stack({ alignContent: Alignment.BottomStart }) {
      Tabs({ controller: this.controller }) {
        TabContent() { ChatListPage(); }
        TabContent() { ContactsPage(); }
        TabContent() { SettingsPage(); }
        TabContent() {
          MyProfilePage({
            active: this.tab === 3,
            onOpenSettings: (): void => { this.select(2); }
          });
        }
      }
      .barHeight(0)
      .scrollable(false)
      .animationDuration(powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, DOCK_SWITCH_DURATION))
      .onAnimationStart((_currentIndex: number, targetIndex: number) => {
        if (this.tab !== targetIndex) {
          animateTo({
            duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, DOCK_SWITCH_DURATION),
            curve: Curve.EaseOut
          }, (): void => { this.tab = targetIndex; });
        }
      })
      .onChange((index: number) => {
        // Keep the dock synced if Tabs changes its final index after a rapid
        // sequence of taps.
        if (this.tab !== index) {
          this.appliedTab = index;
          this.tab = index;
        }
      })
      .width('100%').height('100%');

      // dock 常驻在树上，藏与不藏由它自己的 opacity / enabled / visibility 决定
      // （见 dock() 末尾与 syncDock()）。这里**不能**用 `if`：条件渲染摘掉的子树
      // 在退场过渡期间不再重新构建，属性冻结在「还可点」的那一版上，于是有
      // 160ms 的空档能吃掉落在 ChatPage 输入区上的点击。
      this.dock();
    }
    .width('100%').height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
  }
}
