import { DrawnGiveawayAudienceLayout, DrawnGiveawayAudiencePainter, DrawnGiveawayPeerSlot } from './DrawnGiveawayAudienceLayout';
import { DrawnGiveawayAudienceController } from './DrawnGiveawayAudienceController';
import { a11yRuntimeState } from '../../util/a11yState';
import { str } from '../../util/strings';
import { logW } from '../../util/log';

@ComponentV2
export struct DrawnGiveawayAudience {
  @Require @Param model: DrawnGiveawayAudienceLayout;
  @Param ownerKey: string = '';
  @Event onActivate: (id: number, user: boolean) => void = (): void => {};
  private painter: DrawnGiveawayAudiencePainter = new DrawnGiveawayAudiencePainter();
  private media: DrawnGiveawayAudienceController = new DrawnGiveawayAudienceController();
  private a11y = a11yRuntimeState;
  private attached: boolean = false;
  private generation: number = 0;
  private touchGeneration: number = -1;
  private offPaint: (() => void) | null = null;
  @Local private semanticRevision: number = 0;
  private bind(): void {
    this.generation++; this.touchGeneration = -1; this.offPaint?.(); this.offPaint = null;
    if (!this.attached) { return; }
    this.offPaint = this.model.onPaint((): void => {
      this.painter.invalidate(); if (this.a11y.active) { this.semanticRevision++; }
    });
    try { this.media.bind(this.getUIContext(), this.model, this.ownerKey); }
    catch (error) { this.media.dispose(); logW(`Giveaway audience: ${(error as Error).message}`); }
  }
  @Monitor('model', 'ownerKey') private sourceChanged(): void { this.bind(); }
  aboutToAppear(): void { this.attached = true; this.bind(); }
  aboutToReuse(): void { this.attached = true; this.bind(); }
  aboutToRecycle(): void {
    this.attached = false; this.generation++; this.touchGeneration = -1;
    this.offPaint?.(); this.offPaint = null; this.media.dispose();
  }
  aboutToDisappear(): void { this.aboutToRecycle(); }
  private semanticLabel(slot: DrawnGiveawayPeerSlot, _revision: number): string {
    return slot.name || str(slot.user ? 'cb_telegram_user' : 'bu_unknown_channel');
  }
  private activate(index: number): void {
    const slot = this.model.slots[index];
    if (this.attached && slot !== undefined) { this.onActivate(slot.id, slot.user); }
  }
  private semanticClick(index: number): () => void {
    const model = this.model, owner = this.ownerKey;
    return (): void => { if (model === this.model && owner === this.ownerKey) { this.activate(index); } };
  }
  private pointerClick(): (event: ClickEvent) => void {
    const model = this.model, owner = this.ownerKey;
    return (event: ClickEvent): void => {
      if (this.attached && model === this.model && owner === this.ownerKey && this.touchGeneration === this.generation) {
        this.activate(model.hit(event.x, event.y));
      }
    };
  }
  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.a11y.active) {
        ForEach(this.model.slots, (slot: DrawnGiveawayPeerSlot, index: number) => {
          Row().width(slot.width).height(slot.height).position({ x: slot.x, y: slot.y })
            .accessibilityText(this.semanticLabel(slot, this.semanticRevision))
            .onClick(this.semanticClick(index));
        }, (slot: DrawnGiveawayPeerSlot): string => slot.key);
      }
    }
    .width(this.model.width).height(this.model.height).clip(true)
    .drawModifier(this.painter.bind(this.model))
    .onTouch((event: TouchEvent): void => {
      if (event.type === TouchType.Down) { this.touchGeneration = this.generation; }
      if (event.type === TouchType.Cancel || event.touches.length > 1) { this.touchGeneration = -1; this.model.setPressed(-1); }
      else if (event.type === TouchType.Down) { this.model.setPressed(this.model.hit(event.touches[0]?.x ?? -1, event.touches[0]?.y ?? -1)); }
      else if (event.type === TouchType.Move || event.type === TouchType.Up) { this.model.setPressed(-1); }
    })
    .onClick(this.pointerClick());
  }
}
