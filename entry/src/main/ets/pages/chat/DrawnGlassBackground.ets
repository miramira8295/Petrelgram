import { PathShape } from '@kit.ArkUI';
import { DrawnBubblePlan } from './DrawnBubblePlan';
import { BubbleGlassModifier, GLASS_OUTLINE_COLOR, GLASS_OUTLINE_WIDTH } from '../../util/bubbleTail';
import { bubbleGlassFill } from '../../util/surfaceGlass';
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

// One ordinary fill clipped to the existing body/tail geometry. No background
// sampling and no scroll-dependent background node replacement.
@ComponentV2
export struct DrawnGlassBackground {
  @Require @Param plan: DrawnBubblePlan | null;
  @Require @Param fillColor: ResourceColor;
  private env = chatEnv;
  private clipper: DrawnGlassClip = new DrawnGlassClip();
  private tint(_appearanceEpoch: number): ResourceColor { return bubbleGlassFill(this.fillColor); }
  build() {
    Stack() {
      Row().width('100%').height('100%').backgroundColor(this.tint(this.env.appearanceEpoch))
        .borderRadius(this.plan?.shellRadii).attributeModifier(this.clipper.bind(this.plan));
      Path().width('100%').height('100%').commands(this.plan?.shellCommands ?? '')
        .fill(Color.Transparent).stroke(GLASS_OUTLINE_COLOR).strokeWidth(GLASS_OUTLINE_WIDTH);
    }.width(this.plan?.shellWidth ?? 0).height(this.plan?.shellHeight ?? 0)
      .position({ x: this.plan?.bubbleX ?? 0, y: this.plan?.bubbleY ?? 0 })
      .hitTestBehavior(HitTestMode.None).accessibilityLevel('no-hide-descendants');
  }
}
