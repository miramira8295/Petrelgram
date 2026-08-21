import { promptAction } from '@kit.ArkUI';
import { getTdClient, logoutCurrentTdAccount } from '../../tdkit/Globals';
import { floatingLiveWindow } from '../chat/LiveFloatingWindow';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import { str } from '../../util/strings';
import { monthDay } from '../../util/intlFormat';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import {
  overlayBackdropBlur, overlayGlassFill, MATERIAL_EPOCH
} from '../../util/overlayMaterial';
import { materialModifier } from '../../util/materialModifier';
import { logE } from '../../util/log';
import { HdsSubDestination } from '../common/HdsSubDestination';
import { NavStackLike, stackOf } from '../../util/navStacks';
import {
  HdsNavigationIconOptions, HdsNavigationMenuItemOptions
} from '@kit.UIDesignKit';

const CARD_BG: ResourceColor = $r('app.color.surface');
const CARD_RADIUS: number = 14;
const BIO_MAX: number = 140;
const ACCOUNT_LOAD_TIMEOUT_MS: number = 8000;

// 账号 edit page (Telegram-style): first/last name, bio (140 chars), and the
// read-only personal-info card. ✓ in the header saves via setName/setBio.
// 路由表（router_map.json）的 buildFunction 指向这里。系统在跳转时动态加载本模块
// 并调用它，页面因此不再进 main_pages.json——一个页面不能同时是 router 页和
// NavDestination。形状与试点的 PowerUsagePageBuilder 一致。
@Builder
export function AccountEditPageBuilder(): void {
  AccountEditPage();
}

@Component
export struct AccountEditPage {
  private hdsScroller: Scroller = new Scroller();
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State firstName: string = '';
  @State lastName: string = '';
  @State bio: string = '';
  @State phone: string = '';
  @State username: string = '';
  @State birthday: string = '';
  @State loading: boolean = true;
  @State loadError: string = '';
  @State saveError: string = '';
  @State skeletonBright: boolean = false;
  @State saving: boolean = false;
  @State loggingOut: boolean = false;
  @State leavingPage: boolean = false;
  @State discardDialogOpen: boolean = false;
  private origFirst: string = '';
  private origLast: string = '';
  private origBio: string = '';
  private leaveTimer: number = -1;
  private loadSequence: number = 0;
  private skeletonTimer: number = -1;

  aboutToAppear(): void {
    this.loadProfile();
  }

  aboutToDisappear(): void {
    this.loadSequence++;
    this.stopSkeletonPulse();
    if (this.leaveTimer !== -1) {
      clearTimeout(this.leaveTimer);
      this.leaveTimer = -1;
    }
    this.leavingPage = false;
    this.discardDialogOpen = false;
  }

  private async loadProfile(): Promise<void> {
    const sequence = ++this.loadSequence;
    this.loading = true;
    this.loadError = '';
    this.saveError = '';
    this.startSkeletonPulse();
    try {
      const me = await getTdClient().send(
        { '@type': 'getMe' } as TdRequest,
        ACCOUNT_LOAD_TIMEOUT_MS
      );
      if (sequence !== this.loadSequence) {
        return;
      }
      const myId = (me['id'] as number | undefined) ?? 0;
      if (myId === 0) {
        throw new Error('current user unavailable');
      }
      // getUser and getUserFullInfo must both succeed before editing is enabled.
      // Otherwise an empty field could overwrite data that merely failed to load.
      const userRequest: TdRequest = { '@type': 'getUser' };
      userRequest['user_id'] = myId;
      const fullRequest: TdRequest = { '@type': 'getUserFullInfo' };
      fullRequest['user_id'] = myId;
      const values: TdObject[] = await Promise.all([
        getTdClient().send(userRequest, ACCOUNT_LOAD_TIMEOUT_MS),
        getTdClient().send(fullRequest, ACCOUNT_LOAD_TIMEOUT_MS)
      ]);
      if (sequence !== this.loadSequence) {
        return;
      }
      const user = values[0];
      const fullInfo = values[1];
      this.firstName = (user['first_name'] as string | undefined) ?? '';
      this.lastName = (user['last_name'] as string | undefined) ?? '';
      this.phone = (user['phone_number'] as string | undefined) ?? '';
      const usernames = user['usernames'] as TdObject | undefined;
      const activeUsernames = usernames !== undefined
        ? ((usernames['active_usernames'] as string[] | undefined) ?? []) : [];
      this.username = activeUsernames.length > 0 ? activeUsernames[0] : '';
      const bioFormatted = fullInfo['bio'] as TdObject | undefined;
      this.bio = bioFormatted !== undefined
        ? ((bioFormatted['text'] as string | undefined) ?? '') : '';
      const birthdate = fullInfo['birthdate'] as TdObject | undefined;
      if (birthdate !== undefined) {
        const day = (birthdate['day'] as number | undefined) ?? 0;
        const month = (birthdate['month'] as number | undefined) ?? 0;
        // A birthday has no year, but Intl needs a Date; the year is arbitrary
        // and never shown. Formatting this by hand would give "3月5日" in
        // English too — the month/day order itself is locale business.
        this.birthday = day > 0 && month > 0
          ? monthDay(new Date(2000, month - 1, day)) : '';
      } else {
        this.birthday = '';
      }
      this.origFirst = this.firstName;
      this.origLast = this.lastName;
      this.origBio = this.bio;
      this.loading = false;
      this.stopSkeletonPulse();
    } catch (caught) {
      if (sequence !== this.loadSequence) {
        return;
      }
      const error = caught as Error;
      logE(`AccountEditPage.loadProfile failed: ${error.message}`);
      this.loading = false;
      this.loadError = str('settings_profile_failed');
      this.stopSkeletonPulse();
    }
  }

