import { MessageEntry } from '../../store/MessageEntry';
import { MessageBubbleActions } from './ReusableMessageBubble';
import { AvLoopVideo } from '../common/AvLoopVideo';
import { progressForOr, subscribeProgress } from '../../util/mediaProgressChannel';
import { str } from '../../util/strings';

@ComponentV2
export struct DrawnVideoNoteMessage {
  @Require @Param msg: MessageEntry;
  @Require @Param actions: MessageBubbleActions;
  @Param boxWidth: number = 180;
  @Param sendState: string = '';
  @Event onClaim: () => boolean = (): boolean => false;
  @Local private playing: boolean = false;
  @Local private progress: number = 0;
  private off: (() => void) | null = null;
  private active: boolean = false;
  private generation: number = 0;
  private playerGeneration: number = 0;

  @Computed private get sourceIdentity(): string { return `${this.msg.rowId}:${this.msg.videoFileId}`; }
  @Computed private get side(): number { return Math.max(1, Math.min(180, this.boxWidth)); }
  @Computed private get duration(): string {
    const total = Math.max(0, Math.floor(this.msg.videoDuration));
    return `${Math.floor(total / 60)}:${`${total % 60}`.padStart(2, '0')}`;
  }
  private detach(): void {
    this.generation++;
    this.off?.();
    this.off = null;
    this.stopPlayback();
  }
  private stopPlayback(): void { this.playerGeneration++; this.playing = false; }
  private bind(): void {
    this.detach();
    this.progress = progressForOr(this.msg.videoFileId, this.msg.videoProgress);
    if (!this.active) { return; }
    const owner = this.generation;
    this.off = subscribeProgress(this.msg.videoFileId, (progress: number): void => {
      if (owner === this.generation && this.progress !== progress) { this.progress = progress; }
    });
  }
  @Monitor('sourceIdentity') private sourceChanged(): void { this.bind(); }
  aboutToAppear(): void { this.active = true; this.bind(); }
  aboutToReuse(): void { this.active = true; this.bind(); }
  aboutToRecycle(): void { this.active = false; this.detach(); }
  aboutToDisappear(): void { this.aboutToRecycle(); }
  private finished(owner: number): () => void {
    return (): void => { if (owner === this.playerGeneration) { this.stopPlayback(); } };
  }
  private toggle(): void {
    if (!this.active || this.sendState === 'sending' || !this.onClaim()) { return; }
    if (this.msg.videoPath === '') { this.actions.onVideoNoteDownload(this.msg.id); return; }
    this.playerGeneration++;
    this.playing = !this.playing;
  }
  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.msg.photoPath !== '') {
        Image(this.msg.photoPath.startsWith('/') ? `file://${this.msg.photoPath}` : this.msg.photoPath)
          .width(this.side).height(this.side).objectFit(ImageFit.Cover).draggable(false);
      }
      if (this.playing && this.msg.videoPath !== '') {
        AvLoopVideo({ videoPath: this.msg.videoPath, boxWidth: this.side, boxHeight: this.side,
          loop: false, muted: false, onFinished: this.finished(this.playerGeneration), onFailed: this.finished(this.playerGeneration) });
      } else {
        SymbolGlyph($r('sys.symbol.play_fill')).fontSize(22).fontColor([Color.White]);
      }
      if (this.msg.videoPath === '' && this.progress > 0 && this.progress < 100) {
        Progress({ value: this.progress, total: 100, type: ProgressType.Ring })
          .width(46).height(46).color(Color.White);
      }
      Text(this.duration).fontSize(11).fontColor(Color.White)
        .padding({ left: 7, right: 7, top: 2, bottom: 2 }).backgroundColor('#66000000').borderRadius(9)
        .offset({ y: this.side / 2 - 18 });
    }
    .width(this.side).height(this.side).backgroundColor($r('app.color.surface_alt'))
    .borderRadius(this.side / 2).clip(true)
    .accessibilityText(this.playing ? str('mb_video_note_playing') : str('mb_video_note', this.duration))
    .onVisibleAreaChange([0], (visible: boolean): void => { if (!visible) { this.stopPlayback(); } })
    .onClick((): void => this.toggle());
  }
}
