import { AlbumGroup } from '../../util/collapseAlbums';
import { MessageBubbleActions, MessageBubbleRenderData } from './ReusableMessageBubble';
import { LightweightPlainTextBubble } from './LightweightPlainTextBubble';
import { LegacyTextMessageBubble } from './LegacyTextMessageBubble';

// Fallback preserves each original text renderer and its public behavior.
@ComponentV2
export struct LegacyTextRow {
  @Require @Param group: AlbumGroup;
  @Require @Param data: MessageBubbleRenderData;
  @Require @Param actions: MessageBubbleActions;
  @Param nowSec: number = 0;
  @Param jumpFocus: number = 0;
  @Param leaving: number = 0;
  build() {
    if (this.data.lightweightPlainText && this.group.head.translatedText === '') {
      LightweightPlainTextBubble({
        jumpFocus: this.jumpFocus,
        leaving: this.leaving,
        msg: this.group.head,
        nowSec: this.nowSec,
        chatId: this.data.chatId,
        contentWidth: this.data.contentWidth,
        isGroup: this.data.isGroup,
        themeBubbleOut: this.data.themeBubbleOut,
        showUnreadDivider: this.data.showUnreadDivider,
        dividerIsResume: this.data.dividerIsResume === true,
        dateLabel: this.group.dateLabel,
        editingActive: this.data.editingActive,
        canReply: this.data.canReply,
        isPinnedMsg: this.data.isPinnedMsg,
        canReport: this.data.canReport,
        showAvatar: this.group.showAvatar,
        showSenderName: this.group.showSenderName,
        animateIn: this.data.animateIn,
        memberIds: this.group.memberIds,
        actions: this.actions
      });
    } else {
      LegacyTextMessageBubble({ msg: this.group.head, group: this.group, data: this.data, actions: this.actions,
        nowSec: this.nowSec, jumpFocus: this.jumpFocus, leaving: this.leaving });
    }
  }
}
