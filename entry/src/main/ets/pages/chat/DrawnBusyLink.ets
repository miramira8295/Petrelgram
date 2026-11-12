import { OneShotFrameCallback } from '../../util/oneShotFrameCallback';
import { DrawnRichTextLayout } from './DrawnRichTextLayout';
import { DrawnRichHit } from '../../util/drawnRichTextPolicy';
import { chatEnv } from '../../util/chatEnvMirror';

// Transient overlay only while a URL resolves. It never reparses/reflows text.
// Lookup O(1), nodes O(K) for the selected URL's K line rectangles, no JS timer.
@ComponentV2
export struct DrawnBusyLink {
  @Require @Param plan: DrawnRichTextLayout | null;
  @Param url: string = '';
  @Local private alpha: number = 0.35;
  private env = chatEnv;
  private empty: DrawnRichHit[] = [];
  private generation: number = 0;
  aboutToAppear(): void {
    const generation = ++this.generation;
    this.alpha = 0.35;
    this.getUIContext().postFrameCallback(new OneShotFrameCallback((): void => {
      if (generation === this.generation) { this.alpha = 1; }
    }));
  }
  aboutToDisappear(): void { this.generation++; }
  aboutToRecycle(): void { this.generation++; }
  aboutToReuse(): void { this.aboutToAppear(); }
  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      ForEach(this.plan?.hitsByUrl.get(this.url) ?? this.empty, (hit: DrawnRichHit) => {
        Row().width(hit.widthVp).height(hit.heightVp).position({ x: hit.x, y: hit.y })
          .backgroundColor($r('app.color.select_highlight')).borderRadius(3);
      }, (hit: DrawnRichHit): string => hit.key);
    }.width(this.plan?.widthVp ?? 0).height(this.plan?.heightVp ?? 0)
      .opacity(this.alpha)
      .animation({ duration: this.env.reduceAnim || this.env.powerSaving || !this.env.chatEffects ? 0 : 620,
        curve: Curve.EaseInOut, iterations: -1, playMode: PlayMode.Alternate })
      .hitTestBehavior(HitTestMode.None).accessibilityLevel('no');
  }
}
