import { promptAction, router } from '@kit.ArkUI';
import { getTdClient } from '../../tdkit/Globals';
import { TdError, TdObject, TdRequest } from '../../tdkit/TdTypes';
import { MemberStatusInfo, getMemberStatus, restrictMember } from '../../store/ChatAdminApi';
import {
  GroupPermissions, MEDIA_PERMISSION_KEYS, PERM_ADD_LINK_PREVIEWS, PERM_CHANGE_INFO,
  PERM_INVITE_USERS, PERM_PIN_MESSAGES, PERM_SEND_AUDIOS, PERM_SEND_DOCUMENTS,
  PERM_SEND_MESSAGES, PERM_SEND_OTHER, PERM_SEND_PHOTOS, PERM_SEND_POLLS,
  PERM_SEND_VIDEOS, PERM_SEND_VIDEO_NOTES, PERM_SEND_VOICE_NOTES,
  RESTRICT_DAY_SECONDS, RESTRICT_MONTH_SECONDS, RESTRICT_WEEK_SECONDS,
  allPermissions, clampToChatPermissions, mediaOnCount, permissionValue,
  permissionsFromTd, restrictUntilDate, withPermission
} from '../../util/chatPermissions';
import {
  MemberHeaderCard, PANEL_CARD_RADIUS, PanelGroupRow, PanelSectionTitle, PanelSwitchRow
} from './MemberPanelParts';
import {
  COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';
import { str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { logE } from '../../util/log';

// 单个成员的「限制」面板：setChatMemberStatus + chatMemberStatusRestricted。
//
// 面板一定是"先读后写"：进来先 getChatMember 把对方现在的 permissions 读出来
// 回填，改哪一项写哪一项。凭空写一组权限会把对方已有的设置冲掉。

interface RestrictParams {
  chatId?: number;
  userId?: number;
  memberName?: string;
  memberInitials?: string;
  memberAvatar?: string;
  memberStatus?: string;
}

interface PermRow {
  key: string;
  label: string;
}

const DURATION_SECONDS: number[] = [
  0, RESTRICT_DAY_SECONDS, RESTRICT_WEEK_SECONDS, RESTRICT_MONTH_SECONDS
];

// 函数而不是常量：str() 要等字符串源装好才有值，模块级常量会把当时的语言
// 固化下来（同 GroupAdminPage.slowModeLabels）。
function durationLabels(): string[] {
  return [str('mm_forever'), str('mm_one_day'), str('mm_one_week'), str('mm_one_month')];
}

function mediaRows(): PermRow[] {
  return [
    { key: PERM_SEND_PHOTOS, label: str('mm_photos') },
    { key: PERM_SEND_VIDEOS, label: str('mm_videos') },
    { key: PERM_SEND_DOCUMENTS, label: str('mm_files') },
    { key: PERM_SEND_AUDIOS, label: str('mm_music') },
    { key: PERM_SEND_VOICE_NOTES, label: str('mm_voice_messages') },
    { key: PERM_SEND_VIDEO_NOTES, label: str('mm_round_videos') },
    { key: PERM_SEND_OTHER, label: str('mm_stickers_gifs') },
    { key: PERM_ADD_LINK_PREVIEWS, label: str('ga_embed_links') },
    { key: PERM_SEND_POLLS, label: str('ga_send_polls') }
  ];
}

@Entry
@Component
struct MemberRestrictPage {
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State loadState: string = 'loading'; // loading | ready | error
  @State busy: boolean = false;
  @State perms: GroupPermissions = allPermissions(true);
  // 群本身的默认权限。成员权限给不过它，所以群里关掉的项在这里直接置灰。
  @State chatPerms: GroupPermissions = allPermissions(true);
  @State mediaExpanded: boolean = false;
  @State durationIndex: number = 0;
  @State memberName: string = '';
  @State memberInitials: string = '?';
  @State memberAvatar: string = '';
  @State memberStatus: string = '';
  private chatId: number = 0;
  private userId: number = 0;
  private active: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    const params = router.getParams() as RestrictParams | undefined;
    this.chatId = params?.chatId ?? 0;
    this.userId = params?.userId ?? 0;
    this.memberName = params?.memberName ?? '';
    this.memberInitials = params?.memberInitials ?? '?';
    this.memberAvatar = params?.memberAvatar ?? '';
    this.memberStatus = params?.memberStatus ?? '';
    this.load();
  }

  aboutToDisappear(): void {
    this.active = false;
  }

  private load(): void {
    if (this.chatId === 0 || this.userId === 0) {
      this.loadState = 'error';
      return;
    }
    this.loadState = 'loading';
    const chatRequest: TdRequest = { '@type': 'getChat' };
    chatRequest['chat_id'] = this.chatId;
    getTdClient().send(chatRequest, 15000).then((chat: TdObject): Promise<MemberStatusInfo> => {
      if (this.active) {
        this.chatPerms = permissionsFromTd(chat['permissions'] as TdObject | undefined);
      }
      return getMemberStatus(this.chatId, this.userId);
    }).then((info: MemberStatusInfo): void => {
      if (!this.active) {
        return;
      }
      // 没被限制过的成员，其有效权限就是群的默认权限——用它回填，开关才和
      // 用户在群里看到的实际情况一致。
      const current: GroupPermissions = info.type === 'chatMemberStatusRestricted'
        ? info.permissions : this.chatPerms;
      this.perms = clampToChatPermissions(current, this.chatPerms);
      this.durationIndex = this.durationIndexOf(info.restrictedUntil);
      this.loadState = 'ready';
    }).catch((error: TdError): void => {
      if (!this.active) {
        return;
      }
      logE(`MemberRestrictPage.load failed: ${error.message}`);
      this.loadState = 'error';
    });
  }

  // 已有的到期时间挑一个最接近的档位。精确回显需要一个日期选择器，这里先
  // 保证"什么都不改就点应用"不会把有限期悄悄变成永久。
  private durationIndexOf(until: number): number {
    if (until <= 0) {
      return 0;
    }
    const remain = until - Math.floor(Date.now() / 1000);
    if (remain <= 0) {
      return 0;
    }
    if (remain <= RESTRICT_DAY_SECONDS) {
      return 1;
    }
    if (remain <= RESTRICT_WEEK_SECONDS) {
      return 2;
    }
    return remain <= RESTRICT_MONTH_SECONDS ? 3 : 0;
  }

  private togglePermission(key: string, value: boolean): void {
    this.perms = withPermission(this.perms, key, value);
  }

  private chooseDuration(): void {
    const labels = durationLabels();
    promptAction.showActionMenu({
      title: str('mm_duration'),
      buttons: labels.map((text: string): promptAction.Button =>
        ({ text, color: '#3390EC' } as promptAction.Button)) as
        [promptAction.Button, promptAction.Button?, promptAction.Button?,
          promptAction.Button?, promptAction.Button?, promptAction.Button?]
    }).then((chosen): void => {
      if (chosen.index >= 0 && chosen.index < DURATION_SECONDS.length) {
        this.durationIndex = chosen.index;
      }
    }).catch((): void => {});
  }

  private apply(): void {
    if (this.busy || this.chatId === 0 || this.userId === 0) {
      return;
    }
    this.busy = true;
    const until = restrictUntilDate(
      Math.floor(Date.now() / 1000), DURATION_SECONDS[this.durationIndex]);
    // isMember 恒为 true：限制的语义是"留在群里但受限"，传 false 会把人踢走。
    restrictMember(this.chatId, this.userId, this.perms, until, true).then((): void => {
      this.busy = false;
      promptAction.showToast({ message: str('ga_done'), duration: 1400 });
      router.back();
    }).catch((error: TdError): void => {
      this.busy = false;
      logE(`MemberRestrictPage.apply failed: ${error.message}`);
      promptAction.showToast({
        message: error.message.indexOf('rights') >= 0 || error.message.indexOf('ADMIN') >= 0
          ? str('ga_no_permission') : str('ga_failed'),
        duration: 1700
      });
    });
  }

  @Builder
  header() {
    Row({ space: 8 }) {
      Button() {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([COLOR_TEXT_PRIMARY]);
      }.width(40).height(40).borderRadius(20).backgroundColor(Color.Transparent)
      .onClick((): void => { router.back(); });
      Text($r('app.string.mm_restrict')).fontSize(22).fontWeight(FontWeight.Bold)
        .fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
      if (this.busy) {
        LoadingProgress().width(20).height(20).color(COLOR_PRIMARY);
      }
    }.width('100%').height(52).padding({ left: 8, right: 16 })
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  permissionsCard() {
    Column() {
      PanelSectionTitle({ titleText: str('mm_access_section') });
      PanelSwitchRow({
        rowLabel: str('ga_send_messages'),
        rowValue: permissionValue(this.perms, PERM_SEND_MESSAGES),
        rowEnabled: permissionValue(this.chatPerms, PERM_SEND_MESSAGES),
        onToggle: (v: boolean): void => { this.togglePermission(PERM_SEND_MESSAGES, v); }
      });
      PanelGroupRow({
        rowLabel: str('mm_send_media_files'),
        onCount: mediaOnCount(this.perms),
        totalCount: MEDIA_PERMISSION_KEYS.length,
        expanded: this.mediaExpanded,
        onTap: (): void => { this.mediaExpanded = !this.mediaExpanded; }
      });
      if (this.mediaExpanded) {
        ForEach(mediaRows(), (row: PermRow) => {
          PanelSwitchRow({
            rowLabel: row.label,
            rowValue: permissionValue(this.perms, row.key),
            rowEnabled: permissionValue(this.chatPerms, row.key),
            indented: true,
            onToggle: (v: boolean): void => { this.togglePermission(row.key, v); }
          });
        }, (row: PermRow): string =>
          `${row.key}_${permissionValue(this.perms, row.key)}_${permissionValue(this.chatPerms, row.key)}`);
      }
      PanelSwitchRow({
        rowLabel: str('ga_invite_users'),
        rowValue: permissionValue(this.perms, PERM_INVITE_USERS),
        rowEnabled: permissionValue(this.chatPerms, PERM_INVITE_USERS),
        onToggle: (v: boolean): void => { this.togglePermission(PERM_INVITE_USERS, v); }
      });
      PanelSwitchRow({
        rowLabel: str('ga_pin_messages'),
        rowValue: permissionValue(this.perms, PERM_PIN_MESSAGES),
        rowEnabled: permissionValue(this.chatPerms, PERM_PIN_MESSAGES),
        onToggle: (v: boolean): void => { this.togglePermission(PERM_PIN_MESSAGES, v); }
      });
      PanelSwitchRow({
        rowLabel: str('ga_change_info'),
        rowValue: permissionValue(this.perms, PERM_CHANGE_INFO),
        rowEnabled: permissionValue(this.chatPerms, PERM_CHANGE_INFO),
        onToggle: (v: boolean): void => { this.togglePermission(PERM_CHANGE_INFO, v); }
      });
    }
    .width('100%').backgroundColor(COLOR_SURFACE).borderRadius(PANEL_CARD_RADIUS);
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
          Button($r('app.string.settings_reload')).onClick((): void => { this.load(); });
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else {
        Scroll() {
          Column({ space: 12 }) {
            MemberHeaderCard({
              memberName: this.memberName, memberInitials: this.memberInitials,
              memberAvatar: this.memberAvatar, memberStatus: this.memberStatus,
              colorSeed: this.userId
            });
            this.permissionsCard();
            Row() {
              Text($r('app.string.mm_duration')).fontSize(15)
                .fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
              Text(durationLabels()[this.durationIndex]).fontSize(14).fontColor(COLOR_PRIMARY);
            }
            .width('100%').height(48).padding({ left: 14, right: 14 })
            .backgroundColor(COLOR_SURFACE).borderRadius(PANEL_CARD_RADIUS)
            .onClick((): void => { this.chooseDuration(); });
            Button($r('app.string.mm_apply'))
              .width('100%').height(44).fontSize(16)
              .enabled(!this.busy)
              .onClick((): void => { this.apply(); });
          }.width('100%').padding({ left: 12, right: 12, bottom: this.bottomSafe + 24 });
        }.layoutWeight(1).width('100%').scrollBar(BarState.Off);
      }
    }
    .width('100%').height('100%').backgroundColor(COLOR_PAGE_BG)
    .padding({ top: this.topSafe });
  }
}
