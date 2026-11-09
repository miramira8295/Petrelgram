import { FolderChatSummary } from '../../store/FolderApi';
import { AvatarView } from '../chatlist/AvatarView';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';

// 文件夹编辑 / 文件夹邀请链接两处"选会话"面板共用的一行。候选是整份会话列表，多的账号上千个，
// 所以走 LazyForEach + 复用组件：滚出去的行进复用池，滚进来的行从池里取。
//
// 点击挂在页面的 ListItem 上（闭包随行 key 重建）。复选框**只显示、不接收触摸**：带
// onChange 的 Toggle 在 isOn 被程序改写时也会回调（FolderEditPage 原注释记过：渲染中
// 重入、直到输入看门狗杀掉应用），而复用节点换数据正是一次程序改写。
@Reusable
@Component
export struct FolderChatPickRow {
  @Prop chat: FolderChatSummary;
  @Prop checked: boolean = false;
  // 标题下的一行小字（会话类型）。空串时只显示标题。
  @Prop subtitle: string = '';
  @Prop avatarSize: number = 40;

  @Styles
  pressNormal() {
    .opacity(1).scale({ x: 1, y: 1 }).backgroundColor(Color.Transparent)
  }

  @Styles
  pressDown() {
    .opacity(0.7).scale({ x: 0.97, y: 0.97 }).backgroundColor($r('app.color.surface_alt'))
  }

  build() {
    Row({ space: 12 }) {
      Row({ space: 12 }) {
        AvatarView({
          avatarPath: this.chat.avatarPath, initials: this.chat.initials,
          colorSeed: this.chat.id, avatarSize: this.avatarSize
        });
        if (this.subtitle !== '') {
          Column({ space: 2 }) {
            Text(this.chat.title).fontSize(16).fontColor(COLOR_TEXT_PRIMARY)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
            Text(this.subtitle).fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
          }.layoutWeight(1).alignItems(HorizontalAlign.Start);
        } else {
          Text(this.chat.title).fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        }
      }.layoutWeight(1);
      Toggle({ type: ToggleType.Checkbox, isOn: this.checked })
        .selectedColor(COLOR_PRIMARY).hitTestBehavior(HitTestMode.None);
    }
    .width('100%').padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .stateStyles({ normal: this.pressNormal, pressed: this.pressDown });
  }
}
