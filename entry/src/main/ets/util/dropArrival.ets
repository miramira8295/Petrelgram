import { SharedPayload } from './sharedContent';

export interface DropArrivalHost {
  active: () => boolean;
  check: (payload: SharedPayload) => Promise<void>;
  draft: () => string;
  setDraft: (text: string) => void;
  // 媒体拖拽落到这里就代表"现在发出去"（2026-11-23 去掉了松手后的确认弹框）。
  // 纯文本仍然只接进草稿，由用户自己按发送。
  deliver: (payload: SharedPayload) => void;
}

export class DropArrivalSession {
  private generation: number = 0;
  private busy: boolean = false;
  cancel(): void { this.generation++; this.busy = false; }
  async receive(load: () => Promise<SharedPayload | null>, host: DropArrivalHost): Promise<boolean> {
    if (this.busy || !host.active()) { return false; }
    const generation = ++this.generation;
    this.busy = true;
    const current = (): boolean => generation === this.generation && host.active();
    try {
      const payload = await load();
      if (!current() || payload === null) { return false; }
      if (payload.media.length === 0 && payload.caption === '') { throw new Error('empty drop'); }
      await host.check(payload);
      if (!current()) { return false; }
      if (payload.media.length > 0) { host.deliver(payload); }
      else {
        const existing = host.draft();
        host.setDraft(existing === '' ? payload.caption : `${existing}\n${payload.caption}`);
      }
      return true;
    } finally {
      if (generation === this.generation) { this.busy = false; }
    }
  }
}
