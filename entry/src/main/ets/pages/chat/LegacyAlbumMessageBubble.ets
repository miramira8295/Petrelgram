import { DrawnAlbumGrid } from './DrawnAlbumGrid';
import { DrawnContentRow } from './DrawnContentRow';
import { MessageTextPresentationCache } from '../../util/messageTextInput';
import { MessageBubbleContext } from './MessageBubbleShell';
import { MessageBubbleText } from './MessageBubbleText';
import { AlbumGroup } from '../../util/collapseAlbums';
import { mediaThumbWidth, BUBBLE_AVATAR_GUTTER_VP } from '../../util/mediaBox';
import { MessageBubbleActions, MessageBubbleRenderData } from './ReusableMessageBubble';
import { chatEnv } from '../../util/chatEnvMirror';
import { AlbumCornerRadiiCache } from '../../util/albumCornerRadii';

// 原生配文/chrome组合路径。所有相册回退条件只影响壳和文字，图片网格
// 统一走DrawnAlbumGrid；视频候选在视频岛管理，不再由此处重复建Map。
@ComponentV2
export struct LegacyAlbumMessageBubble {
  private textInputCache: MessageTextPresentationCache = new MessageTextPresentationCache();
  @Require @Param group: AlbumGroup;
  @Require @Param data: MessageBubbleRenderData;
  @Require @Param actions: MessageBubbleActions;
  @Param nowSec: number = 0;
  @Param jumpFocus: number = 0;
  @Param leaving: number = 0;
  private context: MessageBubbleContext = new MessageBubbleContext();
  private cornerCache: AlbumCornerRadiiCache = new AlbumCornerRadiiCache();
  private env = chatEnv;

  private albumWidth(): number {
    const avatarReserve: number = this.data.isGroup && !this.group.head.isOutgoing
      ? BUBBLE_AVATAR_GUTTER_VP : 0;
    return mediaThumbWidth(this.data.contentWidth, avatarReserve);
  }

  private isPureAlbumBubble(): boolean {
    const head = this.group.head;
    return head.text === '' && this.group.caption === '' && head.translatedText === '' &&
      head.replyToMessageId === 0 && head.reactions.length === 0 &&
      head.forwardFrom === '' &&
      !(this.data.isGroup && !head.isOutgoing && head.senderName !== '' && this.group.showSenderName) &&
      !(this.data.isChannel && head.commentCount > 0);
  }

  private gridCornerRadii(): BorderRadiuses {
    const group = this.group;
    return this.cornerCache.prepare(this.isPureAlbumBubble(), this.env.bubbleRadius,
      group.head.isOutgoing, group.showSenderName, group.showAvatar);
  }

  @Builder
  grid() {
    DrawnAlbumGrid({ group: this.group, data: this.data, actions: this.actions, context: this.context,
      gridWidth: this.albumWidth(), gridCorners: this.gridCornerRadii() });
  }

  @Builder
  content() {
    this.grid();
    if (this.group.caption !== '' || this.group.head.translatedText !== '') {
      MessageBubbleText({ actions: this.actions, context: this.context,
        presentation: this.textInputCache.prepare(this.group.head, this.group.showSenderName, this.data,
          this.group.caption, this.group.captionEntities, 0, 'caption') });
    }
  }

  build() {
    DrawnContentRow({ msg: this.group.head, group: this.group, data: this.data, actions: this.actions,
      nowSec: this.nowSec, jumpFocus: this.jumpFocus, leaving: this.leaving, context: this.context }) {
      this.content();
    }
  }
}
