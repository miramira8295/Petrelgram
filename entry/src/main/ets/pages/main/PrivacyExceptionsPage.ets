import { router, promptAction } from '@kit.ArkUI';
import { getTdClient } from '../../tdkit/Globals';
import { TdError, TdObject, TdRequest } from '../../tdkit/TdTypes';
import { PrivacyValue, getPrivacy, setPrivacy } from '../../store/PrivacyApi';
import { PrivacyExceptionsParams } from './PrivacyRulePage';
import { AvatarView } from '../chatlist/AvatarView';
import {
  COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE,
  COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';
import { plural, str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { overlayBlur, overlayMaterial, MATERIAL_EPOCH } from '../../util/overlayMaterial';
import { logE } from '../../util/log';
import { readableContentWidth } from '../../util/contentWidth';
import { SHEET_CLOSE_RESERVE_VP } from '../../util/sheetChrome';

const CARD_RADIUS: number = 16;

interface ExceptionUser {
  id: number;
  name: string;
  username: string;
  initials: string;
  avatarPath: string;
}

function idsFor(rules: TdObject[], type: string): number[] {
  for (const rule of rules) {
    if (rule['@type'] === type) { return (rule['user_ids'] as number[] | undefined) ?? []; }
  }
  return [];
}

function chatCountFor(rules: TdObject[], type: string): number {
  for (const rule of rules) {
    if (rule['@type'] === type) {
      return ((rule['chat_ids'] as number[] | undefined) ?? []).length;
    }
  }
  return 0;
}

function replaceUserRule(rules: TdObject[], type: string, ids: number[]): TdObject[] {
  const next: TdObject[] = [];
  let inserted = false;
  for (const rule of rules) {
    if (rule['@type'] === type) {
      if (!inserted && ids.length > 0) {
        next.push({ '@type': type, 'user_ids': ids } as TdObject);
        inserted = true;
      }
    } else {
      next.push(rule);
    }
  }
  if (!inserted && ids.length > 0) {
    const item = { '@type': type, 'user_ids': ids } as TdObject;
    if (type === 'userPrivacySettingRuleAllowUsers') { next.unshift(item); }
    else { next.push(item); }
  }
  return next;
}

@Entry
@Component
struct PrivacyExceptionsPage {
  // 材质档位（厚度/光感）改变时重绘。overlayMaterial 是 util，订阅不了
  // AppStorage，只能由调用方订阅，同 LANGUAGE_EPOCH 的做法。
  @StorageProp(MATERIAL_EPOCH) private materialEpoch: number = 0;
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  // 窗口宽（不是屏幕宽），限宽用。平板上把一列拉满 2880px 眼睛要横扫一行。
  @StorageProp('screenWidthVp') screenW: number = 360;
  @State setting: string = '';
  @State title: string = '';
  @State loadState: string = 'loading';
  @State allowUsers: ExceptionUser[] = [];
  @State restrictUsers: ExceptionUser[] = [];
  @State allowChatCount: number = 0;
  @State restrictChatCount: number = 0;
  @State sheetOpen: boolean = false;
  @State sheetMode: string = 'allow';
  @State candidates: ExceptionUser[] = [];
  @State candidateState: string = 'loading';
  @State query: string = '';
  @State draftIds: number[] = [];
  @State saving: boolean = false;
  private base: string = '';
  private preserved: TdObject[] = [];
  private allowUserIds: number[] = [];
  private restrictUserIds: number[] = [];
  private active: boolean = false;
  private sequence: number = 0;

  aboutToAppear(): void {
    this.active = true;
    const params = router.getParams() as PrivacyExceptionsParams | undefined;
    if (params === undefined || params.setting === undefined || params.setting === '') {
      router.back();
      return;
    }
    this.setting = params.setting;
    this.title = params.title;
    this.load();
  }

  aboutToDisappear(): void {
    this.active = false;
    this.sequence++;
  }

  private userFromObject(user: TdObject): ExceptionUser {
    const id = (user['id'] as number | undefined) ?? 0;
    const first = (user['first_name'] as string | undefined) ?? '';
    const last = (user['last_name'] as string | undefined) ?? '';
    const name = `${first}${last !== '' ? ` ${last}` : ''}`.trim();
    const usernames = user['usernames'] as TdObject | undefined;
    const active = usernames !== undefined
      ? ((usernames['active_usernames'] as string[] | undefined) ?? []) : [];
    const photo = user['profile_photo'] as TdObject | undefined;
    const small = photo !== undefined ? photo['small'] as TdObject | undefined : undefined;
    const local = small !== undefined ? small['local'] as TdObject | undefined : undefined;
    const path = local !== undefined ? ((local['path'] as string | undefined) ?? '') : '';
    return {
      id,
      name: name !== '' ? name : str('deleted_account'),
      username: active.length > 0 ? `@${active[0]}` : '',
      initials: name !== '' ? name.substring(0, 1).toUpperCase() : '?',
      avatarPath: path
    };
  }

  private resolveUsers(ids: number[]): Promise<ExceptionUser[]> {
    const client = getTdClient();
    return Promise.all(ids.map((id: number): Promise<ExceptionUser | null> => {
      const request: TdRequest = { '@type': 'getUser' };
      request['user_id'] = id;
      return client.send(request).then((user: TdObject): ExceptionUser => this.userFromObject(user))
        .catch((): null => null);
    })).then((items: Array<ExceptionUser | null>): ExceptionUser[] => {
      const rows: ExceptionUser[] = [];
      for (const item of items) { if (item !== null) { rows.push(item); } }
      return rows;
    });
  }

  private load(): void {
    const sequence = ++this.sequence;
    this.loadState = 'loading';
    getPrivacy(this.setting).then((value: PrivacyValue): Promise<ExceptionUser[][]> => {
      if (!this.active || sequence !== this.sequence) { return Promise.resolve([]); }
      this.base = value.base;
      this.preserved = value.extra;
      this.allowUserIds = idsFor(value.extra, 'userPrivacySettingRuleAllowUsers');
      this.restrictUserIds = idsFor(value.extra, 'userPrivacySettingRuleRestrictUsers');
      this.allowChatCount = chatCountFor(value.extra, 'userPrivacySettingRuleAllowChatMembers');
      this.restrictChatCount = chatCountFor(value.extra, 'userPrivacySettingRuleRestrictChatMembers');
      return Promise.all([
        this.resolveUsers(this.allowUserIds),
        this.resolveUsers(this.restrictUserIds)
      ]);
    }).then((rows: ExceptionUser[][]): void => {
      if (!this.active || sequence !== this.sequence || rows.length !== 2) { return; }
      this.allowUsers = rows[0];
      this.restrictUsers = rows[1];
      this.loadState = 'ready';
    }).catch((error: TdError): void => {
      if (!this.active || sequence !== this.sequence) { return; }
      logE(`PrivacyExceptionsPage.load failed: ${error.message}`);
      this.loadState = 'error';
    });
  }

  private openPicker(mode: string): void {
    if (this.saving || this.loadState !== 'ready') { return; }
    this.sheetMode = mode;
    this.query = '';
    this.draftIds = (mode === 'allow' ? this.allowUserIds : this.restrictUserIds).slice();
    this.sheetOpen = true;
    this.loadCandidates();
  }

  private loadCandidates(): void {
    const sequence = ++this.sequence;
    this.candidateState = 'loading';
    const request: TdRequest = { '@type': 'getContacts' };
    getTdClient().send(request).then((result: TdObject): Promise<ExceptionUser[]> => {
      const ids = (result['user_ids'] as number[] | undefined) ?? [];
      return this.resolveUsers(ids);
    }).then((rows: ExceptionUser[]): void => {
      if (!this.active || sequence !== this.sequence) { return; }
      const merged = rows.slice();
      for (const existing of [...this.allowUsers, ...this.restrictUsers]) {
        if (merged.findIndex((item: ExceptionUser): boolean => item.id === existing.id) < 0) {
          merged.push(existing);
        }
      }
      this.candidates = merged;
      this.candidateState = merged.length > 0 ? 'ready' : 'empty';
    }).catch((error: TdError): void => {
      if (!this.active || sequence !== this.sequence) { return; }
      logE(`PrivacyExceptionsPage.contacts failed: ${error.message}`);
      this.candidateState = 'error';
    });
  }

  private filteredCandidates(): ExceptionUser[] {
    const query = this.query.trim().toLowerCase();
    if (query === '') { return this.candidates; }
    return this.candidates.filter((user: ExceptionUser): boolean =>
      user.name.toLowerCase().indexOf(query) >= 0 || user.username.toLowerCase().indexOf(query) >= 0);
  }

  private toggleDraft(id: number): void {
    if (this.draftIds.indexOf(id) >= 0) {
      this.draftIds = this.draftIds.filter((value: number): boolean => value !== id);
    } else {
      this.draftIds = [...this.draftIds, id];
    }
  }

  private saveDraft(): void {
    if (this.saving) { return; }
    const allowIds = this.sheetMode === 'allow'
      ? this.draftIds.slice()
      : this.allowUserIds
        .filter((id: number): boolean => this.draftIds.indexOf(id) < 0);
    const restrictIds = this.sheetMode === 'restrict'
      ? this.draftIds.slice()
      : this.restrictUserIds
        .filter((id: number): boolean => this.draftIds.indexOf(id) < 0);
    let next = replaceUserRule(this.preserved, 'userPrivacySettingRuleAllowUsers', allowIds);
    next = replaceUserRule(next, 'userPrivacySettingRuleRestrictUsers', restrictIds);
    this.saving = true;
    setPrivacy(this.setting, this.base, next).then((): void => {
      if (!this.active) { return; }
      this.preserved = next;
      this.allowUserIds = allowIds;
      this.restrictUserIds = restrictIds;
      this.sheetOpen = false;
      this.saving = false;
      this.load();
    }).catch((error: TdError): void => {
      logE(`PrivacyExceptionsPage.save failed: ${error.message}`);
      if (!this.active) { return; }
      this.saving = false;
      promptAction.showToast({ message: $r('app.string.pe_save_failed'), duration: 1800 });
    });
  }

  @Builder
  header() {
    Row({ space: 8 }) {
      Button() {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([COLOR_TEXT_PRIMARY]);
      }.width(40).height(40).borderRadius(20).backgroundColor(Color.Transparent)
      .onClick((): void => { router.back(); });
      Text(str('pe_title', this.title)).fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
    }
    .width('100%').height(52).padding({ left: 8, right: 14 }).alignItems(VerticalAlign.Center);
  }

  @Builder
  exceptionRow(user: ExceptionUser) {
    Row({ space: 12 }) {
      AvatarView({ avatarPath: user.avatarPath, initials: user.initials, colorSeed: user.id, avatarSize: 42 });
      Column({ space: 2 }) {
        Text(user.name).fontSize(16).fontColor(COLOR_TEXT_PRIMARY).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
        if (user.username !== '') { Text(user.username).fontSize(12).fontColor(COLOR_TEXT_SECONDARY); }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
    }
    .width('100%').constraintSize({ minHeight: 56 }).padding({ left: 12, right: 14 });
  }

  @Builder
  exceptionCard(title: ResourceStr, mode: string, rows: ExceptionUser[], chatCount: number) {
    Column() {
      Row() {
        Text(title).fontSize(14).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY).layoutWeight(1);
        Button($r('app.string.edit')).fontSize(13).fontColor(COLOR_PRIMARY).backgroundColor(Color.Transparent)
          .height(36).onClick((): void => { this.openPicker(mode); });
      }.width('100%').height(46).padding({ left: 16, right: 8 });
      if (rows.length === 0 && chatCount === 0) {
        Text($r('app.string.pe_empty')).fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
          .width('100%').padding({ left: 16, right: 16, top: 10, bottom: 18 });
      } else {
        ForEach(rows, (user: ExceptionUser, index: number) => {
          if (index > 0) { Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 66 }); }
          this.exceptionRow(user);
        }, (user: ExceptionUser): string => `${mode}_${user.id}`);
        if (chatCount > 0) {
          Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16 });
          Text(plural('pe_group_exceptions_kept', chatCount, chatCount))
            .fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
            .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 });
        }
      }
    }
    .width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS).padding({ bottom: 4 });
  }

  @Builder
  pickerSheet() {
    Column({ space: 10 }) {
      Row() {
        Column({ space: 2 }) {
          Text(this.sheetMode === 'allow' ? $r('app.string.privacy_always_allow') : $r('app.string.privacy_never_allow'))
            .fontSize(21).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
          Text($r('app.string.pe_pick_note'))
            .fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
        }.layoutWeight(1).alignItems(HorizontalAlign.Start);
        Button(this.saving ? $r('app.string.saving') : $r('app.string.done')).fontSize(15).fontColor(COLOR_PRIMARY)
          .backgroundColor(Color.Transparent).enabled(!this.saving)
          .onClick((): void => { this.saveDraft(); });
      }
      .width('100%').height(52).alignItems(VerticalAlign.Center)
      // 给系统关闭按钮让位，否则「完成」被它盖住（issue #124）。
      .padding({ right: SHEET_CLOSE_RESERVE_VP });
      TextInput({ text: this.query, placeholder: $r('app.string.search_contacts') })
        .height(44).fontSize(15).backgroundColor($r('app.color.surface_alt')).borderRadius(12)
        .padding({ left: 13, right: 13 }).onChange((value: string): void => { this.query = value; });
      if (this.candidateState === 'loading') {
        Column() { LoadingProgress().width(30).height(30).color(COLOR_PRIMARY); }
          .layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else if (this.candidateState === 'error') {
        Column({ space: 10 }) {
          Text($r('app.string.contacts_load_failed')).fontSize(15).fontColor(COLOR_TEXT_PRIMARY);
          Button($r('app.string.settings_retry')).onClick((): void => { this.loadCandidates(); });
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else if (this.filteredCandidates().length === 0) {
        Column({ space: 6 }) {
          Text($r('app.string.pe_no_contacts')).fontSize(15).fontColor(COLOR_TEXT_PRIMARY);
          Text($r('app.string.pe_no_contacts_sub')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else {
        List() {
          ForEach(this.filteredCandidates(), (user: ExceptionUser) => {
            ListItem() {
              Row({ space: 12 }) {
                AvatarView({ avatarPath: user.avatarPath, initials: user.initials, colorSeed: user.id, avatarSize: 42 });
                Column({ space: 2 }) {
                  Text(user.name).fontSize(16).fontColor(COLOR_TEXT_PRIMARY).maxLines(1);
                  if (user.username !== '') { Text(user.username).fontSize(12).fontColor(COLOR_TEXT_SECONDARY); }
                }.layoutWeight(1).alignItems(HorizontalAlign.Start);
                SymbolGlyph($r(this.draftIds.indexOf(user.id) >= 0
                  ? 'sys.symbol.checkmark_circle_fill' : 'sys.symbol.circle'))
                  .fontSize(23).fontColor([this.draftIds.indexOf(user.id) >= 0 ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY]);
              }
              .width('100%').height(58).padding({ left: 6, right: 8 })
              .onClick((): void => { this.toggleDraft(user.id); });
            }
          }, (user: ExceptionUser): string => `candidate_${user.id}_${this.draftIds.indexOf(user.id) >= 0}`);
        }.layoutWeight(1).width('100%').scrollBar(BarState.Off);
      }
    }
    .width('100%').height('100%').padding({ left: 16, right: 16, top: 4, bottom: this.bottomSafe + 8 });
  }

  build() {
    Column() {
      this.header();
      if (this.loadState === 'loading') {
        Column() { LoadingProgress().width(34).height(34).color(COLOR_PRIMARY); }
          .layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else if (this.loadState === 'error') {
        Column({ space: 10 }) {
          Text($r('app.string.pe_load_failed')).fontSize(17).fontColor(COLOR_TEXT_PRIMARY);
          Button($r('app.string.settings_reload')).onClick((): void => { this.load(); });
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else {
        Scroll() {
          // 两层 Column 是故意的：外层铺满、负责居中，内层才是被限宽的内容。
          // 限宽如果加在 Scroll 上，滚动条和边缘回弹会跟着一起缩进来，侧边留白
          // 区域还会拖不动页面；做在里面则留白仍在 Scroll 的命中区，能拖。
          Column() {
            Column({ space: 12 }) {
              this.exceptionCard($r('app.string.privacy_always_allow'), 'allow', this.allowUsers, this.allowChatCount);
              this.exceptionCard($r('app.string.privacy_never_allow'), 'restrict', this.restrictUsers, this.restrictChatCount);
              Text($r('app.string.pe_note'))
                .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).lineHeight(18)
                .width('100%').padding({ left: 16, right: 16 });
            }
            .width('100%')
            .constraintSize({ maxWidth: readableContentWidth(this.screenW) })
            .padding({ left: 12, right: 12, top: 6, bottom: this.bottomSafe + 24 });
          }
          .width('100%')
          // Column 默认左对齐：限了宽不居中就是把内容全堆在屏幕左边，比不限还难看。
          .alignItems(HorizontalAlign.Center);
        }
        .align(Alignment.Top).layoutWeight(1).width('100%').scrollBar(BarState.Off);
      }
    }
    .width('100%').height('100%').backgroundColor(COLOR_PAGE_BG)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .padding({ top: this.topSafe })
    .bindSheet($$this.sheetOpen, this.pickerSheet(), {
      height: SheetSize.LARGE,
      backgroundColor: COLOR_SURFACE,
      dragBar: true,
      blurStyle: overlayBlur('dialog'), systemMaterial: overlayMaterial('dialog')
    });
  }
}
