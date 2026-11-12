import { RowLeaveChannel } from '../../util/rowLeaveChannel';

// Lifecycle only: the existing row owns capture/overlay nodes. No component,
// timer or subscription is allocated for deletion on the normal render path.
export class DrawnRowLeaveCapture {
  private key: string = '';
  private leaving: number = 0;
  private supported: boolean = true;
  private channel: RowLeaveChannel | null = null;
  private generation: number = 0;
  private publish: (key: string) => void;

  constructor(publish: (key: string) => void) { this.publish = publish; }

  bind(key: string, rowId: number, leaving: number, supported: boolean, channel: RowLeaveChannel): void {
    if (key === this.key && leaving === this.leaving && supported === this.supported && channel === this.channel) { return; }
    this.generation++;
    this.key = key; this.leaving = leaving; this.supported = supported; this.channel = channel;
    this.publish('');
    if (leaving > 0 && !supported) { channel.complete(rowId); }
  }

  captured(): () => void {
    const generation = this.generation;
    const key = this.key;
    return (): void => {
      if (generation === this.generation && this.leaving > 0 && this.supported) { this.publish(key); }
    };
  }

  // Finishing an old overlay still releases its original deletion request,
  // even if the reusable row already displays a different message/channel.
  finished(rowId: number, channel: RowLeaveChannel): () => void {
    return (): void => { channel.complete(rowId); };
  }

  reset(): void {
    this.generation++; this.key = ''; this.leaving = 0; this.channel = null;
    this.publish('');
  }
}
