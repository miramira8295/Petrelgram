import { DiceEndFrame } from './DiceEndFrame';
import { replyThumbSrc } from '../../util/replyThumb';
import { DrawnBubblePlan } from './DrawnBubblePlan';
import { DrawnReactionChip } from './DrawnReactionLayout';
import { MessageEntry } from '../../store/MessageEntry';
import { SenderAvatarSpec, SenderAvatarSpecCache } from '../../util/messageBubblePresentation';
import { COLOR_BUBBLE_IN, COLOR_BUBBLE_OUT } from '../../util/theme';
import { MessageSenderAvatar } from './MessageSenderAvatar';

const COMMENT_AVATAR_SLOTS: number[] = [0, 1, 2];

// Only image resources and the reactors popup's geometry anchor remain native.
// Ordinary emoji/count/comment/forward labels never create Text/Row subtrees.
@ComponentV2
export struct DrawnChromeIslands {
  @Param plan: DrawnBubblePlan | null = null;
  @Require @Param msg: MessageEntry;
  @Param chatId: number = 0;
  @Param themeBubbleOut: string = '';
  private avatars: SenderAvatarSpecCache[] = [];

  private avatarAt(index: number): SenderAvatarSpec {
    if (this.avatars[index] === undefined) { this.avatars[index] = new SenderAvatarSpecCache(); }
    return this.avatars[index].prepare(this.msg.commentReplierIds[index] ?? 0, true,
      this.msg.commentReplierAvatarPaths[index] ?? '', '?', 22, false);
  }
  private fill(): ResourceColor { return this.msg.isOutgoing ? this.themeBubbleOut || COLOR_BUBBLE_OUT : COLOR_BUBBLE_IN; }
  private source(path: string): string { return path.startsWith('/') ? `file://${path}` : path; }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if ((this.plan?.quote?.mediaWidthPx ?? 0) > 0) {
        if (this.msg.replyDiceLayers.length > 0) {
          DiceEndFrame({ layers: this.msg.replyDiceLayers, thumbPath: this.msg.replyThumbPath, boxSize: 32 })
            .position({ x: (this.plan?.quoteRect.x ?? 0) + 10, y: (this.plan?.quoteRect.y ?? 0) + 3 });
        } else if (this.msg.replyThumbPath !== '') {
          Image(replyThumbSrc(this.msg.replyThumbPath)).width(32).height(32).draggable(false)
            .borderRadius(this.msg.replyThumbSticker ? 0 : 4)
            .objectFit(this.msg.replyThumbSticker ? ImageFit.Contain : ImageFit.Cover).interpolation(ImageInterpolation.Medium)
            .position({ x: (this.plan?.quoteRect.x ?? 0) + 10, y: (this.plan?.quoteRect.y ?? 0) + 3 });
        }
      }
      ForEach(this.plan?.chrome?.reactions?.images ?? [], (chip: DrawnReactionChip) => {
        if ((chip.reaction?.customEmojiPath ?? '') !== '') {
          Image(this.source(chip.reaction?.customEmojiPath ?? '')).width(15).height(15).objectFit(ImageFit.Contain)
            .draggable(false).position({ x: (this.plan?.chrome?.reactionsX ?? 0) + chip.x + 9,
              y: (this.plan?.chrome?.reactionsY ?? 0) + chip.y + (chip.height - 15) / 2 });
        }
      }, (chip: DrawnReactionChip): string => `${chip.key}:${chip.reaction?.customEmojiPath}:${chip.x}:${chip.y}:${chip.height}`);
      ForEach(COMMENT_AVATAR_SLOTS, (index: number) => {
        if (index < (this.plan?.chrome?.content.avatarCount ?? 0)) {
          MessageSenderAvatar({ spec: this.avatarAt(index) })
            .borderRadius(11).outline({ width: 1.5, color: this.fill(), radius: 11, style: OutlineStyle.SOLID })
            .position({ x: (this.plan?.chrome?.commentsRect.x ?? 0) + index * 14,
              y: (this.plan?.chrome?.commentsRect.y ?? 0) + 10 +
                ((this.plan?.chrome?.commentsRect.height ?? 36) - 36) / 2 });
        }
      }, (index: number): string => `comment_avatar_slot_${index}`);
      if (this.plan?.chrome?.reactions?.arrow !== null && this.plan?.chrome?.reactions?.arrow !== undefined) {
        Row().width(this.plan?.chrome?.reactions?.arrow?.width ?? 0).height(this.plan?.chrome?.reactions?.arrow?.height ?? 0)
          .position({ x: (this.plan?.chrome?.reactionsX ?? 0) + (this.plan?.chrome?.reactions?.arrow?.x ?? 0),
            y: (this.plan?.chrome?.reactionsY ?? 0) + (this.plan?.chrome?.reactions?.arrow?.y ?? 0) })
          .id(`reactors_anchor_${this.chatId}_${this.msg.id}`);
      }
    }.width(this.plan?.width ?? 0).height(this.plan?.height ?? 0)
    .hitTestBehavior(HitTestMode.None).accessibilityLevel('no');
  }
}
