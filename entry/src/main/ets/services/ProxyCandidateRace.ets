import { TimerFns } from '../tdkit/TdClient';
import { ProxyProbeCancellation } from '../util/ProxyProbeCancellation';

export type ProxyCandidateProbe = (id: number, cancellation?: ProxyProbeCancellation) => Promise<boolean>;

// Probe without changing the active route. Cancelling revokes the probe's
// temporary relay route as well as ignoring late native request replies.
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
      const probes: Set<ProxyProbeCancellation> = new Set();
      this.finish = (id: number | undefined): void => {
        if (done) { return; }
        done = true;
        this.timers.forEach((timer: number): void => this.clock.clearTimeout(timer));
        this.timers.clear();
        probes.forEach((probe: ProxyProbeCancellation): void => probe.cancel());
        probes.clear();
        resolve(id);
      };
      const pump = (): void => {
        if (done) { return; }
        if (this.cancelled) { this.finish(undefined); return; }
        while (!done && active < 3 && next < queue.length) {
          const id = queue[next++];
          const cancellation = new ProxyProbeCancellation();
          probes.add(cancellation);
          active++;
          let settled = false;
          let timer = -1;
          const complete = (usable: boolean): void => {
            if (settled || done) { return; }
            settled = true;
            probes.delete(cancellation);
            cancellation.cancel();
            this.clock.clearTimeout(timer); this.timers.delete(timer);
            active--;
            if (usable) { this.finish(id); } else { pump(); }
          };
          timer = this.clock.setTimeout((): void => complete(false), 12000);
          this.timers.add(timer);
          // Also catch synchronous failures at injected/native boundaries.
          Promise.resolve().then((): Promise<boolean> => done ? Promise.resolve(false) : probe(id, cancellation)).then(
            (usable: boolean): void => complete(usable), (): void => complete(false));
        }
        if (!done && active === 0 && next === queue.length) { this.finish(undefined); }
      };
      pump();
    });
  }
}
