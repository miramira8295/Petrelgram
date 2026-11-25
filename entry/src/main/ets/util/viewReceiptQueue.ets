export interface ViewReceiptHost {
  send: (id: number) => Promise<void>;
  confirmed: (id: number) => void;
  failed: (error: Error) => void;
}

// O(1) latest-value queue. A failed request never advances the confirmed
// watermark. One automatic retry, then a later visible-range event may retry.
export class ViewReceiptQueue {
  private wanted: number = 0;
  private confirmed: number = 0;
  private running: boolean = false;
  private closed: boolean = false;
  private retries: number = 0;
  private timer: number = -1;
  private host: ViewReceiptHost;
  constructor(host: ViewReceiptHost) { this.host = host; }

  mark(id: number): void {
    if (this.closed || id <= this.confirmed || !Number.isSafeInteger(id)) { return; }
    this.wanted = Math.max(this.wanted, id);
    if (this.running || this.timer !== -1) { return; }
    this.retries = 0;
    this.send();
  }

  private send(): void {
    if (this.closed || this.running || this.wanted <= this.confirmed) { return; }
    const id: number = this.wanted;
    this.running = true;
    this.host.send(id).then((): void => {
      this.running = false;
      if (this.closed) { return; }
      this.confirmed = Math.max(this.confirmed, id);
      this.retries = 0;
      this.host.confirmed(id);
      this.send();
    }, (error: Error): void => {
      this.running = false;
      if (this.closed) { return; }
      this.host.failed(error);
      if (this.retries++ === 0) {
        this.timer = setTimeout((): void => { this.timer = -1; this.send(); }, 600);
      }
    });
  }

  close(): void {
    this.closed = true;
    if (this.timer !== -1) { clearTimeout(this.timer); this.timer = -1; }
  }
}
