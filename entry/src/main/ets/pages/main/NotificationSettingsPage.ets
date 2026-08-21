import { router, promptAction } from '@kit.ArkUI';
import { TdError } from '../../tdkit/TdTypes';
import {
  SCOPE_CHANNEL, SCOPE_GROUP, SCOPE_PRIVATE, ScopeSettings, defaultScopeSettings,
  getScopeSettings, resetAllNotificationSettings, setScopeSettings
} from '../../store/NotificationApi';
import {
  COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';
import {
  KEY_NOTIFY_PRIVATE, KEY_NOTIFY_GROUP, KEY_NOTIFY_CHANNEL, KEY_WEBPUSH_ENABLED, setBoolean
} from '../../store/AppSettings';
import { str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { logE } from '../../util/log';
import { HdsSubDestination } from '../common/HdsSubDestination';

const CARD_RADIUS: number = 14;

// 路由表（router_map.json）的 buildFunction 指向这里。系统在跳转时动态加载本模块
// 并调用它，页面因此不再进 main_pages.json——一个页面不能同时是 router 页和
// NavDestination。形状与试点的 PowerUsagePageBuilder 一致。
@Builder
export function NotificationSettingsPageBuilder(): void {
  NotificationSettingsPage();
}

@Component
export struct NotificationSettingsPage {
  private hdsScroller: Scroller = new Scroller();
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State privateSettings: ScopeSettings = defaultScopeSettings();
  @State groupSettings: ScopeSettings = defaultScopeSettings();
  @State channelSettings: ScopeSettings = defaultScopeSettings();
  @State loadState: string = 'loading';
  @StorageProp(KEY_NOTIFY_PRIVATE) notifyPrivate: boolean = true;
  @StorageProp(KEY_NOTIFY_GROUP) notifyGroup: boolean = true;
  @StorageProp(KEY_NOTIFY_CHANNEL) notifyChannel: boolean = true;
  @StorageProp(KEY_WEBPUSH_ENABLED) webPushEnabled: boolean = false;
  private active: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    this.load();
  }

  aboutToDisappear(): void {
    this.active = false;
  }

  private load(): void {
    this.loadState = 'loading';
    Promise.all([
      getScopeSettings(SCOPE_PRIVATE), getScopeSettings(SCOPE_GROUP),
      getScopeSettings(SCOPE_CHANNEL)
    ]).then((all: ScopeSettings[]): void => {
      if (!this.active) { return; }
      this.privateSettings = all[0];
      this.groupSettings = all[1];
      this.channelSettings = all[2];
      this.loadState = 'ready';
    }).catch((error: TdError): void => {
      if (!this.active) { return; }
      logE(`NotificationSettingsPage.load failed: ${error.message}`);
      this.loadState = 'error';
    });
  }

  private settingsOf(scope: string): ScopeSettings {
    if (scope === SCOPE_GROUP) { return this.groupSettings; }
    if (scope === SCOPE_CHANNEL) { return this.channelSettings; }
    return this.privateSettings;
  }

  private applyLocal(scope: string, value: ScopeSettings): void {
    if (scope === SCOPE_GROUP) { this.groupSettings = value; }
    else if (scope === SCOPE_CHANNEL) { this.channelSettings = value; }
    else { this.privateSettings = value; }
  }

  // TDLib replaces the whole scope object, so每次都发送完整设置并在失败时回滚。
  private update(scope: string, key: string, value: boolean): void {
    const current = this.settingsOf(scope);
    const next: ScopeSettings = {
      muted: key === 'muted' ? value : current.muted,
      showPreview: key === 'showPreview' ? value : current.showPreview,
      disablePinned: key === 'disablePinned' ? value : current.disablePinned,
      disableMentions: key === 'disableMentions' ? value : current.disableMentions
    };
    this.applyLocal(scope, next);
    setScopeSettings(scope, next).catch((error: TdError): void => {
      logE(`NotificationSettingsPage.update failed: ${error.message}`);
      this.applyLocal(scope, current);
      promptAction.showToast({ message: $r('app.string.ns_update_failed'), duration: 1600 });
    });
  }

  private resetAll(): void {
    promptAction.showDialog({
      title: $r('app.string.ns_reset'),
      message: $r('app.string.ns_reset_confirm'),
      buttons: [
        { text: $r('app.string.cancel'), color: '#8E8E93' },
        { text: $r('app.string.restore'), color: '#E5484D' }
      ]
    }).then((result): void => {
      if (result.index !== 1) { return; }
      resetAllNotificationSettings().then((): void => {
        promptAction.showToast({ message: $r('app.string.ns_reset_done'), duration: 1500 });
        this.load();
      }).catch((): void => {
        promptAction.showToast({ message: $r('app.string.restore_failed_retry'), duration: 1600 });
      });
    }).catch((): void => {});
  }

  @Builder
  switchRow(label: string, value: boolean, onChange: (next: boolean) => void) {
    Row() {
      Text(label).fontSize(15).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
      Toggle({ type: ToggleType.Switch, isOn: value }).selectedColor(COLOR_PRIMARY)
        .onChange(onChange);
    }.width('100%').height(48).padding({ left: 14, right: 12 });
  }

  // 带副标题的开关行：本机/账号两个开关长得一样但作用域完全不同，
  // 挨在一起时必须一眼能分辨，否则用户不知道自己关的是哪一个。
  @Builder
  switchRowWithHint(label: string, hint: string, value: boolean, onChange: (next: boolean) => void) {
    Row() {
      Column({ space: 2 }) {
        Text(label).fontSize(15).fontColor(COLOR_TEXT_PRIMARY);
        Text(hint).fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
      }.alignItems(HorizontalAlign.Start).layoutWeight(1);
      Toggle({ type: ToggleType.Switch, isOn: value }).selectedColor(COLOR_PRIMARY)
        .onChange(onChange);
    }.width('100%').height(56).padding({ left: 14, right: 12 });
  }

  // 一类会话一张卡，本机开关和账号级设置放在一起 —— 之前拆成"本机通知"独立
  // 一张卡 + 三张作用域卡，等于把"私聊/群组/频道"列了两遍，而同一类型的两个
  // 开关反而隔得很远，看不出它们的关系。
  //
  // 这三个 xxxCard 是无参 @Builder：@StorageProp 的读取必须发生在无参 builder
  // 里，值参数不会随数据变化重新求值（本页 muteButton 一类的坑仓库里已有记录）。
  @Builder
  privateCard() {
    this.scopeCard($r('app.string.ns_private'), SCOPE_PRIVATE, this.privateSettings, false,
      this.notifyPrivate, (next: boolean): void => setBoolean(KEY_NOTIFY_PRIVATE, next));
  }

  @Builder
  groupCard() {
    this.scopeCard($r('app.string.gn_group'), SCOPE_GROUP, this.groupSettings, true,
      this.notifyGroup, (next: boolean): void => setBoolean(KEY_NOTIFY_GROUP, next));
  }

  @Builder
  channelCard() {
    this.scopeCard($r('app.string.gn_channel'), SCOPE_CHANNEL, this.channelSettings, true,
      this.notifyChannel, (next: boolean): void => setBoolean(KEY_NOTIFY_CHANNEL, next));
  }

  @Builder
  scopeCard(title: ResourceStr, scope: string, settings: ScopeSettings, hasMentions: boolean,
    localOn: boolean, onLocalChange: (next: boolean) => void) {
    Column() {
      Text(title).fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
        .width('100%').padding({ left: 14, top: 12, bottom: 4 });
      this.switchRowWithHint(str('ns_device_local'), str('ns_device_local_sub'),
        localOn, onLocalChange);
      this.switchRowWithHint(str('ns_receive'), str('ns_receive_sub'),
        !settings.muted, (next: boolean): void => this.update(scope, 'muted', !next));
      // 本机已关掉时，账号级的细项对这台设备不起作用，收起来避免误以为生效。
      if (localOn) {
        this.switchRow(str('ns_preview'), settings.showPreview,
          (next: boolean): void => this.update(scope, 'showPreview', next));
        if (hasMentions) {
          this.switchRow(str('ns_pinned'), !settings.disablePinned,
            (next: boolean): void => this.update(scope, 'disablePinned', !next));
          this.switchRow(str('ns_mentions'), !settings.disableMentions,
            (next: boolean): void => this.update(scope, 'disableMentions', !next));
        }
      }
    }
    .width('100%').padding({ bottom: 6 })
    .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
  }

  build() {
    Column() {
    // 内联的顶栏搬进标题栏了。
    HdsSubDestination({ title: $r('app.string.settings_notifications'), pageBackground: COLOR_PAGE_BG, scroller: this.hdsScroller }) {
      Column() {
      if (this.loadState === 'loading') {
        Column({ space: 9 }) {
          LoadingProgress().width(32).height(32).color(COLOR_PRIMARY);
          Text($r('app.string.gn_loading')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else if (this.loadState === 'error') {
        Column({ space: 10 }) {
          Text($r('app.string.load_failed')).fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
          Button($r('app.string.settings_reload')).onClick((): void => this.load());
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else {
        Scroll(this.hdsScroller) {
          Column({ space: 12 }) {
            this.privateCard();
            this.groupCard();
            this.channelCard();
            Row({ space: 10 }) {
              Column({ space: 2 }) {
                Text($r('app.string.gn_title')).fontSize(15).fontColor(COLOR_TEXT_PRIMARY);
                Text($r('app.string.ns_per_chat_sub'))
                  .fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
              }.alignItems(HorizontalAlign.Start).layoutWeight(1);
              SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16)
                .fontColor([COLOR_TEXT_SECONDARY]);
            }
            .width('100%').height(58).padding({ left: 14, right: 14 })
            .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS)
            .onClick((): void => {
              router.pushUrl({ url: 'pages/main/GroupNotificationsPage' }).catch((e: Error): void => {
                logE(`NotificationSettingsPage.openGroupNotifications failed: ${e.message}`);
              });
            });
            Row({ space: 10 }) {
              Column({ space: 2 }) {
                Text($r('app.string.ns_custom_push')).fontSize(15).fontColor(COLOR_TEXT_PRIMARY);
                Text(this.webPushEnabled ? $r('app.string.enabled') : $r('app.string.disabled'))
                  .fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
              }.alignItems(HorizontalAlign.Start).layoutWeight(1);
              SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16)
                .fontColor([COLOR_TEXT_SECONDARY]);
            }
            .width('100%').height(58).padding({ left: 14, right: 14 })
            .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS)
            .onClick((): void => {
              router.pushUrl({ url: 'pages/main/WebPushPage' }).catch((e: Error): void => {
                logE(`NotificationSettingsPage.openWebPush failed: ${e.message}`);
              });
            });
            Row({ space: 10 }) {
              SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(17).fontColor(['#E5484D']);
              Text($r('app.string.ns_reset')).fontSize(15).fontColor('#E5484D').layoutWeight(1);
            }
            .width('100%').height(48).padding({ left: 14, right: 14 })
            .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS)
            .onClick((): void => this.resetAll());
            Text($r('app.string.ns_priority_note'))
              .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).lineHeight(18).width('100%');
          }.width('100%').padding({ left: 12, right: 12, bottom: this.bottomSafe + 24 });
        }
        .layoutWeight(1).width('100%').scrollBar(BarState.Off)
        // 不裁剪，内容才能穿到标题栏底下。
        .clip(false);
      }
      }.width('100%').height('100%');
    }
    }.width('100%').height('100%');
  }
}
