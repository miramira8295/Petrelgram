import { AlbumGroup, groupIndexOf } from '../../util/collapseAlbums';
import { BubbleFocusChannel } from '../../util/bubbleFocusChannel';
import { KEY_POWER_EFFECT_REPLY } from '../../store/AppSettings';
import { logW } from '../../util/log';

export interface JumpFlashStateHost {
  scroller: () => Scroller;
  groups: () => AlbumGroup[];
  effectDuration: (key: string, ms: number) => number;
}

// Reply, pinned, link and return jumps share one landing cue: a gentle pulse
// on the bubble itself. Each page owns its channel, so stacked chats cannot
// animate each other's rows. Geometry is retained for layout validation only;
// there is no viewport-positioned highlight rectangle anymore.
export class JumpFlashState {
  readonly focus: BubbleFocusChannel = new BubbleFocusChannel();
  top: number = 0;
  height: number = 0;
  alpha: number = 0;
  shown: boolean = false;

  private flashSeq: number = 0;
  private flashTargetIdx: number = -1;
  private flashTargetId: number = 0;
  private flashRowId: number = 0;
  private host: JumpFlashStateHost = {
    scroller: (): Scroller => new Scroller(),
    groups: (): AlbumGroup[] => [],
    effectDuration: (_key: string, ms: number): number => ms
  };

  bind(host: JumpFlashStateHost): void {
    this.host = host;
  }

  flashAtIndex(gidx: number, targetId: number = 0): void {
    this.cancelFlash();
    const seq: number = this.flashSeq;
    // Capture identity even for index-only callers before the settling delay:
    // prepending history can move the target to another index in those 150ms.
    const requestedId: number = targetId > 0
      ? targetId : (this.host.groups()[gidx]?.head.id ?? 0);
    setTimeout((): void => {
      if (seq !== this.flashSeq) {
        return;
      }
      const idx: number = requestedId > 0
        ? groupIndexOf(this.host.groups(), requestedId) : gidx;
      if (idx < 0) {
        return;
      }
      let rect: RectResult;
      try {
        rect = this.host.scroller().getItemRect(idx);
      } catch (e) {
        return;
      }
      if (rect.height <= 0) {
        return;
      }
      this.flashTargetIdx = idx;
      this.flashTargetId = requestedId;
      this.flashRowId = this.host.groups()[idx]?.head.rowId ?? 0;
      this.top = rect.y;
      this.height = rect.height;
      this.shown = true;
      logW(`[Jump80] pulse idx=${idx} target=${requestedId} row=${this.flashRowId}`);
      this.runPulse(seq);
    }, 150);
  }

  // Keep the existing scroll hook: it cancels when the target disappears.
  // The visual follows the bubble's own transform, never viewport coordinates.
  syncFlashRect(): void {
    if (!this.shown) {
      return;
    }
    const idx: number = this.flashTargetId > 0
      ? groupIndexOf(this.host.groups(), this.flashTargetId) : this.flashTargetIdx;
    if (idx < 0) {
      this.cancelFlash();
      return;
    }
    let rect: RectResult;
    try {
      rect = this.host.scroller().getItemRect(idx);
    } catch (e) {
      this.cancelFlash();
      return;
    }
    if (rect.height <= 0) {
      this.cancelFlash();
      return;
    }
    if (Math.abs(rect.y - this.top) > 0.5 || Math.abs(rect.height - this.height) > 0.5) {
      this.top = rect.y;
      this.height = rect.height;
    }
  }

  private setStrength(strength: number): void {
    this.alpha = strength;
    if (this.flashRowId !== 0) {
      this.focus.set(this.flashRowId, strength);
    }
  }

  private runPulse(seq: number, remaining: number = 2): void {
    if (seq !== this.flashSeq) {
      return;
    }
    this.syncFlashRect();
    if (seq !== this.flashSeq) {
      return;
    }
    const rise: number = this.host.effectDuration(KEY_POWER_EFFECT_REPLY, 180);
    const settle: number = this.host.effectDuration(KEY_POWER_EFFECT_REPLY, 420);
    if (rise <= 0 || settle <= 0) {
      // Reduced motion / disabled reply effects must not produce a scale jump.
      this.cancelFlash();
      return;
    }
    animateTo({ duration: rise, curve: Curve.EaseOut }, (): void => {
      this.setStrength(1);
    });
    setTimeout((): void => {
      if (seq !== this.flashSeq) {
        return;
      }
      this.syncFlashRect();
      if (seq !== this.flashSeq) {
        return;
      }
      animateTo({ duration: settle, curve: Curve.EaseInOut }, (): void => {
        this.setStrength(0);
      });
      setTimeout((): void => {
        if (seq === this.flashSeq) {
          if (remaining > 1) {
            this.runPulse(seq, remaining - 1);
          } else {
            this.cancelFlash();
          }
        }
      }, settle);
    }, rise + 80);
  }

  cancelFlash(): void {
    this.flashSeq++;
    this.shown = false;
    this.alpha = 0;
    this.focus.clear();
  }

  dispose(): void {
    // Invalidate both the landing delay and the return phase on page teardown.
    this.cancelFlash();
  }
}
