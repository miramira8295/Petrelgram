import { DrawnInlineIconLayer } from './DrawnInlineIconLayer';
import { DrawnMathLayer } from './DrawnMathLayer';
import { DrawnInlineEmojiLayer } from './DrawnInlineEmojiLayer';
import { MessageEntry } from '../../store/MessageEntry';
import { DrawnBusyLink } from './DrawnBusyLink';
import { chatEnv } from '../../util/chatEnvMirror';
import { DrawnRichHit, DrawnRichLink } from '../../util/drawnRichTextPolicy';
import { DrawnRichTextLayout } from './DrawnRichTextLayout';
import { DrawnRichTextPainter } from './DrawnRichTextPainter';
import { a11yRuntimeState } from '../../util/a11yState';

const VIEW_HOLD_SLOP: number = 6;
const VIEW_TAP_MOVE_MAX: number = 8;

@Styles
function drawnLinkIdleStyle() { .backgroundColor(Color.Transparent) }
@Styles
function drawnLinkPressedStyle() { .backgroundColor($r('app.color.select_highlight')) }

@ComponentV2
export struct DrawnRichTextView {
  @Require @Param msg: MessageEntry;
  // Reuse can update this child before its parent's fallback branch removes
  // it. Every independently scheduled node update must accept that empty state.
  @Require @Param plan: DrawnRichTextLayout | null;
  @Event onMetricsChanged: () => void = (): void => {};
  @Event onLinkTap: (link: DrawnRichLink) => void = (_link: DrawnRichLink): void => {};
  private painter: DrawnRichTextPainter = new DrawnRichTextPainter();
  private emptyHits: DrawnRichHit[] = [];
  private emptyRegions: Rectangle[] = [];
  private env = chatEnv;
  private a11yState = a11yRuntimeState;
  private touchPlan: DrawnRichTextLayout | null = null;
  private touchHit: DrawnRichHit | null = null;
  private touchX: number = 0;
  private touchY: number = 0;

  private sameLinkTarget(a: DrawnRichHit | null, b: DrawnRichHit | null): boolean {
    if (a === null || b === null) { return false; }
    if (a === b) { return true; }
    return a.link !== undefined && b.link !== undefined && (a.link.group ?? a.link) === (b.link.group ?? b.link);
  }

  private findNear(plan: DrawnRichTextLayout, x: number, y: number, slop: number): DrawnRichHit | null {
    return slop > 0 && plan.hitIndex.findNear !== undefined
      ? plan.hitIndex.findNear(x, y, slop, slop)
      : plan.hitIndex.find(x, y);
  }

  // Capture the plan at registration. Reuse can leave an old recognizer's
  // callback queued after its node has already received a new paragraph.
  private linkClick(plan: DrawnRichTextLayout | null): (event: ClickEvent) => void {
    return (event: ClickEvent): void => {
      if (plan === null || plan !== this.plan) { return; }
      const touchSource = event.source === SourceType.TouchScreen;
      const hit = touchSource && this.touchPlan === plan && this.touchHit !== null &&
        Math.hypot(event.x - this.touchX, event.y - this.touchY) <= VIEW_TAP_MOVE_MAX
        ? this.findNear(plan, event.x, event.y, VIEW_HOLD_SLOP)
        : plan.hitIndex.find(event.x, event.y);
      if (hit === null) { return; }
      if (touchSource && (this.touchPlan !== plan || !this.sameLinkTarget(this.touchHit, hit))) { return; }
      this.touchHit = null;
      this.painter.clearPress();
      this.onLinkTap(hit.link);
    };
  }

