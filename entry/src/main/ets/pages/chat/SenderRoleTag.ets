
import { senderRoleFor, senderRoleKey, subscribeSenderRole } from '../../util/senderRoleChannel';

// 气泡里发送者名字旁边那枚身份标签（管理员 / 创建者 / 自定义头衔）。
//
// 自订阅而不是由页面把标签传下来：管理员名单是异步取的，比消息行晚到。走
// @Prop 的话，标签一到货整页每行都要重建；这里只让这一枚小标签自己换字。
// 同一套做法见 senderAvatarChannel 的注释。
// P4 批 4：迁 @ComponentV2（配方同批 1/2/3b/3c）。复用路径在 aboutToReuse
// 同步重挂（@Param 已是新值），@Monitor 只兜非复用路径——这一处挂错的后果
// 比图片更严重：会把「管理员/群主」身份标签贴到别人的消息上。
@ComponentV2
export struct SenderRoleTag {
  @Param chatId: number = 0;
  @Param senderId: number = 0;
  // 群成员标签（消息自带的 sender_tag）。有它就显示它——标签是打给所有人看
  // 的；没有再落到管理员头衔那条异步通道。
  @Param presetTag: string = '';
  @Local private label: string = '';
  private unsub: (() => void) | null = null;

  private attachRoleChannel(chatId: number, senderId: number): void {
    this.detachRoleChannel();
    const key: string = senderRoleKey(chatId, senderId);
    this.label = senderRoleFor(key);
    this.unsub = subscribeSenderRole(key, (next: string): void => {
      this.label = next;
    });
  }

  private detachRoleChannel(): void {
    if (this.unsub !== null) {
      this.unsub();
      this.unsub = null;
    }
  }

  @Monitor('chatId', 'senderId')
  onSenderChanged(): void {
    this.attachRoleChannel(this.chatId, this.senderId);
  }

  aboutToAppear(): void {
    this.attachRoleChannel(this.chatId, this.senderId);
  }

  aboutToRecycle(): void {
    this.detachRoleChannel();
  }

  aboutToReuse(): void {
    // @Param 已是新值（批 0.5 判读）：同步重挂+播种（attach 内先读通道现值）。
    this.attachRoleChannel(this.chatId, this.senderId);
  }

  aboutToDisappear(): void {
    this.detachRoleChannel();
  }

  build() {
    // Keep one node across ordinary/admin/custom-tag senders. Visibility.None
    // removes it from layout, preserving the old no-gap appearance while a
    // recycled sender row no longer has to create or destroy this Text node.
    Text(this.presetTag !== '' ? this.presetTag : this.label)
      // 不跟强调色（COLOR_PRIMARY）走：深色模式的胶囊底是深蓝，中蓝的强调色
      // 压上去看不清。tag_text 按主题各给一档，保证和 selected_pill 有对比。
      .fontSize(11).fontColor($r('app.color.tag_text'))
      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      .constraintSize({ maxWidth: 88 })
      .padding({ left: 6, right: 6, top: 1, bottom: 1 })
      .backgroundColor($r('app.color.selected_pill'))
      .borderRadius(7)
      .flexShrink(0)
      .visibility(this.presetTag !== '' || this.label !== ''
        ? Visibility.Visible : Visibility.None);
  }
}
