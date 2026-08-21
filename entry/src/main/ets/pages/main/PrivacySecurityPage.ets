import { router, promptAction } from '@kit.ArkUI';
import { getTdClient } from '../../tdkit/Globals';
import { TdError, TdObject } from '../../tdkit/TdTypes';
import {
  ArchiveChatSettings, NewChatPrivacySettings, PrivacyValue,
  ruleLabel, setAccountTtlDays, setArchiveSettings, setAutoDeleteSeconds,
  setBoolOption, setNewChatPrivacy, setReadDatePrivacy
} from '../../store/PrivacyApi';
import {
  OPT_DISABLE_TOP_CHATS, OPT_IGNORE_SENSITIVE, PrivacyLoadState, PrivacyStore
} from '../../store/PrivacyStore';
import { PrivacyRuleParams } from './PrivacyRulePage';
import {
  COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE,
  COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';
import { plural, str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { overlayMaterial, MATERIAL_EPOCH } from '../../util/overlayMaterial';
import { logE } from '../../util/log';

const CARD_RADIUS: number = 16;
const COLOR_WARNING: string = '#D98914';
const COLOR_DANGER: string = '#E5484D';

interface Choice {
  label: string;
  value: number;
}

interface RuleRow {
  setting: string;
  title: string;
  hint: string;
  group: string;
  premiumOnly: boolean;
  allowNobody: boolean;
}

// Functions, not const arrays: the labels come from str(), which resolves
// when called. A module-level array would be built the first time this module
// is imported — before the string source is installed — and would keep that
// language for the rest of the process.
function autoDeleteChoices(): Choice[] {
  return [
  { label: str('ps_off'), value: 0 },
  { label: str('ps_1_day'), value: 86400 },
  { label: str('ps_1_week'), value: 604800 },
  { label: str('ps_1_month'), value: 2678400 }
  ];
}

function accountTtlChoices(): Choice[] {
  return [
  { label: str('ps_1_month'), value: 30 },
  { label: str('ps_3_months'), value: 90 },
  { label: str('ps_6_months'), value: 180 },
  { label: str('ps_12_months'), value: 365 },
  { label: str('ps_18_months'), value: 548 },
  { label: str('ps_24_months'), value: 730 }
  ];
}

function ruleRows(): RuleRow[] {
  return [
  { setting: 'userPrivacySettingShowPhoneNumber', title: str('ct_phone'), group: 'personal',
    hint: str('ps_phone_hint'), premiumOnly: false, allowNobody: true },
  { setting: 'userPrivacySettingShowStatus', title: str('ps_last_seen'), group: 'personal',
    hint: str('ps_last_seen_hint'), premiumOnly: false, allowNobody: true },
  { setting: 'userPrivacySettingShowProfilePhoto', title: str('ps_photo'), group: 'personal',
    hint: str('ps_photo_hint'), premiumOnly: false, allowNobody: true },
  { setting: 'userPrivacySettingShowBio', title: str('ps_bio'), group: 'personal',
    hint: str('ps_bio_hint'), premiumOnly: false, allowNobody: true },
  { setting: 'userPrivacySettingShowBirthdate', title: str('ps_birthdate'), group: 'personal',
    hint: str('ps_birthdate_hint'), premiumOnly: false, allowNobody: true },
  { setting: 'userPrivacySettingShowProfileAudio', title: str('ps_profile_audio'), group: 'personal',
    hint: str('ps_profile_audio_hint'), premiumOnly: false, allowNobody: true },
  { setting: 'userPrivacySettingShowLinkInForwardedMessages', title: str('ps_forward_link'), group: 'personal',
    hint: str('ps_forward_link_hint'), premiumOnly: false, allowNobody: true },
  { setting: 'userPrivacySettingAllowChatInvites', title: str('ps_chat_invites'), group: 'interaction',
    hint: str('ps_chat_invites_hint'), premiumOnly: false, allowNobody: true },
  { setting: 'userPrivacySettingAllowCalls', title: str('ps_calls'), group: 'interaction',
    hint: str('ps_calls_hint'), premiumOnly: false, allowNobody: true },
  { setting: 'userPrivacySettingAllowPeerToPeerCalls', title: str('ps_p2p'), group: 'interaction',
    hint: str('ps_p2p_hint'), premiumOnly: false, allowNobody: true },
  { setting: 'userPrivacySettingAllowPrivateVoiceAndVideoNoteMessages', title: str('ps_voice_video'), group: 'interaction',
    hint: str('ps_voice_video_hint'), premiumOnly: true, allowNobody: true },
  { setting: 'userPrivacySettingAllowFindingByPhoneNumber', title: str('ps_find_by_phone'), group: 'interaction',
    hint: str('ps_find_by_phone_hint'),
    premiumOnly: false, allowNobody: false }
  ];
}

@Entry
@Component
struct PrivacySecurityPage {
  // 材质档位（厚度/光感）改变时重绘。overlayMaterial 是 util，订阅不了
  // AppStorage，只能由调用方订阅，同 LANGUAGE_EPOCH 的做法。
  @StorageProp(MATERIAL_EPOCH) private materialEpoch: number = 0;
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State loadState: PrivacyLoadState = 'loading';
  @State refreshing: boolean = false;
  @State syncError: string = '';
  @State rules: Map<string, PrivacyValue> = new Map();
  @State passwordState: TdObject | null = null;
  @State autoDelete: number = -1;
  @State blocked: number = -1;
  @State sessions: number = -1;
  @State websites: number = -1;
  @State accountTtl: number = -1;
  @State archiveSettings: ArchiveChatSettings | null = null;
  @State readDate: boolean | null = null;
  @State newChatPrivacy: NewChatPrivacySettings | null = null;
  @State suggestFrequent: boolean | null = null;
  @State canArchiveUnknown: boolean = false;
  @State canSetNewChatPrivacy: boolean = false;
  @State canIgnoreSensitive: boolean = false;
  @State ignoreSensitive: boolean | null = null;
  @State isPremium: boolean = false;
  @State actionKey: string = '';
  @State pressedKey: string = '';
  private store: PrivacyStore | null = null;
  private unsubscribe: (() => void) | null = null;
  private active: boolean = false;
  private navigationLocked: boolean = false;

  @Styles
  rowNormalStyle() {
    .backgroundColor(Color.Transparent)
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  rowPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.82)
    .scale({ x: 0.992, y: 0.97 })
  }

  aboutToAppear(): void {
    this.active = true;
    this.navigationLocked = false;
    const settings = ruleRows().map((row: RuleRow): string => row.setting);
    const store = new PrivacyStore(getTdClient(), settings);
    this.store = store;
    this.unsubscribe = store.subscribe((): void => { this.sync(store); });
    store.open();
  }

  aboutToDisappear(): void {
    this.active = false;
    if (this.unsubscribe !== null) { this.unsubscribe(); this.unsubscribe = null; }
    if (this.store !== null) { this.store.close(); this.store = null; }
    this.actionKey = '';
    this.pressedKey = '';
  }

  private sync(store: PrivacyStore): void {
    this.loadState = store.loadState;
    this.refreshing = store.refreshing;
    this.syncError = store.syncError;
    this.rules = new Map(store.rules);
    this.passwordState = store.passwordState;
    this.autoDelete = store.autoDeleteSeconds;
    this.blocked = store.blockedCount;
    this.sessions = store.sessionCount;
    this.websites = store.websiteCount;
    this.accountTtl = store.accountTtlDays;
    this.archiveSettings = store.archiveSettings;
    this.readDate = store.readDate;
    this.newChatPrivacy = store.newChatPrivacy;
    this.suggestFrequent = store.suggestFrequent;
    this.canArchiveUnknown = store.canArchiveUnknown;
    this.canSetNewChatPrivacy = store.canSetNewChatPrivacy;
    this.canIgnoreSensitive = store.canIgnoreSensitive;
    this.ignoreSensitive = store.ignoreSensitive;
    this.isPremium = store.isPremium;
  }

  private route(url: string, params?: Object): void {
    if (this.navigationLocked || this.actionKey !== '') { return; }
    this.navigationLocked = true;
    const work = params !== undefined
      ? router.pushUrl({ url, params })
      : router.pushUrl({ url });
    work.catch((error: Error): void => {
      this.navigationLocked = false;
      logE(`PrivacySecurityPage.route failed: ${error.message}`);
      promptAction.showToast({ message: $r('app.string.page_open_failed'), duration: 1700 });
    });
    setTimeout((): void => { this.navigationLocked = false; }, 700);
  }

  private save(key: string, work: Promise<void>, rollback: () => void): void {
    if (this.actionKey !== '') { rollback(); return; }
    this.actionKey = key;
    work.then((): void => {
      if (!this.active) { return; }
      this.actionKey = '';
    }).catch((error: TdError): void => {
      logE(`PrivacySecurityPage.${key} failed: ${error.message}`);
      if (!this.active) { return; }
      rollback();
      this.actionKey = '';
      promptAction.showToast({ message: $r('app.string.ps_save_failed'), duration: 1800 });
    });
  }

  private applyAutoDelete(seconds: number): void {
    if (this.actionKey !== '' || seconds === this.autoDelete) { return; }
    const previous = this.autoDelete;
    this.autoDelete = seconds;
    this.save('auto_delete', setAutoDeleteSeconds(seconds), (): void => { this.autoDelete = previous; });
  }

  private confirmAccountTtl(days: number): void {
    if (this.actionKey !== '' || days === this.accountTtl) { return; }
    promptAction.showDialog({
      title: $r('app.string.ps_change_ttl'),
      message: str('ps_ttl_confirm', this.choiceLabel(accountTtlChoices(), days)),
      buttons: [
        { text: $r('app.string.cancel'), color: COLOR_TEXT_SECONDARY as string },
        { text: $r('app.string.confirm_change'), color: COLOR_DANGER }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse): void => {
      if (!this.active || result.index !== 1 || this.actionKey !== '') { return; }
      const previous = this.accountTtl;
      this.accountTtl = days;
      this.save('account_ttl', setAccountTtlDays(days), (): void => { this.accountTtl = previous; });
    }).catch((): void => {});
  }

  private applyArchive(value: boolean): void {
    const previous = this.archiveSettings;
    if (previous === null || this.actionKey !== '' || (!value && !previous.archiveUnknown) ||
      (value && previous.archiveUnknown) || (value && !this.canArchiveUnknown)) { return; }
    const next: ArchiveChatSettings = {
      archiveUnknown: value,
      keepUnmutedArchived: previous.keepUnmutedArchived,
      keepFolderChatsArchived: previous.keepFolderChatsArchived
    };
    this.archiveSettings = next;
    this.save('archive_unknown', setArchiveSettings(next), (): void => { this.archiveSettings = previous; });
  }

  private applyReadDate(value: boolean): void {
    const previous = this.readDate;
    if (previous === null || previous === value || this.actionKey !== '') { return; }
    this.readDate = value;
    this.save('read_date', setReadDatePrivacy(value), (): void => { this.readDate = previous; });
  }

  private applyNewChat(value: boolean): void {
    const previous = this.newChatPrivacy;
    if (previous === null || previous.allowUnknown === value || !this.canSetNewChatPrivacy ||
      this.actionKey !== '') { return; }
    const next: NewChatPrivacySettings = { allowUnknown: value, paidStars: previous.paidStars };
    this.newChatPrivacy = next;
    this.save('new_chat', setNewChatPrivacy(next), (): void => { this.newChatPrivacy = previous; });
  }

  private applyFrequent(value: boolean): void {
    const previous = this.suggestFrequent;
    if (previous === null || previous === value || this.actionKey !== '') { return; }
    this.suggestFrequent = value;
    this.save('top_chats', setBoolOption(OPT_DISABLE_TOP_CHATS, !value),
      (): void => { this.suggestFrequent = previous; });
  }

  private applySensitive(value: boolean): void {
    const previous = this.ignoreSensitive;
    if (previous === null || previous === value || !this.canIgnoreSensitive || this.actionKey !== '') { return; }
    this.ignoreSensitive = value;
    this.save('sensitive', setBoolOption(OPT_IGNORE_SENSITIVE, value),
      (): void => { this.ignoreSensitive = previous; });
  }

  private choiceLabel(choices: Choice[], value: number): string {
    for (const choice of choices) { if (choice.value === value) { return choice.label; } }
    return value > 0 ? plural('ps_days', Math.round(value / 86400), Math.round(value / 86400)) : str('not_loaded');
  }

  private valueText(value: number): string {
    return value >= 0 ? `${value}` : '—';
  }

  private ruleValue(row: RuleRow): string {
    const value = this.rules.get(row.setting);
    if (row.premiumOnly && !this.isPremium) { return 'Premium'; }
    return value !== undefined ? ruleLabel(value) : '—';
  }

  private openRule(row: RuleRow): void {
    if (row.premiumOnly && !this.isPremium) {
      promptAction.showToast({ message: $r('app.string.ps_needs_premium'), duration: 1800 });
      return;
    }
    if (!this.rules.has(row.setting)) {
      promptAction.showToast({ message: $r('app.string.ps_not_loaded_refresh'), duration: 1600 });
      return;
    }
    const params: PrivacyRuleParams = {
      setting: row.setting, title: row.title, hint: row.hint, allowNobody: row.allowNobody
    };
    this.route('pages/main/PrivacyRulePage', params);
  }

  @Builder
  header() {
    Row({ space: 8 }) {
      Button() {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([COLOR_TEXT_PRIMARY]);
      }
      .width(40).height(40).borderRadius(20).backgroundColor(Color.Transparent)
      .onClick((): void => { router.back(); });
      Text($r('app.string.settings_privacy')).fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .layoutWeight(1);
      if (this.loadState === 'ready') {
        Button() {
          if (this.refreshing) {
            LoadingProgress().width(20).height(20).color(COLOR_PRIMARY);
          } else {
            SymbolGlyph($r('sys.symbol.arrow_counterclockwise')).fontSize(20).fontColor([COLOR_PRIMARY]);
          }
        }
        .width(40).height(40).borderRadius(20).backgroundColor(Color.Transparent)
        .enabled(!this.refreshing && this.actionKey === '')
        .onClick((): void => { this.store?.refresh(); });
      }
    }
    .width('100%').height(52).padding({ left: 8, right: 10 }).alignItems(VerticalAlign.Center);
  }

  @Builder
  sectionTitle(text: ResourceStr) {
    Text(text).fontSize(14).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY)
      .width('100%').padding({ left: 16, right: 16, top: 13, bottom: 5 });
  }

  @Builder
  divider() {
    Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16 });
  }

  @Builder
  disclosure() {
    SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).fontColor([COLOR_TEXT_SECONDARY]);
  }

  @Builder
  autoDeleteMenu() {
    Menu() {
      ForEach(autoDeleteChoices(), (choice: Choice) => {
        MenuItem({ content: choice.label }).selected(this.autoDelete === choice.value)
          .onClick((): void => { this.applyAutoDelete(choice.value); });
      }, (choice: Choice): string => `auto_${choice.value}`);
    }
  }

  @Builder
  accountTtlMenu() {
    Menu() {
      ForEach(accountTtlChoices(), (choice: Choice) => {
        MenuItem({ content: choice.label }).selected(this.accountTtl === choice.value)
          .onClick((): void => { this.confirmAccountTtl(choice.value); });
      }, (choice: Choice): string => `ttl_${choice.value}`);
    }
  }

  @Builder
  skeleton() {
    Column({ space: 14 }) {
      ForEach([0, 1, 2, 3], (index: number) => {
        Column({ space: 12 }) {
          Row().width(88).height(12).borderRadius(6).backgroundColor($r('app.color.surface_alt'));
          Row().width('100%').height(index === 1 ? 188 : 112).borderRadius(CARD_RADIUS)
            .backgroundColor(COLOR_SURFACE);
        }.width('100%').alignItems(HorizontalAlign.Start);
      }, (index: number): string => `privacy_skeleton_${index}`);
    }
    .width('100%').padding({ left: 12, right: 12, top: 8 });
  }

  @Builder
  errorState() {
    Column({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle')).fontSize(48).fontColor([COLOR_TEXT_SECONDARY]);
      Text($r('app.string.ps_load_failed')).fontSize(18).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
      Text($r('app.string.ps_no_default_substitute')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
        .textAlign(TextAlign.Center);
      Button($r('app.string.settings_reload')).fontSize(15).fontColor(Color.White).backgroundColor(COLOR_PRIMARY)
        .height(42).padding({ left: 22, right: 22 }).borderRadius(21)
        .onClick((): void => { this.store?.refresh(); });
    }
    .layoutWeight(1).width('100%').padding({ left: 32, right: 32 }).justifyContent(FlexAlign.Center);
  }

  @Builder
  content() {
    Scroll() {
      Column({ space: 12 }) {
        if (this.syncError !== '') {
          Row({ space: 9 }) {
            SymbolGlyph($r('sys.symbol.exclamationmark_triangle_fill')).fontSize(17).fontColor([COLOR_WARNING]);
            Text(this.syncError).fontSize(13).fontColor(COLOR_TEXT_SECONDARY).layoutWeight(1);
            Text($r('app.string.settings_retry')).fontSize(13).fontColor(COLOR_PRIMARY)
              .onClick((): void => { this.store?.refresh(); });
          }
          .width('100%').padding(12).backgroundColor(COLOR_SURFACE).borderRadius(12);
        }

        Column() {
          this.sectionTitle($r('app.string.ps_account_security'));
          Row({ space: 10 }) {
            Text($r('app.string.ps_two_step')).fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
            Text(this.passwordState === null ? '—' :
              (((this.passwordState['has_password'] as boolean | undefined) ?? false) ? $r('app.string.enabled_short') : $r('app.string.disabled_short')))
              .fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
            this.disclosure();
          }
          .width('100%').constraintSize({ minHeight: 50 }).padding({ left: 16, right: 14 })
          .borderRadius(12).stateStyles({ normal: this.rowNormalStyle, pressed: this.rowPressedStyle })
          .onClick((): void => { this.route('pages/main/TwoStepVerificationPage'); });
          this.divider();
          Row({ space: 10 }) {
            Text($r('app.string.ps_active_sessions')).fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
            Text(this.valueText(this.sessions)).fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
            this.disclosure();
          }
          .width('100%').constraintSize({ minHeight: 50 }).padding({ left: 16, right: 14 })
          .borderRadius(12).stateStyles({ normal: this.rowNormalStyle, pressed: this.rowPressedStyle })
          .onClick((): void => { this.route('pages/main/ActiveSessionsPage'); });
          this.divider();
          Row({ space: 10 }) {
            Text($r('app.string.cw_title')).fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
            Text(this.valueText(this.websites)).fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
            this.disclosure();
          }
          .width('100%').constraintSize({ minHeight: 50 }).padding({ left: 16, right: 14 })
          .borderRadius(12).stateStyles({ normal: this.rowNormalStyle, pressed: this.rowPressedStyle })
          .onClick((): void => { this.route('pages/main/ConnectedWebsitesPage'); });
        }
        .width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS).padding({ bottom: 5 });

        Column() {
          this.sectionTitle($r('app.string.ae_personal_info'));
          ForEach(ruleRows().filter((row: RuleRow): boolean => row.group === 'personal'),
            (row: RuleRow, index: number) => {
              if (index > 0) { this.divider(); }
              Row({ space: 9 }) {
                Text(row.title).fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
                Text(this.ruleValue(row)).fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
                this.disclosure();
              }
              .width('100%').constraintSize({ minHeight: 50 }).padding({ left: 16, right: 14 })
              .borderRadius(12).stateStyles({ normal: this.rowNormalStyle, pressed: this.rowPressedStyle })
              .onClick((): void => { this.openRule(row); });
            }, (row: RuleRow): string => `personal_${row.setting}_${this.ruleValue(row)}`);
        }
        .width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS).padding({ bottom: 5 });

        Column() {
          this.sectionTitle($r('app.string.ps_interaction'));
          ForEach(ruleRows().filter((row: RuleRow): boolean => row.group === 'interaction'),
            (row: RuleRow, index: number) => {
              if (index > 0) { this.divider(); }
              Row({ space: 9 }) {
                Text(row.title).fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
                Text(this.ruleValue(row)).fontSize(14)
                  .fontColor(row.premiumOnly && !this.isPremium ? COLOR_WARNING : COLOR_TEXT_SECONDARY)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
                this.disclosure();
              }
              .width('100%').constraintSize({ minHeight: 50 }).padding({ left: 16, right: 14 })
              .borderRadius(12).stateStyles({ normal: this.rowNormalStyle, pressed: this.rowPressedStyle })
              .onClick((): void => { this.openRule(row); });
            }, (row: RuleRow): string => `interaction_${row.setting}_${this.ruleValue(row)}`);
        }
        .width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS).padding({ bottom: 5 });

        Column() {
          this.sectionTitle($r('app.string.ps_message_privacy'));
          if (this.readDate !== null) {
            Row({ space: 12 }) {
              Column({ space: 2 }) {
                Text($r('app.string.ps_read_time')).fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
                Text($r('app.string.ps_read_time_sub'))
                  .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).maxLines(2);
              }.layoutWeight(1).alignItems(HorizontalAlign.Start);
              Toggle({ type: ToggleType.Switch, isOn: this.readDate })
                .selectedColor(COLOR_PRIMARY).enabled(this.actionKey === '')
                .onChange((value: boolean): void => { this.applyReadDate(value); });
            }
            .width('100%').constraintSize({ minHeight: 62 }).padding({ left: 16, right: 14, top: 7, bottom: 7 });
          }
          if (this.newChatPrivacy !== null) {
            this.divider();
            Row({ space: 12 }) {
              Column({ space: 2 }) {
                Text($r('app.string.ps_allow_new_chats')).fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
                Text(this.canSetNewChatPrivacy ? $r('app.string.ps_allow_new_chats_sub') : $r('app.string.ps_not_supported'))
                  .fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
              }.layoutWeight(1).alignItems(HorizontalAlign.Start);
              Toggle({ type: ToggleType.Switch, isOn: this.newChatPrivacy.allowUnknown })
                .selectedColor(COLOR_PRIMARY).enabled(this.canSetNewChatPrivacy && this.actionKey === '')
                .onChange((value: boolean): void => { this.applyNewChat(value); });
            }
            .width('100%').constraintSize({ minHeight: 62 }).padding({ left: 16, right: 14, top: 7, bottom: 7 });
          }
          if (this.archiveSettings !== null) {
            this.divider();
            Row({ space: 12 }) {
              Column({ space: 2 }) {
                Text($r('app.string.ps_archive_new_chats')).fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
                Text(this.canArchiveUnknown || this.archiveSettings.archiveUnknown
                  ? $r('app.string.ps_archive_new_chats_sub') : $r('app.string.ps_cannot_enable'))
                  .fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
              }.layoutWeight(1).alignItems(HorizontalAlign.Start);
              Toggle({ type: ToggleType.Switch, isOn: this.archiveSettings.archiveUnknown })
                .selectedColor(COLOR_PRIMARY)
                .enabled((this.canArchiveUnknown || this.archiveSettings.archiveUnknown) && this.actionKey === '')
                .onChange((value: boolean): void => { this.applyArchive(value); });
            }
            .width('100%').constraintSize({ minHeight: 62 }).padding({ left: 16, right: 14, top: 7, bottom: 7 });
          }
          if (this.autoDelete >= 0) {
            this.divider();
            Row({ space: 9 }) {
              Column({ space: 2 }) {
                Text($r('app.string.ps_auto_delete')).fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
                Text($r('app.string.ps_auto_delete_sub')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
              }.layoutWeight(1).alignItems(HorizontalAlign.Start);
              Text(this.choiceLabel(autoDeleteChoices(), this.autoDelete)).fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
              this.disclosure();
            }
            .width('100%').constraintSize({ minHeight: 58 }).padding({ left: 16, right: 14 })
            .borderRadius(12).stateStyles({ normal: this.rowNormalStyle, pressed: this.rowPressedStyle })
            .bindMenu(this.autoDeleteMenu(), { systemMaterial: overlayMaterial('menu') });
          }
        }
        .width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS).padding({ bottom: 5 });

        Column() {
          this.sectionTitle($r('app.string.ps_contacts_and_account'));
          Row({ space: 9 }) {
            Text($r('app.string.bu_title')).fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
            Text(this.valueText(this.blocked)).fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
            this.disclosure();
          }
          .width('100%').constraintSize({ minHeight: 50 }).padding({ left: 16, right: 14 })
          .borderRadius(12).stateStyles({ normal: this.rowNormalStyle, pressed: this.rowPressedStyle })
          .onClick((): void => { this.route('pages/main/BlockedUsersPage'); });
          if (this.suggestFrequent !== null) {
            this.divider();
            Row({ space: 12 }) {
              Column({ space: 2 }) {
                Text($r('app.string.ps_suggest_frequent')).fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
                Text($r('app.string.ps_suggest_frequent_sub')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
              }.layoutWeight(1).alignItems(HorizontalAlign.Start);
              Toggle({ type: ToggleType.Switch, isOn: this.suggestFrequent })
                .selectedColor(COLOR_PRIMARY).enabled(this.actionKey === '')
                .onChange((value: boolean): void => { this.applyFrequent(value); });
            }
            .width('100%').constraintSize({ minHeight: 58 }).padding({ left: 16, right: 14 });
          }
          if (this.canIgnoreSensitive && this.ignoreSensitive !== null) {
            this.divider();
            Row({ space: 12 }) {
              Column({ space: 2 }) {
                Text($r('app.string.ps_sensitive')).fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
                Text($r('app.string.ps_sensitive_sub')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
              }.layoutWeight(1).alignItems(HorizontalAlign.Start);
              Toggle({ type: ToggleType.Switch, isOn: this.ignoreSensitive })
                .selectedColor(COLOR_PRIMARY).enabled(this.actionKey === '')
                .onChange((value: boolean): void => { this.applySensitive(value); });
            }
            .width('100%').constraintSize({ minHeight: 58 }).padding({ left: 16, right: 14 });
          }
          if (this.accountTtl >= 0) {
            this.divider();
            Row({ space: 9 }) {
              Column({ space: 2 }) {
                Text($r('app.string.ps_delete_account')).fontSize(16).fontColor(COLOR_DANGER);
                Text($r('app.string.ps_delete_account_sub')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
              }.layoutWeight(1).alignItems(HorizontalAlign.Start);
              Text(this.choiceLabel(accountTtlChoices(), this.accountTtl)).fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
              this.disclosure();
            }
            .width('100%').constraintSize({ minHeight: 60 }).padding({ left: 16, right: 14 })
            .borderRadius(12).stateStyles({ normal: this.rowNormalStyle, pressed: this.rowPressedStyle })
            .bindMenu(this.accountTtlMenu(), { systemMaterial: overlayMaterial('menu') });
          }
        }
        .width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS).padding({ bottom: 5 });

        Text($r('app.string.ps_note'))
          .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).lineHeight(18)
          .width('100%').padding({ left: 16, right: 16, bottom: 4 });
      }
      .width('100%').padding({ left: 12, right: 12, top: 6, bottom: this.bottomSafe + 24 });
    }
    .layoutWeight(1).width('100%').align(Alignment.Top).scrollBar(BarState.Off);
  }

  build() {
    Column() {
      this.header();
      if (this.loadState === 'loading') { this.skeleton(); }
      else if (this.loadState === 'error') { this.errorState(); }
      else { this.content(); }
    }
    .width('100%').height('100%').backgroundColor(COLOR_PAGE_BG)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .padding({ top: this.topSafe });
  }
}
