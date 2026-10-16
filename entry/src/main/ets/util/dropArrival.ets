import { SharedPayload } from './sharedContent';

export interface DropArrivalHost {
  active: () => boolean;
  check: (payload: SharedPayload) => Promise<void>;
  draft: () => string;
  setDraft: (text: string) => void;
  preview: (payload: SharedPayload) => void;
}

// This interface intentionally has no send method: dropping cannot send a message.
export class DropArrivalSession {
  private generation: number = 0;
  private busy: boolean = false;
  cancel(): void { this.generation++; this.busy = false; }
  async receive(load: () => Promise<SharedPayload>, host: DropArrivalHost): Promise<boolean> {
    if (this.busy || !host.active()) { return false; }
    const generation = ++this.generation;
    this.busy = true;
    const current = (): boolean => generation === this.generation && host.active();
    try {
      const payload = await load();
      if (!current()) { return false; }
      if (payload.media.length === 0 && payload.caption === '') { throw new Error('empty drop'); }
      await host.check(payload);
      if (!current()) { return false; }
      if (payload.media.length > 0) { host.preview(payload); }
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
