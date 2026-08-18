import { router, promptAction } from '@kit.ArkUI';
import { getTdClient } from '../../tdkit/Globals';
import { TdError, TdObject, TdRequest } from '../../tdkit/TdTypes';
import { AvatarView } from '../chatlist/AvatarView';
import {
  COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE,
  COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';
import { plural, str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { overlayMaterial } from '../../util/overlayMaterial';

const PAGE_LIMIT: number = 40;
const CARD_RADIUS: number = 16;
const COLOR_DANGER: string = '#E5484D';

interface BlockedRow {
  key: string;
  userId: number;
  chatId: number;
  title: string;
  subtitle: string;
  initials: string;
  avatarPath: string;
}

interface PickerUser {
  id: number;
  name: string;
  subtitle: string;
  initials: string;
  avatarPath: string;
}

@Entry
@Component
struct BlockedUsersPage {
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State rows: BlockedRow[] = [];
  @State loadState: string = 'loading';
  @State pageState: string = 'idle';
  @State totalCount: number = 0;
  @State actionKey: string = '';
  @State pickerOpen: boolean = false;
  @State pickerState: string = 'loading';
  @State pickerUsers: PickerUser[] = [];
  @State pickerQuery: string = '';
  private active: boolean = false;
  private sequence: number = 0;
  private unsubscribeFile: (() => void) | null = null;
  private fileKeys: Map<number, string[]> = new Map();

  aboutToAppear(): void {
    this.active = true;
    this.unsubscribeFile = getTdClient().onUpdate('updateFile', (update: TdObject): void => {
      const file = update['file'] as TdObject | undefined;
      if (file !== undefined) { this.applyFile(file); }
    });
    this.load(true);
  }

  aboutToDisappear(): void {
    this.active = false;
    this.sequence++;
    if (this.unsubscribeFile !== null) { this.unsubscribeFile(); this.unsubscribeFile = null; }
    this.fileKeys.clear();
  }

  private senderRow(sender: TdObject): BlockedRow {
    const userId = (sender['user_id'] as number | undefined) ?? 0;
    const chatId = (sender['chat_id'] as number | undefined) ?? 0;
    return {
      key: userId > 0 ? `u_${userId}` : `c_${chatId}`,
      userId, chatId, title: '', subtitle: '', initials: '?', avatarPath: ''
    };
  }

  private load(initial: boolean): void {
    if (!initial && (this.pageState === 'loading' || this.rows.length >= this.totalCount)) { return; }
    const sequence = initial ? ++this.sequence : this.sequence;
    if (initial) {
      this.loadState = 'loading';
      this.pageState = 'idle';
      this.rows = [];
      this.totalCount = 0;
      this.fileKeys.clear();
    } else {
      this.pageState = 'loading';
    }
    const request: TdRequest = { '@type': 'getBlockedMessageSenders' };
    request['block_list'] = { '@type': 'blockListMain' } as TdObject;
    request['offset'] = initial ? 0 : this.rows.length;
    request['limit'] = PAGE_LIMIT;
    getTdClient().send(request).then((result: TdObject): void => {
      if (!this.active || sequence !== this.sequence) { return; }
      const senders = (result['senders'] as TdObject[] | undefined) ?? [];
      const incoming = senders.map((sender: TdObject): BlockedRow => this.senderRow(sender));
      const merged = initial ? incoming : this.rows.slice();
      for (const row of incoming) {
        if (merged.findIndex((item: BlockedRow): boolean => item.key === row.key) < 0) { merged.push(row); }
      }
      this.rows = merged;
      this.totalCount = Math.max((result['total_count'] as number | undefined) ?? 0, merged.length);
      this.loadState = 'ready';
      this.pageState = merged.length < this.totalCount && incoming.length > 0 ? 'idle' : 'done';
      for (const row of incoming) { this.resolveRow(row); }
    }).catch((error: TdError): void => {
      if (!this.active || sequence !== this.sequence) { return; }
      console.error(`BlockedUsersPage.load failed: ${error.message}`);
      if (initial) { this.loadState = 'error'; }
      else { this.pageState = 'error'; }
    });
  }

  private patch(key: string, title: string, subtitle: string, avatarPath: string): void {
    this.rows = this.rows.map((row: BlockedRow): BlockedRow => row.key === key ? {
      key: row.key, userId: row.userId, chatId: row.chatId,
      title, subtitle, initials: title !== '' ? title.substring(0, 1).toUpperCase() : '?',
      avatarPath: avatarPath !== '' ? avatarPath : row.avatarPath
    } : row);
  }

  private filePath(file: TdObject | undefined): string {
    const local = file !== undefined ? file['local'] as TdObject | undefined : undefined;
    const completed = local !== undefined
      ? ((local['is_downloading_completed'] as boolean | undefined) ?? false) : false;
    return completed && local !== undefined ? ((local['path'] as string | undefined) ?? '') : '';
  }

  private watchFile(file: TdObject | undefined, key: string): string {
    if (file === undefined) { return ''; }
    const path = this.filePath(file);
    if (path !== '') { return path; }
    const id = (file['id'] as number | undefined) ?? 0;
    if (id <= 0) { return ''; }
    const keys = this.fileKeys.get(id) ?? [];
    if (keys.indexOf(key) < 0) { keys.push(key); this.fileKeys.set(id, keys); }
    const request: TdRequest = { '@type': 'downloadFile' };
    request['file_id'] = id;
    request['priority'] = 2;
    request['offset'] = 0;
    request['limit'] = 0;
    request['synchronous'] = false;
    getTdClient().send(request).catch((): void => {});
    return '';
  }

  private applyFile(file: TdObject): void {
    const id = (file['id'] as number | undefined) ?? 0;
    const path = this.filePath(file);
    const keys = this.fileKeys.get(id);
    if (path === '' || keys === undefined) { return; }
    this.fileKeys.delete(id);
    this.rows = this.rows.map((row: BlockedRow): BlockedRow => keys.indexOf(row.key) >= 0
      ? {
        key: row.key, userId: row.userId, chatId: row.chatId, title: row.title,
        subtitle: row.subtitle, initials: row.initials, avatarPath: path
      } : row);
  }

  private resolveRow(row: BlockedRow): void {
    const request: TdRequest = { '@type': row.userId > 0 ? 'getUser' : 'getChat' };
    if (row.userId > 0) { request['user_id'] = row.userId; }
    else { request['chat_id'] = row.chatId; }
    getTdClient().send(request).then((object: TdObject): void => {
      if (!this.active || this.rows.findIndex((item: BlockedRow): boolean => item.key === row.key) < 0) { return; }
      if (row.userId > 0) {
        const first = (object['first_name'] as string | undefined) ?? '';
        const last = (object['last_name'] as string | undefined) ?? '';
        const name = `${first}${last !== '' ? ` ${last}` : ''}`.trim();
        const usernames = object['usernames'] as TdObject | undefined;
        const active = usernames !== undefined
          ? ((usernames['active_usernames'] as string[] | undefined) ?? []) : [];
        const photo = object['profile_photo'] as TdObject | undefined;
        const small = photo !== undefined ? photo['small'] as TdObject | undefined : undefined;
        this.patch(row.key, name !== '' ? name : str('deleted_account'),
          active.length > 0 ? `@${active[0]}` : str('bu_kind_user'), this.watchFile(small, row.key));
      } else {
        const photo = object['photo'] as TdObject | undefined;
        const small = photo !== undefined ? photo['small'] as TdObject | undefined : undefined;
        this.patch(row.key, (object['title'] as string | undefined) ?? str('bu_unknown_channel'),
          str('bu_kind_chat'), this.watchFile(small, row.key));
      }
    }).catch((error: TdError): void => {
      console.warn(`BlockedUsersPage.resolve(${row.key}) failed: ${error.message}`);
      if (this.active) { this.patch(row.key, row.userId > 0 ? str('bu_unknown_user') : str('bu_unknown_channel'), '', ''); }
    });
  }

  private sender(row: BlockedRow): TdObject {
    return row.userId > 0
      ? { '@type': 'messageSenderUser', 'user_id': row.userId } as TdObject
      : { '@type': 'messageSenderChat', 'chat_id': row.chatId } as TdObject;
  }

  private unblock(row: BlockedRow): void {
    if (this.actionKey !== '') { return; }
    promptAction.showDialog({
      title: $r('app.string.bu_unblock_title'), message: str('bu_unblock_confirm', row.title !== '' ? row.title : str('bu_this_user')),
      buttons: [
        { text: $r('app.string.cancel'), color: COLOR_TEXT_SECONDARY as string },
        { text: $r('app.string.bu_unblock'), color: COLOR_PRIMARY as string }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse): void => {
      if (!this.active || result.index !== 1 || this.actionKey !== '') { return; }
      const before = this.rows.slice();
      const beforeTotal = this.totalCount;
      this.actionKey = row.key;
      this.rows = this.rows.filter((item: BlockedRow): boolean => item.key !== row.key);
      this.totalCount = Math.max(0, this.totalCount - 1);
      const request: TdRequest = { '@type': 'setMessageSenderBlockList' };
      request['sender_id'] = this.sender(row);
      getTdClient().send(request).then((): void => {
        if (!this.active) { return; }
        this.actionKey = '';
        if (this.rows.length < this.totalCount) { this.load(false); }
      }).catch((error: TdError): void => {
        console.error(`BlockedUsersPage.unblock failed: ${error.message}`);
        if (!this.active) { return; }
        this.rows = before;
        this.totalCount = beforeTotal;
        this.actionKey = '';
        promptAction.showToast({ message: $r('app.string.bu_unblock_failed'), duration: 1800 });
      });
    }).catch((): void => {});
  }

  private openPicker(): void {
    if (this.actionKey !== '') { return; }
    this.pickerOpen = true;
    this.pickerQuery = '';
    this.pickerState = 'loading';
    const sequence = ++this.sequence;
    getTdClient().send({ '@type': 'getContacts' } as TdRequest).then((result: TdObject): Promise<PickerUser[]> => {
      const ids = (result['user_ids'] as number[] | undefined) ?? [];
      return Promise.all(ids.map((id: number): Promise<PickerUser | null> => {
        const request: TdRequest = { '@type': 'getUser' };
        request['user_id'] = id;
        return getTdClient().send(request).then((user: TdObject): PickerUser => {
          const first = (user['first_name'] as string | undefined) ?? '';
          const last = (user['last_name'] as string | undefined) ?? '';
          const name = `${first}${last !== '' ? ` ${last}` : ''}`.trim();
          const usernames = user['usernames'] as TdObject | undefined;
          const active = usernames !== undefined
            ? ((usernames['active_usernames'] as string[] | undefined) ?? []) : [];
          const photo = user['profile_photo'] as TdObject | undefined;
          const small = photo !== undefined ? photo['small'] as TdObject | undefined : undefined;
          return {
            id, name: name !== '' ? name : str('bu_untitled_user'),
            subtitle: active.length > 0 ? `@${active[0]}` : str('tab_contacts'),
            initials: name !== '' ? name.substring(0, 1).toUpperCase() : '?',
            avatarPath: this.filePath(small)
          };
        }).catch((): null => null);
      })).then((items: Array<PickerUser | null>): PickerUser[] => {
        const rows: PickerUser[] = [];
        for (const item of items) {
          if (item !== null && this.rows.findIndex((row: BlockedRow): boolean => row.userId === item.id) < 0) {
            rows.push(item);
          }
        }
        return rows;
      });
    }).then((rows: PickerUser[]): void => {
      if (!this.active || sequence !== this.sequence) { return; }
      this.pickerUsers = rows;
      this.pickerState = rows.length > 0 ? 'ready' : 'empty';
    }).catch((error: TdError): void => {
      if (!this.active || sequence !== this.sequence) { return; }
      console.error(`BlockedUsersPage.picker failed: ${error.message}`);
      this.pickerState = 'error';
    });
  }

  private filteredPicker(): PickerUser[] {
    const query = this.pickerQuery.trim().toLowerCase();
    if (query === '') { return this.pickerUsers; }
    return this.pickerUsers.filter((user: PickerUser): boolean =>
      user.name.toLowerCase().indexOf(query) >= 0 || user.subtitle.toLowerCase().indexOf(query) >= 0);
  }

  private block(user: PickerUser): void {
    if (this.actionKey !== '') { return; }
    this.actionKey = `block_${user.id}`;
    const request: TdRequest = { '@type': 'setMessageSenderBlockList' };
    request['sender_id'] = { '@type': 'messageSenderUser', 'user_id': user.id } as TdObject;
    request['block_list'] = { '@type': 'blockListMain' } as TdObject;
    getTdClient().send(request).then((): void => {
      if (!this.active) { return; }
      this.actionKey = '';
      this.pickerOpen = false;
      this.load(true);
      promptAction.showToast({ message: str('bu_blocked_toast', user.name), duration: 1500 });
    }).catch((error: TdError): void => {
      console.error(`BlockedUsersPage.block failed: ${error.message}`);
      if (!this.active) { return; }
      this.actionKey = '';
      promptAction.showToast({ message: $r('app.string.bu_block_failed'), duration: 1800 });
    });
  }

  @Builder
  header() {
    Row({ space: 8 }) {
      Button() {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([COLOR_TEXT_PRIMARY]);
      }.width(40).height(40).borderRadius(20).backgroundColor(Color.Transparent)
      .onClick((): void => { router.back(); });
      Column({ space: 1 }) {
        Text($r('app.string.bu_title')).fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
        if (this.loadState === 'ready') {
          Text(plural('bu_account_count', this.totalCount, this.totalCount)).fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      Button() {
        SymbolGlyph($r('sys.symbol.plus')).fontSize(21).fontColor([COLOR_PRIMARY]);
      }.width(40).height(40).borderRadius(20).backgroundColor(Color.Transparent)
      .enabled(this.loadState === 'ready' && this.actionKey === '')
      .onClick((): void => { this.openPicker(); });
    }.width('100%').height(52).padding({ left: 8, right: 10 }).alignItems(VerticalAlign.Center);
  }

  @Builder
  row(row: BlockedRow) {
    Row({ space: 12 }) {
      AvatarView({
        avatarPath: row.avatarPath, initials: row.initials,
        colorSeed: row.userId !== 0 ? row.userId : row.chatId, avatarSize: 46
      });
      Column({ space: 2 }) {
        Text(row.title !== '' ? row.title : $r('app.string.loading_short')).fontSize(16).fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(row.subtitle).fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      if (this.actionKey === row.key) { LoadingProgress().width(19).height(19).color(COLOR_PRIMARY); }
      else {
        Button($r('app.string.bu_unblock')).height(36).fontSize(13).fontColor(COLOR_PRIMARY).backgroundColor(Color.Transparent)
          .enabled(this.actionKey === '').onClick((): void => { this.unblock(row); });
      }
    }
    .width('100%').constraintSize({ minHeight: 62 }).padding({ left: 10, right: 8, top: 6, bottom: 6 });
  }

  @Builder
  pickerSheet() {
    Column({ space: 10 }) {
      Row() {
        Column({ space: 2 }) {
          Text($r('app.string.bu_add')).fontSize(21).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
          Text($r('app.string.bu_add_sub')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
        }.layoutWeight(1).alignItems(HorizontalAlign.Start);
        Button() { SymbolGlyph($r('sys.symbol.xmark')).fontSize(18).fontColor([COLOR_TEXT_SECONDARY]); }
          .width(38).height(38).borderRadius(19).backgroundColor(Color.Transparent)
          .onClick((): void => { this.pickerOpen = false; });
      }.width('100%').height(52);
      TextInput({ text: this.pickerQuery, placeholder: $r('app.string.search_contacts') })
        .height(44).fontSize(15).backgroundColor($r('app.color.surface_alt')).borderRadius(12)
        .padding({ left: 13, right: 13 }).onChange((value: string): void => { this.pickerQuery = value; });
      if (this.pickerState === 'loading') {
        Column() { LoadingProgress().width(30).height(30).color(COLOR_PRIMARY); }
          .layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else if (this.pickerState === 'error') {
        Column({ space: 8 }) {
          Text($r('app.string.contacts_load_failed')).fontSize(15).fontColor(COLOR_TEXT_PRIMARY);
          Button($r('app.string.settings_retry')).onClick((): void => { this.openPicker(); });
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else if (this.filteredPicker().length === 0) {
        Column({ space: 7 }) {
          Text($r('app.string.bu_no_contacts')).fontSize(15).fontColor(COLOR_TEXT_PRIMARY);
          Text($r('app.string.bu_no_contacts_sub')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else {
        List() {
          ForEach(this.filteredPicker(), (user: PickerUser) => {
            ListItem() {
              Row({ space: 12 }) {
                AvatarView({ avatarPath: user.avatarPath, initials: user.initials, colorSeed: user.id, avatarSize: 44 });
                Column({ space: 2 }) {
                  Text(user.name).fontSize(16).fontColor(COLOR_TEXT_PRIMARY).maxLines(1);
                  Text(user.subtitle).fontSize(12).fontColor(COLOR_TEXT_SECONDARY).maxLines(1);
                }.layoutWeight(1).alignItems(HorizontalAlign.Start);
                if (this.actionKey === `block_${user.id}`) {
                  LoadingProgress().width(19).height(19).color(COLOR_PRIMARY);
                } else {
                  SymbolGlyph($r('sys.symbol.nosign')).fontSize(20).fontColor([COLOR_DANGER]);
                }
              }
              .width('100%').height(60).padding({ left: 6, right: 10 })
              .onClick((): void => { this.block(user); });
            }
          }, (user: PickerUser): string => `block_picker_${user.id}`);
        }.layoutWeight(1).width('100%').scrollBar(BarState.Off);
      }
    }
    .width('100%').height('100%').padding({ left: 16, right: 16, top: 4, bottom: this.bottomSafe + 8 });
  }

  build() {
    Column() {
      this.header();
      if (this.loadState === 'loading') {
        Column({ space: 9 }) {
          LoadingProgress().width(34).height(34).color(COLOR_PRIMARY);
          Text($r('app.string.bu_loading')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else if (this.loadState === 'error') {
        Column({ space: 10 }) {
          Text($r('app.string.bu_load_failed')).fontSize(17).fontColor(COLOR_TEXT_PRIMARY);
          Text($r('app.string.bu_no_empty_substitute')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
          Button($r('app.string.settings_reload')).onClick((): void => { this.load(true); });
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else if (this.rows.length === 0) {
        Column({ space: 9 }) {
          SymbolGlyph($r('sys.symbol.nosign')).fontSize(52).fontColor([COLOR_TEXT_SECONDARY]);
          Text($r('app.string.bu_empty')).fontSize(18).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
          Text($r('app.string.bu_empty_sub')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else {
        List() {
          ForEach(this.rows, (row: BlockedRow, index: number) => {
            ListItem() {
              Column() {
                if (index > 0) {
                  Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 68 });
                }
                this.row(row);
              }.width('100%');
            }
          }, (row: BlockedRow): string => row.key);
          ListItem() {
            if (this.pageState === 'loading') {
              Row({ space: 8 }) {
                LoadingProgress().width(18).height(18).color(COLOR_PRIMARY);
                Text($r('app.string.load_more')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
              }.width('100%').height(50).justifyContent(FlexAlign.Center);
            } else if (this.pageState === 'error') {
              Button($r('app.string.load_more_failed')).width('100%').height(48).fontSize(13)
                .fontColor(COLOR_PRIMARY).backgroundColor(Color.Transparent)
                .onClick((): void => { this.load(false); });
            }
          }
        }
        .layoutWeight(1).width('100%').backgroundColor(COLOR_SURFACE).scrollBar(BarState.Off)
        .padding({ left: 4, right: 4, bottom: this.bottomSafe })
        .onReachEnd((): void => { this.load(false); });
      }
    }
    .width('100%').height('100%').backgroundColor(COLOR_PAGE_BG)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .padding({ top: this.topSafe })
    .bindSheet($$this.pickerOpen, this.pickerSheet(), {
      height: SheetSize.LARGE,
      backgroundColor: COLOR_SURFACE,
      dragBar: true,
      systemMaterial: overlayMaterial('dialog')
    });
  }
}
