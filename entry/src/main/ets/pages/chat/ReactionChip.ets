import { ReactionInfo } from '../../store/MessageEntry';
import { reactionKeyFrom } from '../../util/reactions';
import { REACTION_HEIGHT_VP, REACTION_PADDING_VP, reactionCountGap, reactionFill, reactionForeground } from '../../util/reactionPresentation';
import { str } from '../../util/strings';
import { DrawnReactionAvatars } from './DrawnReactionAvatars';
import { ReactionIcon } from './ReactionIcon';

@Styles
function reactionChipNormal() { .opacity(1).scale({ x: 1, y: 1 }) }
@Styles
function reactionChipPressed() { .opacity(.72).scale({ x: .97, y: .94 }) }

// A stable ForEach item receives the current immutable reaction as a Param.
// Counts, colors and peers can update without destroying/restarting its icon.
@ComponentV2
export struct ReactionChip {
  @Require @Param reaction: ReactionInfo;
  @Param outgoing: boolean = false;
  @Param ownerKey: string = '';
  @Param avatarCount: number = 0;
  @Event onToggle: (key: string, chosen: boolean) => void = (): void => {};
  @Event onShow: (key: string) => void = (): void => {};

  private activate(): void {
    const key = reactionKeyFrom(this.reaction.emoji, this.reaction.customEmojiId, this.reaction.isPaid === true);
    if (this.reaction.isPaid) { this.onShow(key); }
    else { this.onToggle(key, this.reaction.isChosen); }
  }
  private show(): void { this.onShow(reactionKeyFrom(this.reaction.emoji, this.reaction.customEmojiId, this.reaction.isPaid === true)); }
  build() {
    Row({ space: reactionCountGap(this.reaction.customEmojiId !== '') }) {
      ReactionIcon({ reaction: this.reaction, outgoing: this.outgoing, ownerKey: this.ownerKey });
      if (this.avatarCount > 0) {
        DrawnReactionAvatars({ senders: this.reaction.recentSenders ?? [], ownerKey: this.ownerKey });
      } else {
        Text(`${this.reaction.count}`).fontSize(12).fontWeight(FontWeight.Medium)
          .fontColor(reactionForeground(this.outgoing, this.reaction.isChosen));
      }
    }
    .backgroundColor(reactionFill(this.outgoing, this.reaction.isChosen))
    .constraintSize({ minHeight: REACTION_HEIGHT_VP }).borderRadius(13)
    .padding({ left: REACTION_PADDING_VP, right: this.avatarCount > 0 ? 0 : REACTION_PADDING_VP, top: 3, bottom: 3 })
    .stateStyles({ normal: reactionChipNormal, pressed: reactionChipPressed })
    .accessibilityGroup(true)
    .accessibilitySelected(this.reaction.isChosen)
    .accessibilityText(`${this.reaction.emoji || str('reactions_custom_emoji')} ${this.reaction.count}`)
    .onClick((): void => this.activate())
    .gesture(LongPressGesture().onAction((): void => this.show()));
  }
}
