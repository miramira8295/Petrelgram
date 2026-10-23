import { TimerFns } from '../tdkit/TdClient';

export type ProxyCandidateProbe = (id: number) => Promise<boolean>;

// Probe without changing the active route. Native probes cannot be aborted;
// cancellation invalidates their results and stops scheduling further work.
export class ProxyCandidateRace {
  private cancelled: boolean = false;
  private finish: (id: number | undefined) => void = (_id: number | undefined): void => {};
  private timers: Set<number> = new Set();
  private clock: TimerFns;
  constructor(clock: TimerFns) { this.clock = clock; }

  cancel(): void {
    this.cancelled = true;
    this.finish(undefined);
  }

  run(ids: number[], probe: ProxyCandidateProbe): Promise<number | undefined> {
    const queue = ids.slice();
    // Direct access gets a slot in the first wave even with a long proxy list.
    const direct = queue.indexOf(0);
    if (direct > 2) { queue.splice(direct, 1); queue.splice(2, 0, 0); }
    return new Promise<number | undefined>((resolve): void => {
      let done = false;
      let next = 0;
      let active = 0;
      this.finish = (id: number | undefined): void => {
        if (done) { return; }
        done = true;
        this.timers.forEach((timer: number): void => this.clock.clearTimeout(timer));
        this.timers.clear();
        resolve(id);
      };
      const pump = (): void => {
        if (done) { return; }
        if (this.cancelled) { this.finish(undefined); return; }
        while (!done && active < 3 && next < queue.length) {
          const id = queue[next++];
          active++;
          let settled = false;
          let timer = -1;
          const complete = (usable: boolean): void => {
            if (settled || done) { return; }
            settled = true;
            this.clock.clearTimeout(timer); this.timers.delete(timer);
            active--;
            if (usable) { this.finish(id); } else { pump(); }
          };
          timer = this.clock.setTimeout((): void => complete(false), 12000);
          this.timers.add(timer);
          // Also catch synchronous failures at injected/native boundaries.
          Promise.resolve().then((): Promise<boolean> => done ? Promise.resolve(false) : probe(id)).then(
            (usable: boolean): void => complete(usable), (): void => complete(false));
        }
        if (!done && active === 0 && next === queue.length) { this.finish(undefined); }
      };
      pump();
    });
  }
}
