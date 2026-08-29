import { AvatarView } from '../chatlist/AvatarView';
import {
  COLOR_PRIMARY, COLOR_SURFACE, COLOR_TEXT_PRIMARY, COLOR_ICON_SECONDARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';

// 限制面板和提权面板共用的几块积木。
//
// 都做成 @Component 而不是 @Builder：带多个参数的 @Builder 在参数变化时不会
// 重新求值，开关会停在旧状态（GroupAdminPage 里已经为此绕过一次）。@Prop 走
// 的是真正的单向同步，父组件改了 @State 子组件就重绘。

export const PANEL_CARD_RADIUS: number = 14;

@Component
export struct MemberHeaderCard {
  @Prop memberName: string = '';
  @Prop memberInitials: string = '?';
  @Prop memberAvatar: string = '';
  @Prop memberStatus: string = '';
  @Prop colorSeed: number = 0;

  build() {
    Row({ space: 12 }) {
      AvatarView({
        avatarPath: this.memberAvatar, initials: this.memberInitials,
        colorSeed: this.colorSeed, avatarSize: 54
      });
      Column({ space: 3 }) {
        Text(this.memberName)
          .fontSize(17).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(this.memberStatus)
          .fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
      }.alignItems(HorizontalAlign.Start).layoutWeight(1);
    }
    .width('100%').padding(14)
    .backgroundColor(COLOR_SURFACE).borderRadius(PANEL_CARD_RADIUS)
    .alignItems(VerticalAlign.Center);
  }
}

@Component
export struct PanelSwitchRow {
  @Prop rowLabel: string = '';
  @Prop rowValue: boolean = false;
  // 自己没有的权限授不出去，群默认关掉的权限也开不了——这类行直接置灰，
  // 而不是等 TDLib 拒了再弹提示。
  @Prop rowEnabled: boolean = true;
  @Prop indented: boolean = false;
  onToggle: (value: boolean) => void = (): void => {};

  build() {
    Row() {
      Text(this.rowLabel)
        .fontSize(15)
        .fontColor(this.rowEnabled ? COLOR_TEXT_PRIMARY : COLOR_TEXT_SECONDARY)
        .layoutWeight(1)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
      Toggle({ type: ToggleType.Switch, isOn: this.rowValue })
        .selectedColor(COLOR_PRIMARY)
        .enabled(this.rowEnabled)
        .onChange((next: boolean): void => {
          if (next !== this.rowValue) {
            this.onToggle(next);
          }
        });
    }
    .width('100%').height(48)
    .padding({ left: this.indented ? 30 : 14, right: 12 })
    .opacity(this.rowEnabled ? 1 : 0.55);
  }
}

// 可展开的子组标题，右边是「已开项/总项」。
@Component
export struct PanelGroupRow {
  @Prop rowLabel: string = '';
  @Prop onCount: number = 0;
  @Prop totalCount: number = 0;
  @Prop expanded: boolean = false;
  onTap: () => void = (): void => {};

  build() {
    Row({ space: 8 }) {
      Text(this.rowLabel).fontSize(15).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
      Text(`${this.onCount}/${this.totalCount}`)
        .fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
      SymbolGlyph(this.expanded
        ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
        .fontSize(14).fontColor([COLOR_ICON_SECONDARY]);
    }
    .width('100%').height(48).padding({ left: 14, right: 14 })
    .onClick((): void => { this.onTap(); });
  }
}

@Component
export struct PanelSectionTitle {
  @Prop titleText: string = '';

  build() {
    Text(this.titleText)
      .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).width('100%')
      .padding({ left: 14, top: 12, bottom: 4 });
  }
}
