import { FrameCallback } from '@kit.ArkUI';

// 从 ChatPage.ets 搬来（原名 ChatPageFrameCallback）。
// One-shot UI frame task shared by initial-message staging and the deferred
// composer mount. The caller uses postDelayedFrameCallback so callbacks queued
// by adjacent state notifications cannot drain into the same VSync.
export class OneShotFrameCallback extends FrameCallback {
  private task: () => void;

  constructor(task: () => void) {
    super();
    this.task = task;
  }

  onFrame(_frameTimeInNano: number): void {
    this.task();
  }
}