  private linkTouch(plan: DrawnRichTextLayout | null): (event: TouchEvent) => void {
    return (event: TouchEvent): void => {
      if (event.type === TouchType.Down) {
        this.touchPlan = plan;
        const point = event.changedTouches[0];
        this.touchHit = plan !== null && plan === this.plan && event.touches.length === 1 && point !== undefined ?
          plan.hitIndex.find(point.x, point.y) : null;
        this.touchX = point?.x ?? 0; this.touchY = point?.y ?? 0;
        if (this.touchHit !== null) { this.painter.press(this.touchHit, this.getUIContext()); }
        else { this.painter.clearPress(); }
      } else if (event.type === TouchType.Cancel || plan !== this.plan || this.touchPlan !== plan ||
        event.touches.length > 1) {
        this.touchHit = null; this.painter.clearPress();
      } else if (event.type === TouchType.Move || event.type === TouchType.Up) {
        const point = event.changedTouches[0];
        const moved = point === undefined || Math.hypot(point.x - this.touchX, point.y - this.touchY) > VIEW_TAP_MOVE_MAX;
        if (moved) {
          this.touchHit = null;
        } else if (this.touchHit !== null && plan !== null && point !== undefined) {
          const current = this.findNear(plan, point.x, point.y, VIEW_HOLD_SLOP);
          this.touchHit = this.sameLinkTarget(current, this.touchHit) ? current : null;
        }
        if (event.type === TouchType.Up || moved || this.touchHit === null) { this.painter.clearPress(); }
      }
      // Keep propagation/native click arbitration: ancestors still own scrolling,
      // long press and swipe. Touch callbacks only provide press feedback.
    };
  }

  private tapHit(hit: DrawnRichHit): void {
    const plan = this.plan;
    // A removed rectangle may still have a queued click. Membership is checked
    // only on a user tap, never during layout or drawing.
    if (plan !== null && plan.hits.indexOf(hit) >= 0) { this.onLinkTap(hit.link); }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if ((this.plan?.source.links.length ?? 0) > 0 && this.plan?.source.targets.has(this.env.linkNavBusy)) {
        DrawnBusyLink({ plan: this.plan, url: this.env.linkNavBusy });
      }
      Row()
        .width(this.plan?.widthVp ?? 0).height(this.plan?.heightVp ?? 0)
        .drawModifier(this.painter.bind(this.plan))
        .hitTestBehavior(HitTestMode.None)
        .accessibilityText(this.plan?.accessibilityText ?? '')
        .accessibilityLevel(this.plan === null ? 'no' : 'yes');
      if ((this.plan?.icons.length ?? 0) > 0) { DrawnInlineIconLayer({ plan: this.plan }); }
      if ((this.plan?.maths.length ?? 0) > 0) {
        DrawnMathLayer({ plan: this.plan, onMetricsChanged: (): void => this.onMetricsChanged() });
      }
      if ((this.plan?.emojis.length ?? 0) > 0) {
        DrawnInlineEmojiLayer({ plan: this.plan, msg: this.msg });
      }
      if (this.a11yState.active) {
        ForEach(this.plan?.hits ?? this.emptyHits, (hit: DrawnRichHit) => {
          Row()
            .width(hit.widthVp).height(hit.heightVp)
            .position({ x: hit.x, y: hit.y })
            .stateStyles({ normal: drawnLinkIdleStyle, pressed: drawnLinkPressedStyle })
            .accessibilityText(hit.link.accessibilityLabel)
            .accessibilityDescription(hit.link.url)
            .accessibilityRole(hit.link.action === undefined ? AccessibilityRoleType.HYPERLINK : AccessibilityRoleType.BUTTON)
            .accessibilityLevel(hit.accessible ? 'yes' : 'no')
            .onClick((): void => { this.tapHit(hit); });
        }, (hit: DrawnRichHit): string => hit.key);
      } else if ((this.plan?.hits.length ?? 0) > 0) {
        Row()
          .width(this.plan?.widthVp ?? 0).height(this.plan?.heightVp ?? 0)
          .responseRegion(this.plan?.hitIndex.regions ?? this.emptyRegions)
          .accessibilityLevel('no')
          .onTouch(this.linkTouch(this.plan))
          .onClick(this.linkClick(this.plan));
      }
    }
    .width(this.plan?.widthVp ?? 0).height(this.plan?.heightVp ?? 0)
    .accessibilityGroup(false);
    // Only link rectangles own clicks. Other text/blank space keeps the
    // ancestor's menu, long-press and swipe behavior; no new gesture recognizer.
  }
}
