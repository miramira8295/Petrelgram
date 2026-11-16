import { tableScrollTouched } from '../../util/tableTouchChannel';
import { DrawnStage, drawnStageMetrics } from '../../util/drawnStageMetrics';
import { DrawnMediaFrame } from './DrawnMediaFrames';

const EMPTY_DRAWN_ANCHOR: DrawnMediaFrame = {
  width: 0, height: 0, position: { x: 0, y: 0 }, backdrop: '#D7DCE2',
  radius: 0, transition: '', messageId: 0, chatId: 0
};

// Native attributeModifier diffs the complete attribute set before applying it.
// Keep submitting ALL attributes: omitting unchanged ones would RESET them.
// The modifier is owned by one physical slot; no node handles are retained and
// removed/recreated nodes receive a complete initialization automatically.
export class DrawnMediaAnchorAttributes implements AttributeModifier<StackAttribute> {
  private frame: DrawnMediaFrame = EMPTY_DRAWN_ANCHOR;

  bind(frame: DrawnMediaFrame | undefined): DrawnMediaAnchorAttributes {
    this.frame = frame ?? EMPTY_DRAWN_ANCHOR;
    return this;
  }

  applyNormalAttribute(node: StackAttribute): void {
    const traced = drawnStageMetrics.begin(DrawnStage.TileAttributes);
    try {
      const f = this.frame;
      node.size(f).position(f.position).backgroundColor(f.backdrop)
        .borderRadius(f.radius).clip(true).geometryTransition(f.transition)
        .hitTestBehavior(HitTestMode.None);
    } finally { drawnStageMetrics.end(traced); }
  }
}

// O(1) lookup and at most one modifier per physical tile. This pool belongs to
// the mounted row and grows only to its largest displayed album, not messages.
export class DrawnMediaAnchorPool {
  private anchors: DrawnMediaAnchorAttributes[] = [];

  bind(index: number, frame: DrawnMediaFrame | undefined): DrawnMediaAnchorAttributes {
    let anchor = this.anchors[index];
    if (anchor === undefined) {
      anchor = new DrawnMediaAnchorAttributes();
      this.anchors[index] = anchor;
    }
    return anchor.bind(frame);
  }
}

// Geometry and focus share one native diff boundary. drawModifier and menu
// builders are deliberately left in the DSL: ArkUI does not support them in
// AttributeModifier. No extra UI node is added by these attribute objects.
export class DrawnCanvasAttributes implements AttributeModifier<StackAttribute> {
  private box: SizeOptions = { width: 0, height: 0 };
  private focus: ScaleOptions = { x: 1, y: 1, centerX: 0, centerY: '50%' };
  private light: number = 1;
  private drag: boolean = false;
  private press: boolean = false;

  bind(width: number, height: number, scale: number, center: number | string,
    brightness: number, draggable: boolean, press: boolean = false): DrawnCanvasAttributes {
    if (this.box.width !== width || this.box.height !== height) { this.box = { width, height }; }
    if (this.focus.x !== scale || this.focus.centerX !== center) {
      this.focus = { x: scale, y: scale, centerX: center, centerY: '50%' };
    }
    this.light = brightness; this.drag = draggable; this.press = press;
    return this;
  }

  applyNormalAttribute(node: StackAttribute): void {
    const traced = drawnStageMetrics.begin(DrawnStage.CanvasAttributes);
    try { node.size(this.box).scale(this.focus).brightness(this.light).draggable(this.drag).opacity(1).renderGroup(false); }
    finally { drawnStageMetrics.end(traced); }
  }

  // Fade feedback on the existing canvas host replaces an otherwise empty
  // press wrapper. Keep the jump scale independent; deletion opacity belongs
  // to the parent capture node and the avatar is a sibling outside this node.
  applyPressedAttribute(node: StackAttribute): void {
    const on = this.press && !tableScrollTouched();
    node.opacity(on ? .84 : 1).renderGroup(on);
  }
}
