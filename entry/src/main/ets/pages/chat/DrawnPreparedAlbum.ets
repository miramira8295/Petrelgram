import { sameDrawnRowData, sameDrawnAlbumInput, sameDrawnAlbumGeometryData } from '../../util/drawnRowInput';
import { UIContext } from '@kit.ArkUI';
import { DrawnRowLayoutEngine } from './DrawnLayoutWarmCache';
import { AlbumGroup } from '../../util/collapseAlbums';
import { MessageBubbleRenderData } from './ReusableMessageBubble';
import { DrawnBubblePlan, DrawnBubbleStyle } from './DrawnBubblePlan';

// Exclusive to one physical host and its child. This is NOT a process cache or
// a shared mutable layout engine. Exact input/style matches permit handoff of
// already measured geometry without a second prepare in the child.
export class DrawnPreparedAlbum {
  readonly group: AlbumGroup;
  readonly data: MessageBubbleRenderData;
  private currentStyle: DrawnBubbleStyle;
  private currentPlan: DrawnBubblePlan;
  get style(): DrawnBubbleStyle { return this.currentStyle; }
  get plan(): DrawnBubblePlan { return this.currentPlan; }
  readonly engine: DrawnRowLayoutEngine | null;
  private ui: UIContext | null;
  constructor(group: AlbumGroup, data: MessageBubbleRenderData, style: DrawnBubbleStyle, plan: DrawnBubblePlan,
    engine: DrawnRowLayoutEngine | null = null, ui: UIContext | null = null) {
    this.group = group; this.data = data; this.currentStyle = style; this.currentPlan = plan; this.engine = engine; this.ui = ui;
  }
  sameInput(group: AlbumGroup, data: MessageBubbleRenderData): boolean { return this.group === group && this.data === data; }
  refresh(style: DrawnBubbleStyle): DrawnBubblePlan | null {
    const plan = this.ui !== null && this.engine !== null ? this.engine.prepare(this.ui, this.group, this.data, style) : null;
    if (plan !== null) { this.currentStyle = style; this.currentPlan = plan; }
    return plan;
  }
  matches(group: AlbumGroup, data: MessageBubbleRenderData, style: DrawnBubbleStyle): boolean {
    return sameDrawnAlbumInput(this.group, group) && sameDrawnRowData(this.data, data) && this.matchesStyle(style);
  }
  sameGeometry(group: AlbumGroup, data: MessageBubbleRenderData, style: DrawnBubbleStyle): boolean {
    return sameDrawnAlbumInput(this.group, group) && sameDrawnAlbumGeometryData(this.data, data) && this.matchesStyle(style);
  }
  private matchesStyle(style: DrawnBubbleStyle): boolean {
    const old = this.style;
    return old.radius === style.radius &&
      old.fontSize === style.fontSize && old.environment === style.environment &&
      old.textEnvironment === style.textEnvironment && old.role === style.role && old.views === style.views;
  }
  height(): number {
    return this.plan.height + (this.group.showSenderName ? 3 : 1) + (this.group.showAvatar ? 3 : 1);
  }
}

// Ordinary owner reference survives V2 Local resets. Only publication changes
// this observed packet; recycled children keep their old input until admission.
@ObservedV2
export class DrawnAlbumPublication {
  @Trace packet: DrawnPreparedAlbum | null = null;
  // Retained descendants can receive recycle without their own reuse callback.
  // A monotonic epoch survives V2 parameter resets, even for the same packet.
  @Trace activationEpoch: number = 0;
  hostActive: boolean = false;
  activate(): void {
    if (this.hostActive) { return; }
    this.hostActive = true;
    this.activationEpoch++;
  }
  deactivate(): void { this.hostActive = false; }
}
