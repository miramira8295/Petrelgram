import { DrawnDocumentWidget } from '../../util/drawnDocumentWidget';
import { claimDocumentVideo } from '../../util/documentVideoFocus';
import { DrawnDocumentArticleImage } from './DrawnDocumentArticleImage';
import { DrawnDocumentEmbed } from './DrawnDocumentEmbed';
import { COLOR_PRIMARY } from '../../util/theme';

// ArticleViewer passes autoplay=false for embedded URL players. Mount only on
// an explicit play tap; controls/seek remain local, never invalidate row layout.
@ComponentV2
export struct DrawnDocumentVideo {
  @Require @Param widget: DrawnDocumentWidget;
  @Param boxWidth: number = 0;
  @Param boxHeight: number = 0;
  @Event onClaim: () => boolean = (): boolean => false;
  @Event onOpen: (url: string) => void = (_url: string): void => {};
  @Local private playing: boolean = false;
  @Local private fallback: boolean = false;
  private controller: VideoController = new VideoController();
  private release: (() => void) | null = null;
  private generation: number = 0;
  private visible: boolean = false;
  private timeout: number = -1;
  private stop(): void {
    this.generation++;
    if (this.timeout !== -1) { clearTimeout(this.timeout); this.timeout = -1; }
    const wasPlaying = this.playing;
    this.playing = false;
    if (wasPlaying) { try { this.controller.stop(); } catch (_) {} }
    this.release?.(); this.release = null;
  }
  private start(): void {
    if (!this.visible || this.playing || !this.onClaim()) { return; }
    this.stop(); this.fallback = false;
    this.release = claimDocumentVideo((): void => this.stop());
    this.controller = new VideoController(); this.playing = true;
    const generation = this.generation;
    this.timeout = setTimeout((): void => {
      this.timeout = -1;
      if (this.generation === generation && this.playing) { this.failed(); }
    }, 15000);
  }
  private failed(): void { this.stop(); this.fallback = true; }
  private prepared(): void {
    if (this.timeout !== -1) { clearTimeout(this.timeout); this.timeout = -1; }
  }
  private current(controller: VideoController, widget: DrawnDocumentWidget, generation: number): boolean {
    return this.visible && this.playing && this.controller === controller && this.widget === widget && this.generation === generation;
  }
  @Monitor('widget') sourceChanged(): void { this.stop(); this.fallback = false; }
  aboutToDisappear(): void { this.visible = false; this.stop(); this.fallback = false; }
  @Builder private player(controller: VideoController, widget: DrawnDocumentWidget, generation: number) {
    Video({ src: widget.url ?? '', controller: controller })
      .width(this.boxWidth).height(this.boxHeight).objectFit(ImageFit.Contain)
      .controls(true).autoPlay(true).loop(false)
      .onPrepared((): void => { if (this.current(controller, widget, generation)) { this.prepared(); } })
      .onError((): void => { if (this.current(controller, widget, generation)) { this.failed(); } })
      .onTouch((event: TouchEvent): void => {
        if (event.type === TouchType.Down && this.current(controller, widget, generation)) { this.onClaim(); }
      });
  }
  build() {
    Stack() {
      if (this.fallback) {
        DrawnDocumentEmbed({ widget: this.widget, boxWidth: this.boxWidth, boxHeight: this.boxHeight,
          onClaim: (): boolean => this.onClaim(), onOpen: (url: string): void => this.onOpen(url) });
      } else if (this.playing) {
        this.player(this.controller, this.widget, this.generation);
      } else {
        DrawnDocumentArticleImage({ widget: this.widget, boxWidth: this.boxWidth, boxHeight: this.boxHeight });
        Button() { SymbolGlyph($r('sys.symbol.play_fill')).fontSize(30).fontColor([COLOR_PRIMARY]); }
          .width(52).height(52).borderRadius(26).accessibilityText($r('app.string.vf_play'))
          .onClick((): void => this.start());
      }
    }.width(this.boxWidth).height(this.boxHeight).clip(true)
      .onVisibleAreaChange([0], (visible: boolean): void => {
        if (this.visible !== visible) { this.visible = visible; if (!visible) { this.stop(); this.fallback = false; } }
      });
  }
}
