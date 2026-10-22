import { RowLeaveChannel } from '../../util/rowLeaveChannel';
import { ShatterDeleteOverlay } from './ShatterDeleteOverlay';

// 仅包住需要消散的内容，保留布局占位直到业务层移除数据。
@ComponentV2
export struct DissolveDeleteEffect {
  @Require @Param instanceKey: string;
  @Require @Param rowId: number;
  @Require @Param leaving: number;
  @Require @Param channel: RowLeaveChannel;
  @Param captureSupported: boolean = true;
  @BuilderParam content: () => void;
  @Local private capturedKey: string = '';

  private nodeKey(): string { return `dissolve-delete-${this.instanceKey}-${this.rowId}`; }

  @Monitor('leaving', 'rowId', 'instanceKey')
  private resetCapture(): void {
    if (this.leaving === 0 || this.capturedKey !== this.nodeKey()) { this.capturedKey = ''; }
    if (this.leaving > 0 && !this.captureSupported) { this.channel.complete(this.rowId); }
  }

  aboutToAppear(): void { this.resetCapture(); }

  private capturedFor(key: string): () => void {
    return (): void => {
      if (this.leaving > 0 && this.nodeKey() === key) { this.capturedKey = key; }
    };
  }

  private finishedFor(rowId: number, channel: RowLeaveChannel): () => void {
    return (): void => { channel.complete(rowId); };
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Row() { this.content(); }
        .id(this.nodeKey())
        .opacity(this.leaving > 0 && (!this.captureSupported || this.capturedKey === this.nodeKey()) ? 0 : 1);
      if (this.leaving > 0 && this.captureSupported) {
        ShatterDeleteOverlay({
          nodeId: this.nodeKey(),
          particleBudget: this.channel.particleBudget(),
          onCaptured: this.capturedFor(this.nodeKey()),
          onFinish: this.finishedFor(this.rowId, this.channel)
        }).position({ x: 0, y: 0 });
      }
    }
    .hitTestBehavior(this.leaving > 0 ? HitTestMode.None : HitTestMode.Default);
  }
}
