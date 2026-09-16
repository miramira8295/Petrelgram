import {
  KEY_POWER_CALL_ANIMATIONS, powerAnimationDuration
} from '../../store/AppSettings';
import { LiveInteractionEntry } from '../../util/liveInteractionPresentation';

const INTERACTION_TEXT: string = '#F3F7F9';
const INTERACTION_SUBTEXT: string = '#80919D';
const INTERACTION_GREEN: string = '#39D98A';
const INTERACTION_ACCENT: string = '#64A8FF';
const INTERACTION_AVATAR_COLORS: string[] = [
  '#4C9AFF', '#9C6ADE', '#E06C75', '#2CB67D', '#E39B3A', '#4CB8C4'
];

function interactionMessageTime(timestamp: number): string {
  const value = new Date(timestamp * 1000);
  const hour = value.getHours().toString().padStart(2, '0');
  const minute = value.getMinutes().toString().padStart(2, '0');
  return `${hour}:${minute}`;
}

// 只有刚到的消息播入场动画。气泡放在 LazyForEach 里，滑动时按需创建的节点同样是新插入的，
// 带自身动画参数的 transition 会跟着播；不是新到的用 IDENTITY 直接出现。
function bubbleTransition(animateIn: boolean): TransitionEffect {
  if (!animateIn) {
    return TransitionEffect.IDENTITY;
  }
  return TransitionEffect.translate({ y: 8 })
    .combine(TransitionEffect.OPACITY)
    .animation({
      duration: powerAnimationDuration(KEY_POWER_CALL_ANIMATIONS, 180), curve: Curve.EaseOut
    });
}

// 复用组件（两个直播页的互动列表都走 LazyForEach）。
@Reusable
@Component
export struct LiveInteractionBubble {
  @Prop message: LiveInteractionEntry;
  // 这条是不是刚到的数据（页面用 KeyedListDataSource.isFresh 判定）。
  @Prop animateIn: boolean = false;

  @Builder
  avatar() {
    if (this.message.senderAvatarPath !== '') {
      Image(this.message.senderAvatarPath.startsWith('/')
        ? `file://${this.message.senderAvatarPath}` : this.message.senderAvatarPath).draggable(false)
        .width(32).height(32).borderRadius(16).objectFit(ImageFit.Cover);
    } else {
      Stack() {
        Circle({ width: 32, height: 32 })
          .fill(INTERACTION_AVATAR_COLORS[
            Math.abs(this.message.colorSeed) % INTERACTION_AVATAR_COLORS.length
          ]);
        Text(this.message.senderInitials)
          .fontSize(12).fontWeight(FontWeight.Medium).fontColor(Color.White);
      }.width(32).height(32);
    }
  }

  build() {
    Row({ space: 8 }) {
      this.avatar();
      if (this.message.emojiOnly) {
        Row({ space: 7 }) {
          Text(this.message.senderName).fontSize(11).fontWeight(FontWeight.Medium)
            .fontColor(this.message.isFromOwner ? INTERACTION_GREEN : INTERACTION_ACCENT)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
          Text(this.message.text).fontSize(28);
        }
        .padding({ left: 10, right: 12, top: 4, bottom: 4 })
        .backgroundColor('#D91A2731').borderRadius(18);
      } else {
        Column({ space: 3 }) {
          Row({ space: 6 }) {
            Text(this.message.senderName)
              .fontSize(11).fontWeight(FontWeight.Medium)
              .fontColor(this.message.isFromOwner ? INTERACTION_GREEN : INTERACTION_ACCENT)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
            if (this.message.isFromOwner) {
              Text($r('app.string.live_host')).fontSize(8).fontWeight(FontWeight.Bold).fontColor('#082018')
                .padding({ left: 5, right: 5, top: 2, bottom: 2 })
                .backgroundColor(INTERACTION_GREEN).borderRadius(6);
            }
            Text(interactionMessageTime(this.message.date)).fontSize(9).fontColor('#738491');
          }
          if (this.message.photoPath !== '') {
            Image(this.message.photoPath.startsWith('/')
              ? `file://${this.message.photoPath}` : this.message.photoPath).draggable(false)
              .width(176).height(108).borderRadius(10)
              .objectFit(ImageFit.Cover).margin({ top: 3 });
          }
          if (this.message.text !== '') {
            Text(this.message.text).fontSize(14).fontColor(INTERACTION_TEXT)
              .lineHeight(19).wordBreak(WordBreak.BREAK_WORD)
              .constraintSize({ maxWidth: 270 });
          }
          if (this.message.sendState === 'pending') {
            Text($r('app.string.sending')).fontSize(9).fontColor(INTERACTION_SUBTEXT);
          } else if (this.message.sendState === 'failed') {
            Text($r('app.string.send_failed')).fontSize(9).fontColor('#FF8190');
          }
        }
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 10, right: 12, top: 7, bottom: 8 })
        .backgroundColor(this.message.isFromOwner ? '#DD19392F' : '#DF17242E')
        .borderRadius({ topLeft: 5, topRight: 16, bottomLeft: 16, bottomRight: 16 });
      }
    }
    .width('100%').alignItems(VerticalAlign.Top)
    .transition(bubbleTransition(this.animateIn));
  }
}
