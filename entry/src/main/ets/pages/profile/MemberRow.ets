import { SymbolGlyphModifier } from '@kit.ArkUI';
import { AvatarView } from '../chatlist/AvatarView';
import { MemberItem } from '../../store/ChatProfileStore';
import { MEMBER_ROLE_CREATOR, MEMBER_ROLE_NONE } from '../../util/memberRole';
import {
  MEMBER_ACTION_BAN, MEMBER_ACTION_DELETE_MESSAGES, MEMBER_ACTION_PROMOTE,
  MEMBER_ACTION_REMOVE, MEMBER_ACTION_RESTRICT, MEMBER_ACTION_TITLE, MemberMenuOptions,
  noMemberMenu
} from '../../util/memberMenu';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { str } from '../../util/strings';

// 成员列表里的一行 + 它的长按菜单。
//
// 单独成组件而不是留在 ChatProfilePage 的 ForEach 里：bindContextMenu 要的是
// 一个不带参数的 @Builder（带参数的 @Builder 内部 UI 不会随状态刷新），组件
// 里的 @Prop 才能让菜单跟着权限变化重建。

@Component
export struct MemberRow {
  @Prop member: MemberItem;
  @Prop options: MemberMenuOptions = noMemberMenu();
  @Prop showDivider: boolean = false;
  onOpenProfile: (userId: number) => void = (): void => {};
  onAction: (action: string) => void = (): void => {};

  @Styles
  rowNormalStyle() {
    .backgroundColor(Color.Transparent)
  }

  @Styles
  rowPressedStyle() {
    .backgroundColor($r('app.color.press_overlay'))
  }

  // 标签文案：有自定义头衔就用它，否则按身份给默认词。
  private roleLabel(): string {
    if (this.member.roleTitle !== '') {
      return this.member.roleTitle;
    }
    return this.member.role === MEMBER_ROLE_CREATOR ? str('ga_creator') : str('ga_admin');
  }

  @Builder
  contextMenu() {
    Menu() {
      if (this.options.showPromote) {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.person_badge_plus')),
          content: this.options.promoteIsEdit ? str('mm_edit_admin') : str('mm_promote')
        }).onClick((): void => { this.onAction(MEMBER_ACTION_PROMOTE); });
      }
      // 「编辑标签」紧跟在提权后面：两者都是管理员相关，而改称呼比调权限
      // 高频得多，放前面少一次误点。
      if (this.options.showEditTitle) {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.square_and_pencil')),
          content: str('ga_edit_title')
        }).onClick((): void => { this.onAction(MEMBER_ACTION_TITLE); });
      }
      if (this.options.showRestrict) {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.lock_fill')),
          content: str('mm_restrict')
        }).onClick((): void => { this.onAction(MEMBER_ACTION_RESTRICT); });
      }
      if (this.options.showBan) {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.nosign')),
          content: str('ga_ban_short')
        }).onClick((): void => { this.onAction(MEMBER_ACTION_BAN); });
      }
      if (this.options.showRemove) {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.xmark_circle')),
          content: str('ga_remove_member')
        }).onClick((): void => { this.onAction(MEMBER_ACTION_REMOVE); });
      }
      if (this.options.showDeleteMessages) {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.trash')),
          content: str('ga_delete_all')
        }).onClick((): void => { this.onAction(MEMBER_ACTION_DELETE_MESSAGES); });
      }
    }
  }

  @Builder
  rowBody() {
    Row({ space: 10 }) {
      AvatarView({
        avatarPath: this.member.avatarPath, initials: this.member.initials,
        colorSeed: this.member.userId, avatarSize: 46
      });
      Column({ space: 2 }) {
        Text(this.member.name).fontSize(15.5).fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(this.member.status).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
      }.alignItems(HorizontalAlign.Start).layoutWeight(1);
      // 身份/成员标签。普通成员默认不挂（避免整列都是标签），但被打了
      // chatMemberTag 的成员例外——标签就是打给所有人看的。
      if (this.member.role !== MEMBER_ROLE_NONE || this.member.tag !== '') {
        Text(this.member.tag !== '' ? this.member.tag : this.roleLabel())
          .fontSize(11.5).fontColor($r('app.color.tag_text'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: 96 })
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .backgroundColor($r('app.color.selected_pill'))
          .borderRadius(9)
          .flexShrink(0);
      }
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(13).fontColor([COLOR_TEXT_SECONDARY]);
    }
    .width('100%').padding({ left: 15, right: 13, top: 11, bottom: 11 })
    .alignItems(VerticalAlign.Center)
    .stateStyles({ normal: this.rowNormalStyle, pressed: this.rowPressedStyle })
    .onClick((): void => { this.onOpenProfile(this.member.userId); });
  }

  build() {
    Column() {
      // 一项管理权限都没有就不挂菜单：空菜单比没有菜单更让人困惑。菜单只能
      // 整块挂上或不挂，所以这里分两支，而不是给 bindContextMenu 传开关。
      if (this.options.anyVisible) {
        Column() {
          this.rowBody();
        }
        .width('100%')
        .bindContextMenu(this.contextMenu, ResponseType.LongPress);
      } else {
        this.rowBody();
      }
      if (this.showDivider) {
        // 玻璃上的分隔线要更淡：0.7 的实线在半透明底上显得很硬。
        Divider().color($r('app.color.divider')).opacity(0.5).strokeWidth(0.5)
          .margin({ left: 67 });
      }
    }.width('100%');
  }
}
