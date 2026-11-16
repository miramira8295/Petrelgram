import { UIContext } from '@kit.ArkUI';
import { logW } from '../../util/log';

let nextDrawnMediaPosition: number = 0;

// One id per physical video island, retained across message reuse. Query only
// after the caller's generation guard and at visible-ratio cadence, not every
// scroll frame. Never retain a native node or the previous message's position.
export class DrawnMediaPosition {
  readonly nodeId: string = `drawn-media-position-${++nextDrawnMediaPosition}`;
  private failureLogged: boolean = false;

  center(ui: UIContext): number | undefined {
    try {
      const node = ui.getFrameNodeById(this.nodeId);
      if (node === null) { return undefined; }
      const height = node.getMeasuredSize().height;
      if (!(height > 0)) { return undefined; }
      const top = node.getPositionToWindowWithTransform().y;
      // FrameNode position is vp; measured size is px.
      const center = top + ui.px2vp(height) / 2;
      return Number.isFinite(center) ? center : undefined;
    } catch (error) {
      if (!this.failureLogged) {
        this.failureLogged = true;
        logW(`DrawnMediaPosition: geometry unavailable: ${(error as Error)?.message ?? String(error)}`);
      }
      return undefined;
    }
  }
}
