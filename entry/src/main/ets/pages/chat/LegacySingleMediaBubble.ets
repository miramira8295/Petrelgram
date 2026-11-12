import { DrawnContentRow } from './DrawnContentRow';
import { DrawnSingleMediaSurface } from './DrawnSingleMediaSurface';
import { MessageTextPresentationCache } from '../../util/messageTextInput';
import { MessageEntry } from '../../store/MessageEntry';
import { AlbumGroup } from '../../util/collapseAlbums';
import { MessageBubbleContext } from './MessageBubbleShell';
import { MessageBubbleText } from './MessageBubbleText';
import { MessageBubbleActions, MessageBubbleRenderData } from './ReusableMessageBubble';
import { bubbleMaxWidth, BUBBLE_AVATAR_GUTTER_VP } from '../../util/mediaBox';
import { chatEnv } from '../../util/chatEnvMirror';
import { AlbumCornerRadiiCache } from '../../util/albumCornerRadii';

// Native rich content/material/accessibility remains intact. Media ownership is
// shared with the drawn row; fallback no longer restores the old image tree.
@ComponentV2
export struct LegacySingleMediaBubble {
  @Require @Param msg: MessageEntry;
  @Require @Param group: AlbumGroup;
  @Require @Param data: MessageBubbleRenderData;
  @Require @Param actions: MessageBubbleActions;
  @Param nowSec: number = 0;
  @Param jumpFocus: number = 0;
  @Param leaving: number = 0;
  private context: MessageBubbleContext = new MessageBubbleContext();
  private env = chatEnv;
  private textInputCache: MessageTextPresentationCache = new MessageTextPresentationCache();
  private corners: AlbumCornerRadiiCache = new AlbumCornerRadiiCache();

  private mediaCornerRadii(): BorderRadiuses {
    const m = this.msg;
    const pure = m.text === '' && m.translatedText === '' && m.replyToMessageId === 0 &&
      m.reactions.length === 0 && m.forwardFrom === '' &&
      !(this.data.isGroup && !m.isOutgoing && m.senderName !== '' && this.group.showSenderName) &&
      !(this.data.isChannel && m.commentCount > 0);
    return this.corners.prepare(pure, this.env.bubbleRadius, m.isOutgoing, this.group.showSenderName, this.group.showAvatar);
  }
  private captionWidth(): number {
    return bubbleMaxWidth(this.data.contentWidth,
      this.data.isGroup && !this.msg.isOutgoing ? BUBBLE_AVATAR_GUTTER_VP : 0);
  }
  @Builder
  content() {
    Column() {
      DrawnSingleMediaSurface({ msg: this.msg, data: this.data, actions: this.actions,
        context: this.context, corners: this.mediaCornerRadii() });
    }.alignSelf(ItemAlign.Center);
    if (this.msg.text !== '' || this.msg.translatedText !== '') {
      MessageBubbleText({ actions: this.actions, context: this.context,
        presentation: this.textInputCache.prepare(this.msg, this.group.showSenderName, this.data,
          this.msg.text, this.msg.textEntities, this.captionWidth(), 'caption') });
    }
  }
  build() {
    DrawnContentRow({ msg: this.msg, group: this.group, data: this.data, actions: this.actions,
      nowSec: this.nowSec, jumpFocus: this.jumpFocus, leaving: this.leaving, context: this.context }) {
      this.content();
    }
  }
}