  private startSkeletonPulse(): void {
    if (this.skeletonTimer !== -1 ||
      powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 1) === 0) {
      return;
    }
    this.skeletonTimer = setInterval((): void => {
      this.skeletonBright = !this.skeletonBright;
    }, 680);
  }

  private stopSkeletonPulse(): void {
    if (this.skeletonTimer !== -1) {
      clearInterval(this.skeletonTimer);
      this.skeletonTimer = -1;
    }
    this.skeletonBright = false;
  }

  private hasUnsavedChanges(): boolean {
    return this.firstName !== this.origFirst ||
      this.lastName !== this.origLast ||
      this.bio !== this.origBio;
  }

  // 【和其它几个设置子页不一样，leavingPage 这一套要留着】
  // 别的页面（PowerUsagePage / LanguagePage / ChatSettingsPage /
  // InteractionSettingsPage）里的同名字段只是"连点两下返回"的防抖，全文件没有
  // 渲染读取，迁移时整块删掉了。本页的 leavingPage 是**渲染依赖**：
  //   · loadErrorState() 的「重新加载」按钮 .enabled(!this.leavingPage)；
  //   · 标题栏右上角保存键 saveMenuItem() 的 isEnabled 里有 !this.leavingPage；
  //   · requestBack() / save() 两个入口的守卫也读它。
  // 语义是「这一次离场已经发起了，别再让用户按东西」，和栈深没关系，所以迁移
  // 不影响它——字段、500ms 定时器、aboutToDisappear 的清理全部原样保留。
  //
  // 真正要改的只有最后一句离场动作：迁移前是 router.back()，那在 NavDestination
  // 上是**错的**——它弹的是 router 页栈，而本页已不在那条栈上，弹掉的会是 Index，
  // 现象是直接退到桌面（HdsSubDestination 文件头记了同一条实测）。改成出
  // Navigation 栈。
  private leavePage(): void {
    if (this.leavingPage) {
      return;
    }
    this.leavingPage = true;
    this.leaveTimer = setTimeout((): void => {
      this.leaveTimer = -1;
      this.leavingPage = false;
    }, 500);
    this.popSelf();
  }

  // 出栈。**取的是设置页签的栈**，不是随便哪个栈：本页只有三个入口
  //（SettingsPage 的「账号」条目、SettingsPage 头部头像、MyProfilePage 的
  // 「编辑信息」），三个都走 navigateToSetting()，推的都是 'settings' 这条栈。
  //
  // 为什么不像 ArchivePage 那样用 onReady(ctx.pathStack) 拿：那个回调挂在
  // HdsNavDestination 上，而本页并不自己写 HdsNavDestination——它在外壳
  // HdsSubDestination 里，onReady 拿到的栈存在外壳的私有字段上，本页够不着。
  // 外壳的默认 onBack 已经是正确的出栈，但本页必须传自己的 onBack（未保存确认
  // 框要先弹），所以只能自己找一次栈。
  //
  // 栈缺失时**故意不回退到 router.back()**：那正是会把应用退到桌面的那条路，
  // 返回键"什么都不做 + 一条日志"远比退到桌面好。形状与 HdsSubDestination.popSelf
  // 一致。
  private popSelf(): void {
    const stack: NavStackLike | undefined = stackOf('settings');
    if (stack === undefined) {
      logE('AccountEditPage.popSelf: settings stack not registered, back ignored');
      return;
    }
    stack.pop();
  }

  private requestBack(): void {
    if (this.saving || this.leavingPage || this.discardDialogOpen) {
      return;
    }
    if (!this.hasUnsavedChanges()) {
      this.leavePage();
      return;
    }
    this.discardDialogOpen = true;
    promptAction.showDialog({
      title: $r('app.string.ae_discard_title'),
      message: $r('app.string.ae_discard_body'),
      buttons: [
        { text: $r('app.string.ae_keep_editing'), color: COLOR_TEXT_SECONDARY as string },
        { text: $r('app.string.ae_discard'), color: '#E64646' }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse): void => {
      this.discardDialogOpen = false;
      if (result.index === 1) {
        this.leavePage();
      }
    }).catch((): void => {
      this.discardDialogOpen = false;
    });
  }

  @Styles
  headerActionNormalStyle() {
    .backgroundColor(Color.Transparent)
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  headerActionPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.72)
    .scale({ x: 0.92, y: 0.92 })
  }

  @Styles
  retryActionNormalStyle() {
    .backgroundColor('#143478F6')
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  retryActionPressedStyle() {
    .backgroundColor('#243478F6')
    .opacity(0.72)
    .scale({ x: 0.96, y: 0.96 })
  }

  private save(): void {
    if (this.loading || this.loadError !== '' || this.saving ||
      this.leavingPage || this.discardDialogOpen) {
      return;
    }
    if (this.firstName.trim() === '') {
      promptAction.showToast({ message: $r('app.string.ae_name_required'), duration: 1500 });
      return;
    }
    this.saveError = '';
    this.saving = true;
    const jobs: Promise<TdObject>[] = [];
    if (this.firstName !== this.origFirst || this.lastName !== this.origLast) {
      const req: TdRequest = { '@type': 'setName' };
      req['first_name'] = this.firstName.trim();
      req['last_name'] = this.lastName.trim();
      jobs.push(getTdClient().send(req));
    }
    if (this.bio !== this.origBio) {
      const req: TdRequest = { '@type': 'setBio' };
      req['bio'] = this.bio;
      jobs.push(getTdClient().send(req));
    }
    if (jobs.length === 0) {
      this.saving = false;
      this.leavePage();
      return;
    }
    Promise.all(jobs).then(() => {
      this.saving = false;
      promptAction.showToast({ message: $r('app.string.saved'), duration: 1200 });
      this.origFirst = this.firstName;
      this.origLast = this.lastName;
      this.origBio = this.bio;
      this.leavePage();
    }).catch((e: TdError) => {
      this.saving = false;
      this.saveError = str('ae_save_partial');
      logE(`AccountEditPage.save failed: ${e.message}`);
      promptAction.showToast({ message: $r('app.string.ae_save_failed'), duration: 2000 });
    });
  }

  // 退出登录放在账号页最底部。此前它藏在设置页右上角一个无标签的「⋯」图标
  // 后面、再进一层弹窗，用户根本找不到 —— 低频但关键的操作不该靠探索发现。
  private confirmLogout(): void {
    if (this.loggingOut) { return; }
    promptAction.showDialog({
      title: $r('app.string.ae_log_out'),
      message: $r('app.string.ae_log_out_confirm'),
      buttons: [
        { text: $r('app.string.cancel'), color: COLOR_TEXT_SECONDARY as string },
        { text: $r('app.string.ae_log_out_button'), color: '#E64646' }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse): void => {
      if (result.index !== 1) { return; }
      this.performLogout();
    }).catch((e: Object): void => {
      logE(`AccountEditPage.confirmLogout failed: ${JSON.stringify(e)}`);
    });
  }

  private performLogout(): void {
    this.loggingOut = true;
    // 先收起悬浮直播窗，否则它会挂在旧账号的运行时上。
    floatingLiveWindow.closeForAccountSwitch()
      .then((): Promise<void> => logoutCurrentTdAccount())
      .catch((caught: Error): void => {
        this.loggingOut = false;
        logE(`AccountEditPage.logout failed: ${caught.message}`);
        promptAction.showToast({ message: $r('app.string.ae_log_out_failed'), duration: 1800 });
      });
  }

  @Builder
  logoutCard() {
    Row({ space: 14 }) {
      Stack({ alignContent: Alignment.Center }) {
        if (this.loggingOut) {
          LoadingProgress().width(20).height(20).color('#E64646');
        } else {
          SymbolGlyph($r('sys.symbol.xmark_circle')).fontSize(20).fontColor(['#E64646']);
        }
      }
      .width(38).height(38).borderRadius(19).backgroundColor('#18E64646');
      Column({ space: 2 }) {
        Text(this.loggingOut ? $r('app.string.ae_logging_out') : $r('app.string.ae_log_out'))
          .fontSize(16).fontWeight(FontWeight.Medium).fontColor('#E64646');
        Text($r('app.string.ae_log_out_sub'))
          .fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);
    }
    .width('100%').height(64)
    .padding({ left: 12, right: 12 })
    .backgroundColor(CARD_BG).borderRadius(CARD_RADIUS)
    .margin({ top: 14 })
    .enabled(!this.loggingOut)
    .accessibilityText($r('app.string.ae_log_out_a11y'))
    .onClick((): void => { this.confirmLogout(); });
  }

  @Builder
  loadingState() {
    Column({ space: 12 }) {
      Row({ space: 14 }) {
        Column({ space: 11 }) {
          Rect({ width: 88, height: 11, radius: 5.5 }).fill($r('app.color.surface_alt'));
          Rect({ width: '82%', height: 16, radius: 8 }).fill($r('app.color.surface_alt'));
          Divider().color($r('app.color.divider')).strokeWidth(0.7);
          Rect({ width: '68%', height: 16, radius: 8 }).fill($r('app.color.surface_alt'));
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1);
        LoadingProgress().width(24).height(24).color(COLOR_PRIMARY);
      }
      .width('100%')
      .height(132)
      .padding({ left: 16, right: 16, top: 16, bottom: 16 })
      .backgroundColor(CARD_BG)
      .borderRadius(CARD_RADIUS)
      .alignItems(VerticalAlign.Center);

      Column({ space: 12 }) {
        Rect({ width: '86%', height: 16, radius: 8 }).fill($r('app.color.surface_alt'));
        Rect({ width: '46%', height: 10, radius: 5 }).fill($r('app.color.surface_alt'));
      }
      .width('100%')
      .height(86)
      .padding({ left: 16, right: 16 })
      .backgroundColor(CARD_BG)
      .borderRadius(CARD_RADIUS)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center);

      Row({ space: 10 }) {
        LoadingProgress().width(18).height(18).color(COLOR_PRIMARY);
        Text($r('app.string.ae_loading_secure'))
          .fontSize(13)
          .fontColor(COLOR_TEXT_SECONDARY);
      }
      .height(38);
    }
    .width('calc(100% - 24vp)')
    .margin({ left: 12, right: 12, top: 8 })
    .opacity(this.skeletonBright ? 0.56 : 0.92)
    .animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 640),
      curve: Curve.EaseInOut
    })
    .accessibilityText($r('app.string.settings_profile_loading'))
    .transition(TransitionEffect.OPACITY.animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 160),
      curve: Curve.EaseOut
    }));
  }

  @Builder
  loadErrorState() {
    Column({ space: 9 }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle({ width: 62, height: 62 }).fill('#18E64646');
        SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
          .fontSize(30)
          .fontColor(['#E64646']);
      }
      Text(this.loadError)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(COLOR_TEXT_PRIMARY);
      Text($r('app.string.ae_no_blank_form'))
        .fontSize(13)
        .fontColor(COLOR_TEXT_SECONDARY)
        .textAlign(TextAlign.Center);
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(15)
          .fontColor([COLOR_PRIMARY]);
        Text($r('app.string.settings_reload'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_PRIMARY);
      }
      .height(40)
      .padding({ left: 17, right: 17 })
      .margin({ top: 5 })
      .borderRadius(20)
      .stateStyles({
        normal: this.retryActionNormalStyle,
        pressed: this.retryActionPressedStyle
      })
      .enabled(!this.leavingPage)
      .accessibilityText($r('app.string.ae_reload_profile'))
      .onClick((): void => { this.loadProfile(); });
    }
    .layoutWeight(1)
    .width('calc(100% - 24vp)')
    .margin({ left: 12, right: 12, top: 8, bottom: this.bottomSafe + 24 })
    .justifyContent(FlexAlign.Center)
    .backgroundColor(CARD_BG)
    .borderRadius(CARD_RADIUS)
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.scale({ x: 0.97, y: 0.97 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
        curve: Curve.EaseOut
      }));
  }

  @Builder
  saveErrorBanner() {
    Row({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(20)
        .fontColor(['#E64646']);
      Column({ space: 2 }) {
        Text($r('app.string.save_failed'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_PRIMARY);
        Text(this.saveError)
          .fontSize(12)
          .fontColor(COLOR_TEXT_SECONDARY);
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);
      Row({ space: 4 }) {
        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(13)
          .fontColor([COLOR_PRIMARY]);
        Text($r('app.string.settings_retry'))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_PRIMARY);
      }
      .height(34)
      .padding({ left: 10, right: 10 })
      .borderRadius(17)
      .stateStyles({
        normal: this.retryActionNormalStyle,
        pressed: this.retryActionPressedStyle
      })
      .enabled(!this.saving)
      .accessibilityText($r('app.string.ae_retry_save'))
      .onClick((): void => { this.save(); });
    }
    .width('100%')
    .height(66)
    .padding({ left: 13, right: 10 })
    .backgroundColor('#10E64646')
    .border({ width: 0.7, color: '#30E64646' })
    .borderRadius(CARD_RADIUS)
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: -5 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
        curve: Curve.EaseOut
      }));
  }

  @Builder
  sectionLabel(label: ResourceStr) {
    Text(label).fontSize(15).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY)
      .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 2 });
  }

  // NOTE: @Builder value parameters are captured at first render and are NOT
  // re-evaluated when @State changes. phone/username/birthday resolve
  // asynchronously, so each row inlines its markup and reads state directly —
  // passing the value through a builder parameter would freeze it at $r('app.string.not_set').
  @Builder
  phoneRow() {
    Row({ space: 14 }) {
      Stack() {
        SymbolGlyph($r('sys.symbol.phone_fill')).fontSize(18).fontColor([Color.White]);
      }
      .width(34).height(34).borderRadius(9).backgroundColor('#34C759');
      Column({ space: 2 }) {
        Text(this.phone !== '' ? `+${this.phone}` : $r('app.string.not_set')).fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
        Text($r('app.string.ct_phone')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
      }.alignItems(HorizontalAlign.Start).layoutWeight(1);
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(15).fontColor([COLOR_TEXT_SECONDARY]);
    }
    .width('100%').padding({ left: 16, right: 16, top: 9, bottom: 9 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      promptAction.showToast({ message: $r('app.string.ae_phone_change_unsupported'), duration: 2000 });
    });
  }

  @Builder
  usernameRow() {
    Row({ space: 14 }) {
      Stack() {
        SymbolGlyph($r('sys.symbol.at')).fontSize(18).fontColor([Color.White]);
      }
      .width(34).height(34).borderRadius(9).backgroundColor('#FF9500');
      Column({ space: 2 }) {
        Text(this.username !== '' ? `@${this.username}` : $r('app.string.not_set')).fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
        Text($r('app.string.ae_username_tap')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
      }.alignItems(HorizontalAlign.Start).layoutWeight(1);
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(15).fontColor([COLOR_TEXT_SECONDARY]);
    }
    .width('100%').padding({ left: 16, right: 16, top: 9, bottom: 9 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.editUsername = this.username;
      this.usernameCtrl.open();
    });
  }

  @Builder
  birthdayRow() {
    Row({ space: 14 }) {
      Stack() {
        SymbolGlyph($r('sys.symbol.cake')).fontSize(18).fontColor([Color.White]);
      }
      .width(34).height(34).borderRadius(9).backgroundColor('#3478F6');
      Column({ space: 2 }) {
        Text(this.birthday !== '' ? this.birthday : $r('app.string.not_set')).fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
        Text($r('app.string.ae_birthday_tap')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
      }.alignItems(HorizontalAlign.Start).layoutWeight(1);
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(15).fontColor([COLOR_TEXT_SECONDARY]);
    }
    .width('100%').padding({ left: 16, right: 16, top: 9, bottom: 9 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => { this.pickBirthday(); });
  }

  // --- username edit ---
  @State editUsername: string = '';
  private usernameCtrl: CustomDialogController = new CustomDialogController({
    builder: UsernameDialog({
      value: this.editUsername,
      onSave: (v: string): void => { this.saveUsername(v); }
    }),
    alignment: DialogAlignment.Center,
    autoCancel: true
  });

  private saveUsername(v: string): void {
    const name = v.trim().replace('@', '');
    if (name === this.username) {
      return;
    }
    const req: TdRequest = { '@type': 'setUsername' };
    req['username'] = name;
    getTdClient().send(req).then(() => {
      this.username = name;
      promptAction.showToast({ message: $r('app.string.ae_username_updated'), duration: 1500 });
    }).catch((e: TdError) => {
      const msg = e.message.includes('OCCUPIED') ? $r('app.string.ae_username_taken')
        : (e.message.includes('INVALID') ? $r('app.string.ae_username_invalid') : str('ae_change_failed', e.message));
      promptAction.showToast({ message: msg, duration: 2200 });
    });
  }

  // --- birthday edit ---
  private pickBirthday(): void {
    DatePickerDialog.show({
      start: new Date('1900-01-01'),
      end: new Date(),
      selected: new Date('2000-01-01'),
      onDateAccept: (d: Date) => {
        const req: TdRequest = { '@type': 'setBirthdate' };
        const bd: TdObject = { '@type': 'birthdate' };
        bd['day'] = d.getDate();
        bd['month'] = d.getMonth() + 1;
        bd['year'] = d.getFullYear();
        req['birthdate'] = bd;
        getTdClient().send(req).then(() => {
          this.birthday = monthDay(d);
          promptAction.showToast({ message: $r('app.string.ae_birthday_updated'), duration: 1500 });
        }).catch((e: TdError) => {
          promptAction.showToast({ message: str('ae_change_failed', e.message), duration: 2000 });
        });
      }
    });
  }

  // 标题栏右上角的保存键。禁用条件照搬原来那个对勾。
  private saveMenuItem(): HdsNavigationMenuItemOptions {
    const icon: HdsNavigationIconOptions = {
      icon: $r('sys.symbol.checkmark'),
      label: $r('app.string.ae_save_profile'),
      isEnabled: !this.loading && this.loadError === '' &&
        !this.leavingPage && !this.discardDialogOpen,
      action: (): void => { this.save(); }
    };
    return { content: icon };
  }

  build() {
    Column() {
    // 内联顶栏搬进标题栏：返回走 requestBack()（它管着未保存的确认），
    // 保存变成标题栏右上角的对勾。保存中时对勾换成副标题「保存中」——HDS 的
    // 菜单项只能放图标，放不下 LoadingProgress。
    HdsSubDestination({
      title: $r('app.string.settings_account'),
      subTitle: this.saving ? $r('app.string.saving') : '',
      pageBackground: $r('app.color.page_bg'),
      scroller: this.hdsScroller,
      onBack: (): void => { this.requestBack(); },
      menuItems: this.saving ? [] : [this.saveMenuItem()]
    }) {
      Column() {

      if (this.loading) {
        Column() {
          this.loadingState();
        }
        .layoutWeight(1)
        .width('100%');
      } else if (this.loadError !== '') {
        this.loadErrorState();
      } else {
        Scroll(this.hdsScroller) {
          Column({ space: 0 }) {
            if (this.saveError !== '') {
              Column() {
                this.saveErrorBanner();
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 8 });
            }

            // 你的姓名
            Column() {
              this.sectionLabel($r('app.string.ae_your_name'));
              TextInput({ text: this.firstName, placeholder: $r('app.string.ct_first_name_short') })
                .fontSize(17).backgroundColor(Color.Transparent)
                .padding({ left: 16, right: 16, top: 10, bottom: 10 })
                .onChange((v: string) => {
                  this.firstName = v;
                  this.saveError = '';
                });
              Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16, right: 16 });
              TextInput({ text: this.lastName, placeholder: $r('app.string.ct_last_name_short') })
                .fontSize(17).backgroundColor(Color.Transparent)
                .padding({ left: 16, right: 16, top: 10, bottom: 10 })
                .onChange((v: string) => {
                  this.lastName = v;
                  this.saveError = '';
                });
            }
            .width('100%').backgroundColor(CARD_BG).borderRadius(CARD_RADIUS)
            .padding({ bottom: 4 })
            .margin({ top: 8 });

            // 个人简介
            Column() {
              Row() {
                TextInput({ text: this.bio, placeholder: $r('app.string.ae_bio') })
                  .fontSize(17).backgroundColor(Color.Transparent)
                  .padding({ left: 16, right: 8, top: 12, bottom: 12 })
                  .maxLength(BIO_MAX)
                  .layoutWeight(1)
                  .onChange((v: string) => {
                    this.bio = v;
                    this.saveError = '';
                  });
                Text(`${BIO_MAX - this.bio.length}`)
                  .fontSize(15).fontColor(COLOR_TEXT_SECONDARY).margin({ right: 16 });
              }.width('100%').alignItems(VerticalAlign.Center);
            }
            .width('100%').backgroundColor(CARD_BG).borderRadius(CARD_RADIUS)
            .margin({ top: 14 });
            Text($r('app.string.ae_bio_hint'))
              .fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
              .width('100%').padding({ left: 24, right: 24, top: 6 });

            // 个人信息（只读）
            Column() {
              this.sectionLabel($r('app.string.ae_personal_info'));
              this.phoneRow();
              Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 64 });
              this.usernameRow();
              Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 64 });
              this.birthdayRow();
            }
            .width('100%').backgroundColor(CARD_BG).borderRadius(CARD_RADIUS)
            .padding({ bottom: 4 })
            .margin({ top: 14 });
            this.logoutCard();
          }
          .width('100%')
          .padding({ left: 12, right: 12, bottom: this.bottomSafe + 24 });
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Off)
        // 不裁剪，内容才能穿到标题栏底下。
        .clip(false);
      }
      }.width('100%').height('100%');
    }
    }.width('100%').height('100%');
  }
}


