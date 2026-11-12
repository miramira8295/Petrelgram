import { BubbleCornerCache } from './messageBubblePresentation';
import { cornerPx } from './bubbleCornerInset';

const PURE_ALBUM_INNER_CORNERS: BorderRadiuses = {
  topLeft: 13, topRight: 13, bottomLeft: 13, bottomRight: 13
};

// The grid sits 2vp inside the bubble. Its outside contour must use the same
// four corner centers as the shell; individual cells keep their 6vp corners.
export class AlbumCornerRadiiCache {
  private shell: BubbleCornerCache = new BubbleCornerCache();
  private previousOuter: BorderRadiuses | undefined = undefined;
  private previousInner: BorderRadiuses = PURE_ALBUM_INNER_CORNERS;

  prepare(pure: boolean, radius: number, outgoing: boolean, showSenderName: boolean,
    showAvatar: boolean): BorderRadiuses {
    if (pure) { return PURE_ALBUM_INNER_CORNERS; }
    const outer = this.shell.prepare(radius, outgoing, showSenderName, showAvatar);
    if (outer !== this.previousOuter) {
      this.previousOuter = outer;
      this.previousInner = {
        topLeft: Math.max(0, cornerPx(outer.topLeft) - 2),
        topRight: Math.max(0, cornerPx(outer.topRight) - 2),
        bottomLeft: Math.max(0, cornerPx(outer.bottomLeft) - 2),
        bottomRight: Math.max(0, cornerPx(outer.bottomRight) - 2)
      };
    }
    return this.previousInner;
  }
}
