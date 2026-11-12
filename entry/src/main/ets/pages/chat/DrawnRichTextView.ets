import { DrawnInlineEmojiLayer } from './DrawnInlineEmojiLayer';
import { MessageEntry } from '../../store/MessageEntry';
import { DrawnBusyLink } from './DrawnBusyLink';
import { chatEnv } from '../../util/chatEnvMirror';
import { DrawnRichHit, DrawnRichLink } from '../../util/drawnRichTextPolicy';
import { DrawnRichTextLayout } from './DrawnRichTextLayout';
import { DrawnRichTextPainter } from './DrawnRichTextPainter';
import { a11yRuntimeState } from '../../util/a11yState';

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

  // Capture the plan at registration. Reuse can leave an old recognizer's
  // callback queued after its node has already received a new paragraph.
  private linkClick(plan: DrawnRichTextLayout | null): (event: ClickEvent) => void {
    return (event: ClickEvent): void => {
      if (plan === null || plan !== this.plan) { return; }
      const hit = plan.hitIndex.find(event.x, event.y);
      if (hit === null) { return; }
      if (event.source === SourceType.TouchScreen &&
        (this.touchPlan !== plan || this.touchHit !== hit)) { return; }
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
        if (point === undefined || plan?.hitIndex.find(point.x, point.y) !== this.touchHit) {
          this.touchHit = null; this.painter.clearPress();
        }
        if (event.type === TouchType.Up || (point !== undefined &&
          Math.hypot(point.x - this.touchX, point.y - this.touchY) > 8)) { this.painter.clearPress(); }
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
        .accessibilityText(this.plan?.source.content ?? '')
        .accessibilityLevel(this.plan === null ? 'no' : 'yes');
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
            .accessibilityRole(AccessibilityRoleType.HYPERLINK)
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