// Simple username editor dialog: @-prefixed input + 取消/保存.
@CustomDialog
struct UsernameDialog {
  // 材质档位（厚度/光感）改变时重绘。overlayMaterial 是 util，订阅不了
  // AppStorage，只能由调用方订阅，同 LANGUAGE_EPOCH 的做法。
  @StorageProp(MATERIAL_EPOCH) private materialEpoch: number = 0;
  controller?: CustomDialogController;
  value: string = '';
  onSave: (v: string) => void = (): void => {};
  @State input: string = '';

  aboutToAppear(): void {
    this.input = this.value;
  }

  build() {
    Column({ space: 16 }) {
      Text($r('app.string.ae_change_username')).fontSize(17).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
      Row({ space: 4 }) {
        Text('@').fontSize(17).fontColor(COLOR_TEXT_SECONDARY);
        TextInput({ text: this.input, placeholder: $r('app.string.ae_username') })
          .fontSize(17).layoutWeight(1)
          .backgroundColor(Color.Transparent).padding(0)
          .onChange((v: string) => { this.input = v; });
      }
      .width('100%').padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .backgroundColor($r('app.color.surface_alt')).borderRadius(10)
      .alignItems(VerticalAlign.Center);
      Text($r('app.string.ae_username_rule'))
        .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).width('100%');
      Row({ space: 12 }) {
        Blank().layoutWeight(1);
        Text($r('app.string.cancel')).fontSize(16).fontColor(COLOR_TEXT_SECONDARY)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .onClick(() => { this.controller?.close(); });
        Text($r('app.string.save')).fontSize(16).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .onClick(() => {
            this.controller?.close();
            this.onSave(this.input);
          });
      }.width('100%');
    }
    .padding(22)
    .backgroundColor(overlayGlassFill('dialog', $r('app.color.surface')))
    .borderRadius(16)
    .width('86%')
    .backdropBlur(overlayBackdropBlur('dialog'))
    .attributeModifier(materialModifier('dialog'));
  }
}
