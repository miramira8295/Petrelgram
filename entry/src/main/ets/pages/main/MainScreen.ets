import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { getTdClient, getUnreadCountStore, getCallSession, getChatStore, getChatThemeStore } from '../../tdkit/Globals';
import { CallSnapshot } from '../../services/CallSession';
import { callKeepAliveTask } from '../../services/CallKeepAliveTask';
import { ProfileStore } from '../../store/ProfileStore';
import { AvatarView } from '../chatlist/AvatarView';
import { ChatListPage, NAV_BAR_WIDTH_KEY, CHAT_NAV_BAR_VISIBLE_KEY } from '../chatlist/ChatListPage';
import {
  ContactsPage, CONTACTS_NAV_BAR_VISIBLE_KEY, CONTACTS_NAV_BAR_WIDTH_KEY
} from './ContactsPage';
import {
  SettingsPage, SETTINGS_NAV_BAR_VISIBLE_KEY, SETTINGS_NAV_BAR_WIDTH_KEY
} from './SettingsPage';
import { MyProfilePage, PROFILE_NAV_BAR_VISIBLE_KEY } from './MyProfilePage';
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
import { overlayBackdropBlur, materialOff, MATERIAL_EPOCH } from '../../util/overlayMaterial';
import { APPEARANCE_EPOCH } from '../../util/appearance';
import { DOCK_SIDE_PADDING, dockSidePadding } from '../../util/mainTabsWidth';
import { publishTabReTap } from '../../util/tabReTap';
import { KEY_SHOW_CONTACTS_TAB } from '../../store/AppSettings';
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
// dock 返回时的淡入时长。进入目的页时立即撤下，避免它的材质层继续参与
// NavDestination 的推入合成；返回列表时再用短淡入恢复视觉连续性。
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
  // 强调色是 theme 里的活绑定，不是状态；dock 读一次 epoch 才会在用户改色后重绘。
  @StorageProp(APPEARANCE_EPOCH) private appearanceEpoch: number = 0;
  // 交互设置里可以把「联系人」页签从底栏藏掉；正停在它上面时跳回聊天。
  @StorageProp(KEY_SHOW_CONTACTS_TAB) @Watch('onShowContactsTabChanged') showContactsTab: boolean = true;
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @StorageProp('screenWidthVp') screenW: number = 360;
  // 聊天页签分栏时左栏的实际宽度（vp，0 = 还没量到）。由 ChatListPage 在自己的
  // 布局回调里写入——HdsNavigation 不回调宽度，拖分割线又会改它，只能这么拿。
  @StorageProp(NAV_BAR_WIDTH_KEY) private navBarWidth: number = 0;
  // 聊天页签的 navBar 此刻可不可见。false 只可能出现在「单栏 **且** 聊天栈非空」
  // ——也就是手机上打开了会话/资料/话题列表/归档的时候。见 CHAT_NAV_BAR_VISIBLE_KEY。
  @StorageProp(CHAT_NAV_BAR_VISIBLE_KEY) @Watch('syncDock') private chatNavBarVisible: boolean = true;
  // 设置页签分栏时左栏的实际宽度（vp，0 = 还没量到）。与聊天页签分开存：两个
  // 页签各自 enableDragBar(true)，拖过之后两边不再相等。见
  // SETTINGS_NAV_BAR_WIDTH_KEY。
  @StorageProp(SETTINGS_NAV_BAR_WIDTH_KEY) private settingsNavBarWidth: number = 0;
  // 设置页签的 navBar 此刻可不可见。false 只可能出现在「单栏 **且** 设置栈非空」
  // ——也就是手机上打开了已迁成 NavDestination 的设置子页的时候。
  @StorageProp(SETTINGS_NAV_BAR_VISIBLE_KEY) @Watch('syncDock') private settingsNavBarVisible: boolean = true;
  // 联系人页签分栏时左栏的实际宽度（vp，0 = 还没量到）。第三个独立的键，理由
  // 同上：三个页签各自 enableDragBar(true)，拖过之后互不相等。见
  // CONTACTS_NAV_BAR_WIDTH_KEY。
  @StorageProp(CONTACTS_NAV_BAR_WIDTH_KEY) private contactsNavBarWidth: number = 0;
  // 联系人页签的 navBar 此刻可不可见。手机上恒为 true——本页在单栏下不推任何
  // 目的地（点联系人直接开会话，见 ContactsPage.openContact）；平板分栏下左栏
  // 常驻，同样恒为 true。留着这一支不是冗余：断点是窗口宽，平板分屏到
  // < 600vp 时就是单栏，那时右栏那层 ProfilePage 会盖上来，dock 必须跟着藏。
  @StorageProp(CONTACTS_NAV_BAR_VISIBLE_KEY) @Watch('syncDock') private contactsNavBarVisible: boolean = true;
  // 个人资料页签的 navBar 此刻可不可见。**没有配套的宽度键**：这一页强制单栏
  //（.mode(NavigationMode.Stack)），navBar 恒等于整屏宽，dock 用 '100%' 就对。
  // 也正因为永远单栏，这个键的 false 直接等价于「个人资料栈非空」——平板上
  // 同样会翻 false，而那正是要的：单栏下编辑页是整页替换、铺满整屏。
  // 见 PROFILE_NAV_BAR_VISIBLE_KEY。
  @StorageProp(PROFILE_NAV_BAR_VISIBLE_KEY) @Watch('syncDock') private profileNavBarVisible: boolean = true;
  // dock 的**交互态**：false 的那一刻起就不再接收任何点击，不等淡出结束。
  // 与 dockMounted 分开是本次修复的核心，理由见 syncDock()。
  @State private dockShown: boolean = true;
  // dock 的**渲染态**：显示时先挂载再淡入；隐藏时与 dockShown 同帧撤下。
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
  private unsubCall: (() => void) | null = null;
  private callPagePushed: boolean = false;

  aboutToAppear(): void {
    // **先让 Tabs 与 mainTabIndex 对齐。**
    //
    // 本组件不是只在冷启动时建一次：账号切换（含"添加账号"和取消添加返回原
    // 账号）会 bumpSessionEpoch() 把整棵树重建，而 mainTabIndex 存在 AppStorage
    // 里、跨重建存活。于是 this.tab 恢复成 2（设置），Tabs 却从 0 开始——
    // 屏幕上是聊天列表，dock 高亮的却是"设置"。更糟的是点"设置"也没反应：
    // select() 看见 index === this.tab 就早退了。用户报的正是这一串（issue #119）。
    //
    // @Watch 救不了：ArkUI 的 @Watch 不在初始化时触发，只在此后的变化上触发。
    // 所以对齐必须在这里显式做一次。appliedTab 一并跟上，否则 select() 的
    // 去重基准从一开始就是错的。
    this.appliedTab = this.tab;
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
      // 点已经选中的页签：交给那一页自己处理（聊天页是回顶 / 跳下一个未读，
      // issue #35）。这里只发信号，不知道也不该知道对方怎么响应。
      publishTabReTap(index);
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

  // 把 dock 的交互态与渲染态推到目标上。推入目的页时立即断交互并撤下整个
  // 玻璃层，避免和系统转场并发；返回列表时先挂载 opacity=0 的节点再淡入。
  private syncDock(): void {
    const want: boolean = this.dockVisible();
    if (want === this.dockShown) {
      return;
    }
    if (want) {
      // 先挂树再淡入：节点不在树上时改 opacity 没有任何东西可动。
      this.dockMounted = true;
      const duration: number =
        powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, DOCK_FADE_DURATION);
      animateTo({ duration: duration, curve: Curve.EaseOut },
        (): void => { this.dockShown = true; });
      return;
    }
    this.dockShown = false;
    this.dockMounted = false;
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
          .fontColor([this.tab === index ? this.accent() : COLOR_TAB_UNSELECTED])
          // 双气泡这类多层图标按不透明度分层：前面那只实心，后面那只淡一层。
          // 单层图标（齿轮、联系人）走这条也不变样。
          .renderingStrategy(SymbolRenderingStrategy.MULTIPLE_OPACITY)
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
            .backgroundColor(this.accent()).borderRadius(9)
            .offset({ x: 12, y: -7 });
        }
      }
      Text(label).fontSize(10)
        .fontColor(this.tab === index ? this.accent() : COLOR_TAB_UNSELECTED);
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
      .border({ width: 2, color: this.tab === 3 ? this.accent() : Color.Transparent });
      Text($r('app.string.tab_profile')).fontSize(10)
        .fontColor(this.tab === 3 ? this.accent() : COLOR_TAB_UNSELECTED);
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
  // 认聊天(0)、联系人(1)、设置(2)三个页签：这三个的 HdsNavigation 都带
  // NavPathStack、都走默认的 Auto 模式，宽屏上会分栏。个人资料(3)现在也带
  // NavPathStack（编辑信息推进去），但仍显式 .mode(NavigationMode.Stack) 强制
  // 单栏——它在屏上时整页就是整屏宽，dock 缩在左边一条是错的，所以这一支照旧
  // 落到底下的 '100%'，不给它开第四个宽度键。
  // 三个页签各读各的键：拖过分割线之后左栏宽度不再相等，共用一个会在另外两个
  // 页签上错开。
  // 手机（单栏）下量到的就是整屏宽，自然退化为改造前的行为；还没量到（0）时
  // 同样退化，不会先闪一下窄条。
  // 藏掉联系人页签后胶囊里只剩三格，两侧留白补上空出的那一格（issue #135）。
  private dockPadding(): number {
    const w: number = typeof this.dockWidth() === 'number'
      ? this.dockWidth() as number : this.screenW;
    return dockSidePadding(w, this.showContactsTab ? 4 : 3, DOCK_SIDE_PADDING);
  }

  private dockWidth(): Length {
    if (this.tab === 0) {
      return this.navBarWidth > 0 ? this.navBarWidth : '100%';
    }
    if (this.tab === 1) {
      return this.contactsNavBarWidth > 0 ? this.contactsNavBarWidth : '100%';
    }
    if (this.tab === 2) {
      return this.settingsNavBarWidth > 0 ? this.settingsNavBarWidth : '100%';
    }
    return '100%';
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
  // 【为什么还要看 tab】每个页签的 navBar 显隐是各自独立的一件事，chatNavBarVisible
  // 只描述聊天页签。停在别的页签上时 dock 必须照常显示，哪怕聊天栈里还留着一个
  // 会话。
  //
  // 设置页签（2）现在也有自己的 NavPathStack（首个 NavDestination 是
  // PowerUsagePage），于是同一套判断要照做一遍：手机上推入设置子页之后，子页不再
  // 是盖住整个 MainScreen 的整页 router 页，dock 会浮在它上面——必须跟着藏。
  // 联系人页签（1）同理，只是它在手机上不推目的地（点联系人直接开会话），
  // contactsNavBarVisible 在手机上恒为 true，dock 行为与改造前逐字相同；这一支
  // 真正管的是「平板分屏到 <600vp、右栏那层 ProfilePage 盖上来」那一刻。
  // 【原注释，已经是历史，保留原文】「个人资料（3）仍强制单栏、永远不推目的地，
  // 恒显示。」——个人资料页签现在有自己的栈了（「编辑信息」推 AccountEditPage
  // 进去），于是同一套判断要照做第四遍。它强制单栏，编辑页因此是**整页替换**、
  // 铺满整屏，dock 浮在它上面正好压住底部——手机平板都一样，这一支不像联系人
  // 那样在手机上恒为 true。
  private dockVisible(): boolean {
    if (this.tab === 0) {
      return this.chatNavBarVisible;
    }
    if (this.tab === 1) {
      return this.contactsNavBarVisible;
    }
    if (this.tab === 2) {
      return this.settingsNavBarVisible;
    }
    if (this.tab === 3) {
      return this.profileNavBarVisible;
    }
    return true;
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
        this.dockItem(0, 'sys.symbol.message_on_message_fill', $r('app.string.tab_chats'), 'tab_chats');
        if (this.showContactsTab) {
          this.dockItem(1, 'sys.symbol.person_2_fill', $r('app.string.tab_contacts'), 'tab_contacts');
        }
        this.dockItem(2, 'sys.symbol.gearshape', $r('app.string.settings_title'), 'settings_title');
        this.profileDockItem();
      }
      .alignItems(VerticalAlign.Center)
      .width('100%').height(DOCK_H)
      .backgroundColor(this.dockBg())
      // backdropBlur over a light tint: COMPONENT_* material styles carry an
      // opaque built-in backboard that reads as solid gray, so blur the
      // backdrop directly instead. The immersive material has no such backboard
      // and supersedes this — overlayBackdropBlur() drops to 0 where it applies.
      .backdropBlur(this.dockBlur())
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
    .padding({ left: this.dockPadding(), right: this.dockPadding() })
    .margin({ bottom: Math.max(DOCK_GAP, Math.round(this.bottomSafe * 0.7)) })
    // 返回列表时淡入；进入目的页时 syncDock() 同帧撤下玻璃层。
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
    // visibility 保留同一个组件实例，供返回时先挂载再淡入。
    .visibility(this.dockMounted ? Visibility.Visible : Visibility.None);
  }

  // dock 的底色/模糊读一次 materialEpoch：厚度/关闭改了才会重绘。厚度「关闭」
  // 时底色退回实色 surface，否则还是那层玻璃色（材质在的时候压在材质上做染色）。
  onShowContactsTabChanged(): void {
    if (!this.showContactsTab && this.tab === 1) {
      this.tab = 0;
    }
  }

  private accent(): ResourceColor {
    return this.appearanceEpoch < 0 ? Color.Transparent : COLOR_PRIMARY;
  }

  private dockBg(): ResourceColor {
    if (this.materialEpoch < 0) {
      return Color.Transparent;
    }
    return materialOff() ? $r('app.color.surface') : DOCK_BG;
  }

  private dockBlur(): number {
    return this.materialEpoch < 0 ? 0 : overlayBackdropBlur('bar');
  }

  build() {
    // BottomStart 而不是 Bottom：dock 分栏时是一条定宽的左栏内容，居中就飘到
    // 两栏中间去了。Tabs 是 width/height 100%，换对齐方式影响不到它。
    // Start 会跟着布局方向镜像，和 navBar 默认的 NavBarPosition.Start 一致。
    Stack({ alignContent: Alignment.BottomStart }) {
      // index 显式跟住 mainTabIndex，Tabs 才不会在树重建后从 0 开始——
      // 见 aboutToAppear 里的说明。稳态下它与 controller.changeIndex 同值，
      // 重复驱动是幂等的。
      Tabs({ controller: this.controller, index: this.tab }) {
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
