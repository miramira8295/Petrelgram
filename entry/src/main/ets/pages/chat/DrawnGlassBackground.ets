import { PathShape } from '@kit.ArkUI';
import { DrawnBubblePlan } from './DrawnBubblePlan';
import { BubbleGlassModifier, GLASS_OUTLINE_COLOR, GLASS_OUTLINE_WIDTH } from '../../util/bubbleTail';
import { bubbleGlassFill, bubbleGlassBlurStyle } from '../../util/surfaceGlass';
import { chatEnv } from '../../util/chatEnvMirror';

class DrawnGlassClip {
  private commands: string = '';
  private current: BubbleGlassModifier = new BubbleGlassModifier(false, null);
  bind(plan: DrawnBubblePlan | null): BubbleGlassModifier {
    const commands = plan?.shellCommands ?? '';
    if (commands !== this.commands) {
      this.commands = commands;
      this.current = new BubbleGlassModifier(commands !== '', commands !== '' ? new PathShape({ commands }) : null);
    }
    return this.current;
  }
}

// Material is an OS compositor layer. It uses the exact drawn outline and
// measured geometry; no size callback, duplicate paragraph or replacement row.
@ComponentV2
export struct DrawnGlassBackground {
  @Require @Param plan: DrawnBubblePlan | null;
  @Require @Param fillColor: ResourceColor;
  private env = chatEnv;
  private clipper: DrawnGlassClip = new DrawnGlassClip();
  private tint(_appearanceEpoch: number): ResourceColor { return bubbleGlassFill(this.fillColor); }
  private blurActive(_appearanceEpoch: number): boolean {
    return !this.env.scrollActive && bubbleGlassBlurStyle() !== undefined;
  }
  build() {
    Stack() {
      // Recreate only this background node when removing legacy blur. Passing
      // undefined alone does not reliably remove a previously mounted blur.
      if (!this.blurActive(this.env.appearanceEpoch)) {
        Row().width('100%').height('100%').backgroundColor(this.tint(this.env.appearanceEpoch))
          .borderRadius(this.plan?.shellRadii).attributeModifier(this.clipper.bind(this.plan));
      } else {
        Row().width('100%').height('100%').backgroundColor(this.tint(this.env.appearanceEpoch))
          .backgroundBlurStyle(bubbleGlassBlurStyle()).borderRadius(this.plan?.shellRadii)
          .attributeModifier(this.clipper.bind(this.plan));
      }
      Path().width('100%').height('100%').commands(this.plan?.shellCommands ?? '')
        .fill(Color.Transparent).stroke(GLASS_OUTLINE_COLOR).strokeWidth(GLASS_OUTLINE_WIDTH);
    }.width(this.plan?.shellWidth ?? 0).height(this.plan?.shellHeight ?? 0)
      .position({ x: this.plan?.bubbleX ?? 0, y: this.plan?.bubbleY ?? 0 })
      .hitTestBehavior(HitTestMode.None).accessibilityLevel('no-hide-descendants');
  }
}
