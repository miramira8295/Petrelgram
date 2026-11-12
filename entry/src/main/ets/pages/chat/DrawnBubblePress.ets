import { tableScrollTouched } from '../../util/tableTouchChannel';

// This modifier belongs to the bubble wrapper, outside its jump transform and
// inside deletion capture. It never dims the avatar or adds resident animation.
class DrawnBubblePressModifier implements AttributeModifier<CommonAttribute> {
  private active: boolean;
  constructor(active: boolean) { this.active = active; }
  applyNormalAttribute(node: CommonAttribute): void {
    node.renderGroup(false).opacity(1).scale({ x: 1, y: 1 });
  }
  applyPressedAttribute(node: CommonAttribute): void {
    const on = this.active && !tableScrollTouched();
    const scale = on ? .992 : 1;
    node.renderGroup(on).opacity(on ? .84 : 1).scale({ x: scale, y: scale });
  }
}
export const DRAWN_BUBBLE_PRESS: AttributeModifier<CommonAttribute> = new DrawnBubblePressModifier(true);
export const DRAWN_BUBBLE_PRESS_NONE: AttributeModifier<CommonAttribute> = new DrawnBubblePressModifier(false);
