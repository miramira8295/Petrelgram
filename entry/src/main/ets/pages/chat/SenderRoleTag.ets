import { COLOR_PRIMARY } from '../../util/theme';
import { senderRoleFor, senderRoleKey, subscribeSenderRole } from '../../util/senderRoleChannel';

// 气泡里发送者名字旁边那枚身份标签（管理员 / 创建者 / 自定义头衔）。
//
// 自订阅而不是由页面把标签传下来：管理员名单是异步取的，比消息行晚到。走
// @Prop 的话，标签一到货整页每行都要重建；这里只让这一枚小标签自己换字。
// 同一套做法见 senderAvatarChannel 的注释。
@Component
export struct SenderRoleTag {
  @Prop chatId: number;
  @Prop senderId: number;
  @State private label: string = '';
  private unsub: (() => void) | null = null;

  aboutToAppear(): void {
    const key: string = senderRoleKey(this.chatId, this.senderId);
    this.label = senderRoleFor(key);
    this.unsub = subscribeSenderRole(key, (next: string): void => {
      this.label = next;
    });
  }

  aboutToDisappear(): void {
    if (this.unsub !== null) {
      this.unsub();
      this.unsub = null;
    }
  }

  build() {
    // 普通成员没有标签，整行不占位——否则每条消息旁边都留一块空白。
    if (this.label !== '') {
      Text(this.label)
        .fontSize(11).fontColor(COLOR_PRIMARY)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: 88 })
        .padding({ left: 6, right: 6, top: 1, bottom: 1 })
        .backgroundColor($r('app.color.selected_pill'))
        .borderRadius(7)
        .flexShrink(0);
    }
  }
}
