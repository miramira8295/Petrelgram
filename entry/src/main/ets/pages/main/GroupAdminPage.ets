import { router, promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { getTdClient, getUserStore } from '../../tdkit/Globals';
import { TdError, TdObject, TdRequest } from '../../tdkit/TdTypes';
import {
  AdminRow, GroupPermissions, InviteLinkRow, JoinRequestRow, banMember, createInviteLink,
  defaultPermissions, deleteMessagesFromSender, getAdministrators, getInviteLinks,
  checkUsernameAvailable, deleteMessagesByDate, getJoinRequests, permissionsFromTd,
  processJoinRequest, revokeInviteLink, setAdmin, setChatDescription, setChatPermissions,
  setChatTitle, setPublicUsername, setSlowMode
} from '../../store/ChatAdminApi';
import {
  COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';
import { str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';

const CARD_RADIUS: number = 14;
const SLOW_MODE_VALUES: number[] = [0, 10, 30, 60, 300, 900, 3600];
// A function, not a const: the labels come from str(), which resolves at call
// time. A module-level array would be built before the string source is
// installed and would then keep that language.
function slowModeLabels(): string[] {
  return [str('slow_off'), str('slow_10s'), str('slow_30s'), str('slow_1m'),
    str('slow_5m'), str('slow_15m'), str('slow_1h')];
}

interface AdminPageParams {
  chatId?: number;
}

@Entry
@Component
struct GroupAdminPage {
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State title: string = '';
  @State description: string = '';
  @State permissions: GroupPermissions = defaultPermissions();
  @State slowModeIndex: number = 0;
  @State admins: AdminRow[] = [];
  @State links: InviteLinkRow[] = [];
  @State requests: JoinRequestRow[] = [];
  @State loadState: string = 'loading';
  @State busy: boolean = false;
  @State publicUsername: string = '';
  private supergroupId: number = 0;
  private chatId: number = 0;
  private active: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    const params = router.getParams() as AdminPageParams | undefined;
    this.chatId = params?.chatId ?? 0;
    this.load();
  }

  aboutToDisappear(): void {
    this.active = false;
  }

  private load(): void {
    if (this.chatId === 0) { this.loadState = 'error'; return; }
    this.loadState = 'loading';
    const chatReq: TdRequest = { '@type': 'getChat' };
    chatReq['chat_id'] = this.chatId;
    getTdClient().send(chatReq).then((chat: TdObject): void => {
      if (!this.active) { return; }
      this.title = (chat['title'] as string | undefined) ?? '';
      this.permissions = permissionsFromTd(chat['permissions'] as TdObject | undefined);
      const type = chat['type'] as TdObject | undefined;
      this.supergroupId = type !== undefined
        ? ((type['supergroup_id'] as number | undefined) ?? 0) : 0;
      this.loadState = 'ready';
    }).catch((error: TdError): void => {
      if (!this.active) { return; }
      console.error(`GroupAdminPage.load failed: ${error.message}`);
      this.loadState = 'error';
    });
    getAdministrators(this.chatId).then((rows: AdminRow[]): void => {
      if (this.active) {
        this.admins = rows;
        for (const row of rows) { getUserStore().ensure(row.userId); }
      }
    }).catch((): void => {});
    getInviteLinks(this.chatId, 0).then((rows: InviteLinkRow[]): void => {
      if (this.active) { this.links = rows; }
    }).catch((): void => {});
    getJoinRequests(this.chatId).then((rows: JoinRequestRow[]): void => {
      if (this.active) {
        this.requests = rows;
        for (const row of rows) { getUserStore().ensure(row.userId); }
      }
    }).catch((): void => {});
  }

  private nameOf(userId: number): string {
    const name = getUserStore().displayName(userId);
    return name !== '' ? name : str('ga_user_id', userId);
  }

  private fail(error: TdError, fallback: string): void {
    this.busy = false;
    console.error(`GroupAdminPage: ${error.message}`);
    promptAction.showToast({
      message: error.message.indexOf('rights') >= 0 || error.message.indexOf('ADMIN') >= 0
        ? $r('app.string.ga_no_permission') : fallback,
      duration: 1700
    });
  }

  private saveTitle(): void {
    const value = this.title.trim();
    if (value === '' || this.busy) { return; }
    this.busy = true;
    setChatTitle(this.chatId, value).then((): void => {
      this.busy = false;
      promptAction.showToast({ message: $r('app.string.ga_name_updated'), duration: 1400 });
    }).catch((e: TdError): void => this.fail(e, str('ga_name_failed')));
  }

  private saveDescription(): void {
    if (this.busy) { return; }
    this.busy = true;
    setChatDescription(this.chatId, this.description.trim()).then((): void => {
      this.busy = false;
      promptAction.showToast({ message: $r('app.string.ga_bio_updated'), duration: 1400 });
    }).catch((e: TdError): void => this.fail(e, str('ga_bio_failed')));
  }

  // Permission switches write the whole set — TDLib has no partial update.
  private togglePermission(key: string, value: boolean): void {
    const next: GroupPermissions = {
      sendMessages: key === 'sendMessages' ? value : this.permissions.sendMessages,
      sendMedia: key === 'sendMedia' ? value : this.permissions.sendMedia,
      sendPolls: key === 'sendPolls' ? value : this.permissions.sendPolls,
      sendOther: key === 'sendOther' ? value : this.permissions.sendOther,
      addLinkPreviews: key === 'addLinkPreviews' ? value : this.permissions.addLinkPreviews,
      changeInfo: key === 'changeInfo' ? value : this.permissions.changeInfo,
      inviteUsers: key === 'inviteUsers' ? value : this.permissions.inviteUsers,
      pinMessages: key === 'pinMessages' ? value : this.permissions.pinMessages
    };
    const previous = this.permissions;
    this.permissions = next;
    setChatPermissions(this.chatId, next).catch((e: TdError): void => {
      this.permissions = previous;
      this.fail(e, str('ga_permission_failed'));
    });
  }

  private chooseSlowMode(): void {
    promptAction.showActionMenu({
      title: $r('app.string.ga_slow_mode'),
      buttons: slowModeLabels().slice(0, 6).map((text: string): promptAction.Button =>
        ({ text, color: '#3390EC' } as promptAction.Button)) as
        [promptAction.Button, promptAction.Button?, promptAction.Button?,
          promptAction.Button?, promptAction.Button?, promptAction.Button?]
    }).then((chosen): void => {
      const seconds = SLOW_MODE_VALUES[chosen.index];
      if (seconds === undefined) { return; }
      setSlowMode(this.chatId, seconds).then((): void => {
        this.slowModeIndex = chosen.index;
        promptAction.showToast({
          message: seconds === 0 ? $r('app.string.ga_slow_off') : str('ga_slow_interval', slowModeLabels()[chosen.index]),
          duration: 1600
        });
      }).catch((e: TdError): void => this.fail(e, str('ga_slow_failed')));
    }).catch((): void => {});
  }

  private memberActions(userId: number, isAdmin: boolean): void {
    const labels: string[] = isAdmin ? [str('ga_demote')] : [str('ga_promote'), str('ga_ban'), str('ga_delete_all')];
    promptAction.showActionMenu({
      title: this.nameOf(userId),
      buttons: labels.map((text: string): promptAction.Button =>
        ({ text, color: text.indexOf(str('ga_ban_short')) >= 0 || text.indexOf(str('delete')) >= 0
          ? '#E5484D' : '#3390EC' } as promptAction.Button)) as
        [promptAction.Button, promptAction.Button?, promptAction.Button?,
          promptAction.Button?, promptAction.Button?, promptAction.Button?]
    }).then((chosen): void => {
      const label = labels[chosen.index];
      if (label === undefined) { return; }
      let task: Promise<void> | null = null;
      if (label === str('ga_demote')) { task = setAdmin(this.chatId, userId, false); }
      else if (label === str('ga_promote')) { task = setAdmin(this.chatId, userId, true); }
      else if (label === str('ga_ban')) { task = banMember(this.chatId, userId, false); }
      else { task = deleteMessagesFromSender(this.chatId, userId); }
      task.then((): void => {
        promptAction.showToast({ message: $r('app.string.ga_done'), duration: 1400 });
        this.load();
      }).catch((e: TdError): void => this.fail(e, str('ga_failed')));
    }).catch((): void => {});
  }

  // Public username: '' turns the group private. Availability is checked
  // before writing so the user gets a precise reason.
  private savePublicUsername(): void {
    if (this.busy) { return; }
    const value = this.publicUsername.trim();
    this.busy = true;
    const check: Promise<string> = value === ''
      ? Promise.resolve('') : checkUsernameAvailable(this.chatId, value);
    check.then((issue: string): Promise<void> => {
      if (issue !== '') { return Promise.reject(new TdError(400, issue)); }
      if (this.supergroupId === 0) {
        return Promise.reject(new TdError(400, str('ga_public_supergroup_only')));
      }
      return setPublicUsername(this.supergroupId, value);
    }).then((): void => {
      this.busy = false;
      promptAction.showToast({
        message: value === '' ? $r('app.string.ga_now_private') : str('ga_public_link_set', value), duration: 1900
      });
    }).catch((e: TdError): void => {
      this.busy = false;
      promptAction.showToast({ message: e.message, duration: 1900 });
    });
  }

  private deleteTodayMessages(): void {
    promptAction.showDialog({
      title: $r('app.string.ga_delete_today'),
      message: $r('app.string.ga_delete_today_confirm'),
      buttons: [
        { text: $r('app.string.cancel'), color: '#8E8E93' },
        { text: $r('app.string.delete'), color: '#E5484D' }
      ]
    }).then((result): void => {
      if (result.index !== 1) { return; }
      const now = Math.floor(Date.now() / 1000);
      const start = new Date();
      start.setHours(0, 0, 0, 0);
      deleteMessagesByDate(this.chatId, Math.floor(start.getTime() / 1000), now).then((): void => {
        promptAction.showToast({ message: $r('app.string.deleted'), duration: 1500 });
      }).catch((e: TdError): void => this.fail(e, str('delete_failed')));
    }).catch((): void => {});
  }

  private newInviteLink(): void {
    if (this.busy) { return; }
    this.busy = true;
    createInviteLink(this.chatId, '', 0, false).then((link: string): void => {
      this.busy = false;
      if (link !== '') {
        const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, link);
        pasteboard.getSystemPasteboard().setData(data).catch((): void => {});
        promptAction.showToast({ message: $r('app.string.ga_link_created'), duration: 1700 });
      }
      this.load();
    }).catch((e: TdError): void => this.fail(e, str('ga_link_failed')));
  }

  private handleRequest(userId: number, approve: boolean): void {
    processJoinRequest(this.chatId, userId, approve).then((): void => {
      this.requests = this.requests.filter((r: JoinRequestRow): boolean => r.userId !== userId);
      promptAction.showToast({ message: approve ? $r('app.string.ga_approved') : $r('app.string.ga_declined'), duration: 1400 });
    }).catch((e: TdError): void => this.fail(e, str('ga_handle_failed')));
  }

  @Builder
  header() {
    Row({ space: 8 }) {
      Button() {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([COLOR_TEXT_PRIMARY]);
      }.width(40).height(40).borderRadius(20).backgroundColor(Color.Transparent)
      .onClick((): void => { router.back(); });
      Text($r('app.string.ga_title')).fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .layoutWeight(1);
      if (this.busy) { LoadingProgress().width(20).height(20).color(COLOR_PRIMARY); }
    }.width('100%').height(52).padding({ left: 8, right: 16 }).alignItems(VerticalAlign.Center);
  }

  // 按 key 读状态，而不是把值当 @Builder 参数传进来 —— 值参数不会随
  // @State 变化重新求值，开关会停在旧状态（同 ChatProfilePage.muteButton）。
  private permissionValue(key: string): boolean {
    const p = this.permissions;
    if (key === 'sendMessages') { return p.sendMessages; }
    if (key === 'sendMedia') { return p.sendMedia; }
    if (key === 'sendPolls') { return p.sendPolls; }
    if (key === 'sendOther') { return p.sendOther; }
    if (key === 'addLinkPreviews') { return p.addLinkPreviews; }
    if (key === 'changeInfo') { return p.changeInfo; }
    if (key === 'inviteUsers') { return p.inviteUsers; }
    return p.pinMessages;
  }

  @Builder
  permissionRow(label: string, key: string) {
    Row() {
      Text(label).fontSize(15).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
      Toggle({ type: ToggleType.Switch, isOn: this.permissionValue(key) }).selectedColor(COLOR_PRIMARY)
        .onChange((next: boolean): void => this.togglePermission(key, next));
    }.width('100%').height(48).padding({ left: 14, right: 12 });
  }

  build() {
    Column() {
      this.header();
      if (this.loadState === 'loading') {
        Column({ space: 9 }) {
          LoadingProgress().width(32).height(32).color(COLOR_PRIMARY);
          Text($r('app.string.ga_loading')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else if (this.loadState === 'error') {
        Column({ space: 10 }) {
          Text($r('app.string.load_failed')).fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
          Button($r('app.string.settings_reload')).onClick((): void => this.load());
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else {
        Scroll() {
          Column({ space: 12 }) {
            Column({ space: 10 }) {
              Text($r('app.string.ga_basic')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY).width('100%');
              TextInput({ placeholder: $r('app.string.ng_group_name'), text: this.title })
                .fontSize(15).backgroundColor(COLOR_PAGE_BG).borderRadius(10)
                .onChange((value: string): void => { this.title = value; })
                .onSubmit((): void => this.saveTitle());
              TextArea({ placeholder: $r('app.string.ga_group_bio'), text: this.description })
                .fontSize(14).height(72).backgroundColor(COLOR_PAGE_BG).borderRadius(10)
                .onChange((value: string): void => { this.description = value; });
              Row({ space: 10 }) {
                Button($r('app.string.ga_save_name')).layoutWeight(1).height(38).fontSize(14)
                  .onClick((): void => this.saveTitle());
                Button($r('app.string.ga_save_bio')).layoutWeight(1).height(38).fontSize(14)
                  .onClick((): void => this.saveDescription());
              }.width('100%');
              Row({ space: 8 }) {
                Text('t.me/').fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
                TextInput({ placeholder: $r('app.string.ga_public_username'), text: this.publicUsername })
                  .fontSize(14).layoutWeight(1).backgroundColor(COLOR_PAGE_BG).borderRadius(10)
                  .onChange((value: string): void => { this.publicUsername = value; });
                Button($r('app.string.save')).height(34).fontSize(13)
                  .onClick((): void => this.savePublicUsername());
              }.width('100%');
            }
            .width('100%').padding(14).backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);

            Column() {
              Text($r('app.string.ga_member_rights')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
                .width('100%').padding({ left: 14, top: 12, bottom: 4 });
              this.permissionRow(str('ga_send_messages'), 'sendMessages');
              this.permissionRow(str('ga_send_media'), 'sendMedia');
              this.permissionRow(str('ga_send_polls'), 'sendPolls');
              this.permissionRow(str('ga_send_stickers'), 'sendOther');
              this.permissionRow(str('ga_embed_links'), 'addLinkPreviews');
              this.permissionRow(str('ga_change_info'), 'changeInfo');
              this.permissionRow(str('ga_invite_users'), 'inviteUsers');
              this.permissionRow(str('ga_pin_messages'), 'pinMessages');
              Row() {
                Text($r('app.string.ga_slow_mode')).fontSize(15).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
                Text(slowModeLabels()[this.slowModeIndex]).fontSize(14).fontColor(COLOR_PRIMARY);
              }.width('100%').height(48).padding({ left: 14, right: 14 })
              .onClick((): void => this.chooseSlowMode());
            }.width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);

            if (this.requests.length > 0) {
              Column() {
                Text(str('ga_join_requests', this.requests.length)).fontSize(12)
                  .fontColor(COLOR_TEXT_SECONDARY).width('100%')
                  .padding({ left: 14, top: 12, bottom: 4 });
                ForEach(this.requests, (row: JoinRequestRow) => {
                  Row({ space: 8 }) {
                    Text(this.nameOf(row.userId)).fontSize(15).fontColor(COLOR_TEXT_PRIMARY)
                      .layoutWeight(1).maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis });
                    Button($r('app.string.ga_approve')).height(32).fontSize(13)
                      .onClick((): void => this.handleRequest(row.userId, true));
                    Button($r('app.string.ga_decline')).height(32).fontSize(13)
                      .backgroundColor(COLOR_PAGE_BG).fontColor('#E5484D')
                      .onClick((): void => this.handleRequest(row.userId, false));
                  }.width('100%').height(52).padding({ left: 14, right: 12 });
                }, (row: JoinRequestRow): string => `req_${row.userId}`);
              }.width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
            }

            Column() {
              Text(str('ga_admins', this.admins.length)).fontSize(12)
                .fontColor(COLOR_TEXT_SECONDARY).width('100%')
                .padding({ left: 14, top: 12, bottom: 4 });
              ForEach(this.admins, (row: AdminRow) => {
                Row({ space: 8 }) {
                  Column({ space: 2 }) {
                    Text(this.nameOf(row.userId)).fontSize(15).fontColor(COLOR_TEXT_PRIMARY)
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
                    Text(row.isCreator ? $r('app.string.ga_creator')
                      : (row.customTitle !== '' ? row.customTitle : $r('app.string.ga_admin')))
                      .fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start);
                  if (!row.isCreator) {
                    SymbolGlyph($r('sys.symbol.more')).fontSize(18)
                      .fontColor([COLOR_TEXT_SECONDARY]);
                  }
                }
                .width('100%').height(54).padding({ left: 14, right: 14 })
                .onClick((): void => {
                  if (!row.isCreator) { this.memberActions(row.userId, true); }
                });
              }, (row: AdminRow): string => `adm_${row.userId}`);
            }.width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);

            Column() {
              Row() {
                Text(str('ga_invite_links', this.links.length)).fontSize(12)
                  .fontColor(COLOR_TEXT_SECONDARY).layoutWeight(1);
                Text($r('app.string.ga_new')).fontSize(13).fontColor(COLOR_PRIMARY)
                  .onClick((): void => this.newInviteLink());
              }.width('100%').padding({ left: 14, right: 14, top: 12, bottom: 4 });
              ForEach(this.links, (row: InviteLinkRow) => {
                Row({ space: 8 }) {
                  Column({ space: 2 }) {
                    Text(row.name !== '' ? row.name : (row.isPrimary ? $r('app.string.ga_primary_link') : $r('app.string.ga_invite_link')))
                      .fontSize(14).fontColor(COLOR_TEXT_PRIMARY);
                    Text(row.link).fontSize(11).fontColor(COLOR_TEXT_SECONDARY)
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start);
                  SymbolGlyph($r('sys.symbol.doc')).fontSize(16)
                    .fontColor([COLOR_PRIMARY])
                    .onClick((): void => {
                      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, row.link);
                      pasteboard.getSystemPasteboard().setData(data).then((): void => {
                        promptAction.showToast({ message: $r('app.string.copied'), duration: 1300 });
                      }).catch((): void => {});
                    });
                  if (!row.isPrimary) {
                    SymbolGlyph($r('sys.symbol.trash')).fontSize(16).fontColor(['#E5484D'])
                      .onClick((): void => {
                        revokeInviteLink(this.chatId, row.link).then((): void => {
                          promptAction.showToast({ message: $r('app.string.ga_link_revoked'), duration: 1400 });
                          this.load();
                        }).catch((e: TdError): void => this.fail(e, str('ga_revoke_failed')));
                      });
                  }
                }.width('100%').height(56).padding({ left: 14, right: 14 });
              }, (row: InviteLinkRow): string => `lnk_${row.link}`);
            }.width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);

            Row({ space: 10 }) {
              SymbolGlyph($r('sys.symbol.trash')).fontSize(17).fontColor(['#E5484D']);
              Text($r('app.string.ga_delete_today_all')).fontSize(15).fontColor('#E5484D').layoutWeight(1);
            }
            .width('100%').height(48).padding({ left: 14, right: 14 })
            .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS)
            .onClick((): void => this.deleteTodayMessages());

            Text($r('app.string.ga_note'))
              .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).lineHeight(18).width('100%');
          }.width('100%').padding({ left: 12, right: 12, bottom: this.bottomSafe + 24 });
        }.layoutWeight(1).width('100%').scrollBar(BarState.Off);
      }
    }
    .width('100%').height('100%').backgroundColor(COLOR_PAGE_BG)
    // 没有这一行时页面的布局区停在安全区边界，状态栏那一条不归页面画，
    // 露出的是窗口底色。padding 只负责把内容让开，铺满是另一回事。
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .padding({ top: this.topSafe });
  }
}
