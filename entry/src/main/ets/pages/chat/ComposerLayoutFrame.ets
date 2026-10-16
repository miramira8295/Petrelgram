import { FrameCallback } from '@kit.ArkUI';

// onIdle 位于渲染任务之后；零延时定时器不保证这个时序。每次请求只采一次。
export class ComposerLayoutFrame extends FrameCallback {
  private readLayout: (() => void) | undefined;

  constructor(readLayout: () => void) {
    super();
    this.readLayout = readLayout;
  }

  onIdle(_timeLeftInNano: number): void {
    const readLayout: (() => void) | undefined = this.readLayout;
    this.readLayout = undefined;
    if (readLayout !== undefined) {
      readLayout();
    }
  }
}
