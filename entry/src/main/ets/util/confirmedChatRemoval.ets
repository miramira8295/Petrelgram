import { RowLeaveChannel } from './rowLeaveChannel';

// 行复用不改变已确认操作的目标；等待后重验账号，失败只恢复对应会话。
export class ConfirmedChatRemoval {
  readonly channel: RowLeaveChannel = new RowLeaveChannel();
  private pending: Set<number> = new Set();

  async perform(chatId: number, animate: boolean, active: () => boolean,
    remove: () => Promise<boolean>): Promise<boolean> {
    if (!active() || this.pending.has(chatId)) { return false; }
    this.pending.add(chatId);
    let success = false;
    try {
      await this.channel.play([chatId], animate);
      if (!active()) { return false; }
      success = await remove();
      return success;
    } finally {
      this.pending.delete(chatId);
      if (!success) { this.channel.restore(chatId); }
    }
  }
}
