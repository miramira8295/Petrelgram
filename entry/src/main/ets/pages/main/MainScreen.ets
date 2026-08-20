import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { getTdClient, getUnreadCountStore, getCallSession, getChatStore, getChatThemeStore } from '../../tdkit/Globals';
import { CallSnapshot } from '../../services/CallSession';
import { callKeepAliveTask } from '../../services/CallKeepAliveTask';
import { bindAccentPrimary } from '../../util/accentTheme';
import { ProfileStore } from '../../store/ProfileStore';
import { AvatarView } from '../chatlist/AvatarView';
import { ChatListPage } from '../chatlist/ChatListPage';
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
import { overlayBackdropBlur, overlayMaterial, MATERIAL_EPOCH } from '../../util/overlayMaterial';

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
  @StorageProp('screenHeightVp') screenH: number = 780;
  @StorageProp(KEY_BG_BLUR) bgBlur: number = BG_BLUR_DEFAULT;
  @StorageProp(STORAGE_UPDATE_AVAILABLE) updateAvailable: boolean = false;
  // 回前台补偿：后台期间的来电 push 可能被系统拒绝，前台一刻重查一次。
  @StorageProp('appIsForeground') @Watch('onAppForegroundChanged') appIsForeground: boolean = true;
  @State tab: number = 0;
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
          console.error(`MainScreen incoming call navigation failed: ${error.message}`);
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
      console.error(`MainScreen.getMe failed: ${e.message}`);
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
        console.error(`MainScreen foreground call check failed: ${error.message}`);
      });
    }
  }

  private select(index: number): void {
    if (index === this.tab) {
      return;
    }
    animateTo({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, DOCK_SWITCH_DURATION),
      curve: Curve.EaseOut
    }, (): void => { this.tab = index; });
    this.controller.changeIndex(index);
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
      .systemMaterial(overlayMaterial('bar'))
      ;
    }
    .width('100%')
    // 两侧留白 16 → 28 → 40，胶囊再窄一档。四个格子是 layoutWeight 均分的，
    // 收窄只吃格子宽度，图标和文字尺寸不动——但「联系人」是最长的一条，
    // 再窄就该撞它了。
    .padding({ left: 40, right: 40 })
    .margin({ bottom: Math.max(DOCK_GAP, Math.round(this.bottomSafe * 0.7)) });
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
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
          this.tab = index;
        }
      })
      .width('100%').height('100%');

      this.dock();
    }
    .width('100%').height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
  }
}
