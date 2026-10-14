export interface QrLink {
  url: string;
  expiresIn: number;
}

export interface QrSnapshot<T> {
  link: string;
  image: T | null;
  failed: boolean;
  temporary: boolean;
}

// Owns both the rendered code and its link: they are published/cleared together.
// Dependencies are injectable so expiry and late native results can be tested.
export class QrSession<T> {
  private active: boolean = false;
  private busy: boolean = false;
  private generation: number = 0;
  private timer: number = -1;
  private value: T | null = null;
  private fetch: () => Promise<QrLink>;
  private render: (url: string) => Promise<T>;
  private release: (value: T) => void;
  private publish: (state: QrSnapshot<T>) => void;
  private now: () => number;
  private schedule: (callback: () => void, ms: number) => number;
  private cancel: (id: number) => void;

  constructor(fetch: () => Promise<QrLink>, render: (url: string) => Promise<T>,
    release: (value: T) => void, publish: (state: QrSnapshot<T>) => void,
    now: () => number = (): number => Date.now(),
    schedule: (callback: () => void, ms: number) => number =
      (callback: () => void, ms: number): number => setTimeout(callback, ms),
    cancel: (id: number) => void = (id: number): void => { clearTimeout(id); }) {
    this.fetch = fetch;
    this.render = render;
    this.release = release;
    this.publish = publish;
    this.now = now;
    this.schedule = schedule;
    this.cancel = cancel;
  }

  start(): void {
    if (this.active) { return; }
    this.active = true;
    this.load();
  }

  retry(): void {
    if (this.active && !this.busy) { this.load(); }
  }

  close(): void {
    this.active = false;
    this.generation++;
    this.busy = false;
    this.clear(false);
  }

  private clear(failed: boolean): void {
    if (this.timer !== -1) { this.cancel(this.timer); this.timer = -1; }
    const previous: T | null = this.value;
    this.value = null;
    this.publish({ link: '', image: null, failed, temporary: false });
    if (previous !== null) { this.release(previous); }
  }

  private current(generation: number): boolean {
    return this.active && generation === this.generation;
  }

  private load(): void {
    const generation: number = ++this.generation;
    this.busy = true;
    this.clear(false);
    // Budget includes the request's round trip, not just the rendering time.
    const started: number = this.now();
    this.fetch().then((link: QrLink): void => {
      if (!this.current(generation)) { return; }
      if (link.url === '' || !Number.isFinite(link.expiresIn) || link.expiresIn < 0) {
        this.fail(generation);
        return;
      }
      const deadline: number = link.expiresIn > 0 ? started + link.expiresIn * 1000 : 0;
      if (deadline > 0) {
        const remaining: number = deadline - this.now();
        if (remaining <= 0) { this.fail(generation); return; }
        this.timer = this.schedule((): void => {
          if (this.current(generation)) { this.load(); }
        }, Math.min(remaining, 2147483647));
      }
      this.render(link.url).then((value: T): void => {
        if (!this.current(generation)) { this.release(value); return; }
        if (deadline > 0 && this.now() >= deadline) {
          this.release(value);
          this.load();
          return;
        }
        this.busy = false;
        this.value = value;
        this.publish({ link: link.url, image: value, failed: false, temporary: deadline > 0 });
      }).catch((): void => { this.fail(generation); });
    }).catch((): void => { this.fail(generation); });
  }

  private fail(generation: number): void {
    if (!this.current(generation)) { return; }
    this.generation++;
    this.busy = false;
    this.clear(true);
  }
}
