import { ReactionAnimationSource } from './ReactionImage';
import { TgsNativeStickerView } from './TgsNativeStickerView';
import { AlphaWebmStickerView } from '../common/AlphaWebmStickerView';

// Shared by the canvas bar and compatibility chips. Only one explicit reaction
// event owns this short-lived overlay; it never loops or creates an ijk player.
@ComponentV2
export struct ReactionAnimationView {
  @Param source: ReactionAnimationSource | null = null;
  @Param replayToken: number = 0;
  @Event onStarted: () => void = (): void => {};
  @Event onFailed: () => void = (): void => {};

  private attached: boolean = false;
  private generation: number = 0;
  // Retire generations only on exit: callbacks prepared before attach remain valid.
  aboutToAppear(): void { this.attached = true; }
  aboutToReuse(): void { this.attached = true; }
  aboutToRecycle(): void { this.generation++; this.attached = false; }
  aboutToDisappear(): void { this.generation++; this.attached = false; }

  private failure(): () => void {
    const source = this.source, token = this.replayToken, generation = this.generation;
    return (): void => {
      if (this.attached && this.generation === generation && this.source === source && this.replayToken === token) { this.onFailed(); }
    };
  }

  private started(): () => void {
    const source = this.source, token = this.replayToken, generation = this.generation;
    return (): void => {
      if (this.attached && this.generation === generation && this.source === source && this.replayToken === token) {
        this.onStarted();
      }
    };
  }

  build() {
    Stack() {
      if (this.source?.format === 'stickerFormatTgs') {
        TgsNativeStickerView({ tgsPath: this.source.path, thumbPath: this.source.poster,
          boxWidth: 20, boxHeight: 20, chatTimeline: true, powerCategory: 'emojiReaction',
          playOnce: true, loop: false, replayToken: this.replayToken, onFailed: this.failure(), onWorking: this.started() });
      } else if (this.source?.format === 'stickerFormatWebm') {
        AlphaWebmStickerView({ webmPath: this.source.path, thumbPath: this.source.poster,
          boxWidth: 20, boxHeight: 20, chatTimeline: true, powerCategory: 'emojiReaction',
          playOnce: true, replayToken: this.replayToken, onFallback: this.failure(), onWorking: this.started() });
      }
    }.width(20).height(20).hitTestBehavior(HitTestMode.None).accessibilityLevel('no');
  }
}
