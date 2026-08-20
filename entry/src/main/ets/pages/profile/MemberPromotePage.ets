import { promptAction, router } from '@kit.ArkUI';
import { getTdClient } from '../../tdkit/Globals';
import { TdError, TdObject, TdRequest } from '../../tdkit/TdTypes';
import {
  MemberStatusInfo, demoteMember, getMemberStatus, promoteMember
} from '../../store/ChatAdminApi';
import {
  AdminRights, RIGHT_CHANGE_INFO, RIGHT_DELETE_MESSAGES, RIGHT_DELETE_STORIES,
  RIGHT_EDIT_MESSAGES, RIGHT_EDIT_STORIES, RIGHT_INVITE_USERS, RIGHT_IS_ANONYMOUS,
  RIGHT_MANAGE_VIDEO_CHATS, RIGHT_PIN_MESSAGES, RIGHT_POST_MESSAGES,
  RIGHT_POST_STORIES, RIGHT_PROMOTE_MEMBERS, RIGHT_RESTRICT_MEMBERS,
  STORY_RIGHT_KEYS, adminRightValue, allAdminRights, defaultAdminRights,
  limitAdminRights, storyRightsOnCount, withAdminRight
} from '../../util/adminRights';
import {
  MemberHeaderCard, PANEL_CARD_RADIUS, PanelGroupRow, PanelSectionTitle, PanelSwitchRow
} from './MemberPanelParts';
import {
  COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';
import { str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';

// 单个成员的「提权 / 编辑管理员权限」面板：setChatMemberStatus +
// chatMemberStatusAdministrator，带 custom_title 与 chatAdministratorRights。
//
// 同样是先读后写：进来先把对方现在的 rights 和头衔读出来回填。另外还要读
// **自己**的 rights——授不出去比自己大的权限，界面上先把这些行置灰，而不是
// 让用户点完再吃一个 TDLib 的拒绝。

const DANGER_COLOR: string = '#E5484D';

interface PromoteParams {
  chatId?: number;
  userId?: number;
  memberName?: string;
  memberInitials?: string;
  memberAvatar?: string;
  memberStatus?: string;
  isChannel?: boolean;
}

interface RightRow {
  key: string;
  label: string;
}

function storyRows(): RightRow[] {
  return [
    { key: RIGHT_POST_STORIES, label: str('mm_story_post') },
    { key: RIGHT_EDIT_STORIES, label: str('mm_story_edit') },
    { key: RIGHT_DELETE_STORIES, label: str('mm_story_delete') }
  ];
}

@Entry
@Component
struct MemberPromotePage {
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State loadState: string = 'loading'; // loading | ready | error
  @State busy: boolean = false;
  @State rights: AdminRights = allAdminRights(false);
  // 自己的权限上限。群主是 allAdminRights(true)，与任何集合相交都是原集合。
  @State ownRights: AdminRights = allAdminRights(false);
  @State customTitle: string = '';
  @State isAdmin: boolean = false;
  @State storiesExpanded: boolean = false;
  @State memberName: string = '';
  @State memberInitials: string = '?';
  @State memberAvatar: string = '';
  @State memberStatus: string = '';
  private chatId: number = 0;
  private userId: number = 0;
  private isChannel: boolean = false;
  private active: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    const params = router.getParams() as PromoteParams | undefined;
    this.chatId = params?.chatId ?? 0;
    this.userId = params?.userId ?? 0;
    this.memberName = params?.memberName ?? '';
    this.memberInitials = params?.memberInitials ?? '?';
    this.memberAvatar = params?.memberAvatar ?? '';
    this.memberStatus = params?.memberStatus ?? '';
    this.isChannel = params?.isChannel ?? false;
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
    getTdClient().send({ '@type': 'getMe' } as TdRequest, 15000)
      .then((me: TdObject): Promise<MemberStatusInfo> => {
        const selfId = (me['id'] as number | undefined) ?? 0;
        return getMemberStatus(this.chatId, selfId);
      })
      .then((mine: MemberStatusInfo): Promise<MemberStatusInfo> => {
        if (this.active) {
          this.ownRights = mine.rights;
        }
        return getMemberStatus(this.chatId, this.userId);
      })
      .then((target: MemberStatusInfo): void => {
        if (!this.active) {
          return;
        }
        this.isAdmin = target.type === 'chatMemberStatusAdministrator';
        this.customTitle = target.customTitle;
        // 还不是管理员时给一份常用勾选做起点，但先削到自己有的范围内。
        const proposed: AdminRights = this.isAdmin ? target.rights : defaultAdminRights();
        this.rights = limitAdminRights(proposed, this.ownRights);
        this.loadState = 'ready';
      })
      .catch((error: TdError): void => {
        if (!this.active) {
          return;
        }
        console.error(`MemberPromotePage.load failed: ${error.message}`);
        this.loadState = 'error';
      });
  }

  private toggleRight(key: string, value: boolean): void {
    this.rights = withAdminRight(this.rights, key, value);
  }

  private fail(error: TdError): void {
    this.busy = false;
    console.error(`MemberPromotePage: ${error.message}`);
    promptAction.showToast({
      message: error.message.indexOf('rights') >= 0 || error.message.indexOf('ADMIN') >= 0
        ? str('ga_no_permission') : str('ga_failed'),
      duration: 1700
    });
  }

  private save(): void {
    if (this.busy || this.chatId === 0 || this.userId === 0) {
      return;
    }
    this.busy = true;
    // 再削一次：ownRights 是异步读回来的，理论上可能在编辑期间变小。
    const granted = limitAdminRights(this.rights, this.ownRights);
    promoteMember(this.chatId, this.userId, this.customTitle.trim(), granted).then((): void => {
      this.busy = false;
      promptAction.showToast({ message: str('ga_done'), duration: 1400 });
      router.back();
    }).catch((error: TdError): void => { this.fail(error); });
  }

  private dismiss(): void {
    if (this.busy) {
      return;
    }
    promptAction.showDialog({
      title: str('ga_demote'),
      message: this.memberName,
      buttons: [
        { text: $r('app.string.cancel'), color: '#8E8E93' },
        { text: $r('app.string.ga_demote'), color: DANGER_COLOR }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse): void => {
      if (result.index !== 1) {
        return;
      }
      this.busy = true;
      demoteMember(this.chatId, this.userId).then((): void => {
        this.busy = false;
        promptAction.showToast({ message: str('ga_done'), duration: 1400 });
        router.back();
      }).catch((error: TdError): void => { this.fail(error); });
    }).catch((): void => {});
  }

  @Builder
  header() {
    Row({ space: 8 }) {
      Button() {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([COLOR_TEXT_PRIMARY]);
      }.width(40).height(40).borderRadius(20).backgroundColor(Color.Transparent)
      .onClick((): void => { router.back(); });
      Text(this.isAdmin ? str('mm_edit_admin') : str('mm_promote'))
        .fontSize(22).fontWeight(FontWeight.Bold)
        .fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
      if (this.busy) {
        LoadingProgress().width(20).height(20).color(COLOR_PRIMARY);
      }
    }.width('100%').height(52).padding({ left: 8, right: 16 })
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  rightsCard() {
    Column() {
      PanelSectionTitle({ titleText: str('mm_admin_rights') });
      PanelSwitchRow({
        rowLabel: str('ga_change_info'),
        rowValue: adminRightValue(this.rights, RIGHT_CHANGE_INFO),
        rowEnabled: adminRightValue(this.ownRights, RIGHT_CHANGE_INFO),
        onToggle: (v: boolean): void => { this.toggleRight(RIGHT_CHANGE_INFO, v); }
      });
      // 发布/编辑消息只在频道里有意义，群里给了也没有对应的界面。
      if (this.isChannel) {
        PanelSwitchRow({
          rowLabel: str('mm_post_messages'),
          rowValue: adminRightValue(this.rights, RIGHT_POST_MESSAGES),
          rowEnabled: adminRightValue(this.ownRights, RIGHT_POST_MESSAGES),
          onToggle: (v: boolean): void => { this.toggleRight(RIGHT_POST_MESSAGES, v); }
        });
        PanelSwitchRow({
          rowLabel: str('mm_edit_messages'),
          rowValue: adminRightValue(this.rights, RIGHT_EDIT_MESSAGES),
          rowEnabled: adminRightValue(this.ownRights, RIGHT_EDIT_MESSAGES),
          onToggle: (v: boolean): void => { this.toggleRight(RIGHT_EDIT_MESSAGES, v); }
        });
      }
      PanelSwitchRow({
        rowLabel: str('mm_right_delete_messages'),
        rowValue: adminRightValue(this.rights, RIGHT_DELETE_MESSAGES),
        rowEnabled: adminRightValue(this.ownRights, RIGHT_DELETE_MESSAGES),
        onToggle: (v: boolean): void => { this.toggleRight(RIGHT_DELETE_MESSAGES, v); }
      });
      PanelSwitchRow({
        rowLabel: str('mm_right_restrict'),
        rowValue: adminRightValue(this.rights, RIGHT_RESTRICT_MEMBERS),
        rowEnabled: adminRightValue(this.ownRights, RIGHT_RESTRICT_MEMBERS),
        onToggle: (v: boolean): void => { this.toggleRight(RIGHT_RESTRICT_MEMBERS, v); }
      });
      PanelSwitchRow({
        rowLabel: str('mm_right_invite'),
        rowValue: adminRightValue(this.rights, RIGHT_INVITE_USERS),
        rowEnabled: adminRightValue(this.ownRights, RIGHT_INVITE_USERS),
        onToggle: (v: boolean): void => { this.toggleRight(RIGHT_INVITE_USERS, v); }
      });
      PanelSwitchRow({
        rowLabel: str('ga_pin_messages'),
        rowValue: adminRightValue(this.rights, RIGHT_PIN_MESSAGES),
        rowEnabled: adminRightValue(this.ownRights, RIGHT_PIN_MESSAGES),
        onToggle: (v: boolean): void => { this.toggleRight(RIGHT_PIN_MESSAGES, v); }
      });
      PanelGroupRow({
        rowLabel: str('mm_manage_stories'),
        onCount: storyRightsOnCount(this.rights),
        totalCount: STORY_RIGHT_KEYS.length,
        expanded: this.storiesExpanded,
        onTap: (): void => { this.storiesExpanded = !this.storiesExpanded; }
      });
      if (this.storiesExpanded) {
        ForEach(storyRows(), (row: RightRow) => {
          PanelSwitchRow({
            rowLabel: row.label,
            rowValue: adminRightValue(this.rights, row.key),
            rowEnabled: adminRightValue(this.ownRights, row.key),
            indented: true,
            onToggle: (v: boolean): void => { this.toggleRight(row.key, v); }
          });
        }, (row: RightRow): string =>
          `${row.key}_${adminRightValue(this.rights, row.key)}_${adminRightValue(this.ownRights, row.key)}`);
      }
      PanelSwitchRow({
        rowLabel: str('mm_manage_calls'),
        rowValue: adminRightValue(this.rights, RIGHT_MANAGE_VIDEO_CHATS),
        rowEnabled: adminRightValue(this.ownRights, RIGHT_MANAGE_VIDEO_CHATS),
        onToggle: (v: boolean): void => { this.toggleRight(RIGHT_MANAGE_VIDEO_CHATS, v); }
      });
      PanelSwitchRow({
        rowLabel: str('mm_anonymous'),
        rowValue: adminRightValue(this.rights, RIGHT_IS_ANONYMOUS),
        rowEnabled: adminRightValue(this.ownRights, RIGHT_IS_ANONYMOUS),
        onToggle: (v: boolean): void => { this.toggleRight(RIGHT_IS_ANONYMOUS, v); }
      });
      PanelSwitchRow({
        rowLabel: str('mm_add_admins'),
        rowValue: adminRightValue(this.rights, RIGHT_PROMOTE_MEMBERS),
        rowEnabled: adminRightValue(this.ownRights, RIGHT_PROMOTE_MEMBERS),
        onToggle: (v: boolean): void => { this.toggleRight(RIGHT_PROMOTE_MEMBERS, v); }
      });
      if (!adminRightValue(this.rights, RIGHT_PROMOTE_MEMBERS)) {
        Text($r('app.string.mm_no_add_admins_note'))
          .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).lineHeight(17)
          .width('100%').padding({ left: 14, right: 14, top: 2, bottom: 12 });
      }
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
            Column() {
              PanelSectionTitle({ titleText: str('mm_custom_title') });
              TextInput({ placeholder: $r('app.string.ga_admin'), text: this.customTitle })
                .fontSize(15).backgroundColor(COLOR_PAGE_BG).borderRadius(10)
                .margin({ left: 14, right: 14 })
                .maxLength(16)
                .onChange((value: string): void => { this.customTitle = value; });
              Text($r('app.string.mm_custom_title_hint'))
                .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).lineHeight(17)
                .width('100%').padding({ left: 14, right: 14, top: 8, bottom: 12 });
            }
            .width('100%').backgroundColor(COLOR_SURFACE).borderRadius(PANEL_CARD_RADIUS);

            this.rightsCard();

            Button($r('app.string.save'))
              .width('100%').height(44).fontSize(16)
              .enabled(!this.busy)
              .onClick((): void => { this.save(); });
            if (this.isAdmin) {
              Button($r('app.string.ga_demote'))
                .width('100%').height(44).fontSize(15)
                .backgroundColor(COLOR_SURFACE).fontColor(DANGER_COLOR)
                .enabled(!this.busy)
                .onClick((): void => { this.dismiss(); });
            }
          }.width('100%').padding({ left: 12, right: 12, bottom: this.bottomSafe + 24 });
        }.layoutWeight(1).width('100%').scrollBar(BarState.Off);
      }
    }
    .width('100%').height('100%').backgroundColor(COLOR_PAGE_BG)
    .padding({ top: this.topSafe });
  }
}
