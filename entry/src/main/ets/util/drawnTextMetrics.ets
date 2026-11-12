// Process-local counters only: no message IDs/content, timers, observed state,
// per-row log writes or retained samples. Formatting happens on log export.
export interface DrawnTextMetricsSnapshot {
  requests: number;
  planHits: number;
  paragraphHits: number;
  paragraphMisses: number;
  paragraphBuilds: number;
  layoutCalls: number;
  outlineBuilds: number;
  colorUpdates: number;
  failures: number;
  timedBuilds: number;
  sampledBuildMs: number;
  sampledMaxBuildMs: number;
}

export class DrawnTextMetrics {
  private counts: DrawnTextMetricsSnapshot = this.empty();

  private empty(): DrawnTextMetricsSnapshot {
    return { requests: 0, planHits: 0, paragraphHits: 0, paragraphMisses: 0,
      paragraphBuilds: 0, layoutCalls: 0, outlineBuilds: 0, colorUpdates: 0,
      failures: 0, timedBuilds: 0, sampledBuildMs: 0, sampledMaxBuildMs: 0 };
  }

  request(): void { this.counts.requests++; }
  planHit(): void { this.counts.planHits++; }
  paragraphHit(): void { this.counts.paragraphHits++; }
  paragraphBuilt(): void { this.counts.paragraphBuilds++; }
  layoutCall(): void { this.counts.layoutCalls++; }
  outlineBuilt(): void { this.counts.outlineBuilds++; }
  colorUpdated(): void { this.counts.colorUpdates++; }
  failure(): void { this.counts.failures++; }

  // Time the first eight misses, then one in sixteen. Hits never read a clock.
  paragraphMiss(): boolean {
    this.counts.paragraphMisses++;
    return this.counts.paragraphMisses <= 8 || this.counts.paragraphMisses % 16 === 0;
  }

  sampleBuild(ms: number): void {
    if (!Number.isFinite(ms) || ms < 0) { return; }
    this.counts.timedBuilds++;
    this.counts.sampledBuildMs += ms;
    this.counts.sampledMaxBuildMs = Math.max(this.counts.sampledMaxBuildMs, ms);
  }

  reset(): void { this.counts = this.empty(); }

  snapshot(): DrawnTextMetricsSnapshot {
    const c = this.counts;
    return { requests: c.requests, planHits: c.planHits, paragraphHits: c.paragraphHits,
      paragraphMisses: c.paragraphMisses, paragraphBuilds: c.paragraphBuilds,
      layoutCalls: c.layoutCalls, outlineBuilds: c.outlineBuilds, colorUpdates: c.colorUpdates,
      failures: c.failures, timedBuilds: c.timedBuilds,
      sampledBuildMs: c.sampledBuildMs, sampledMaxBuildMs: c.sampledMaxBuildMs };
  }

  summary(): string {
    const c = this.counts;
    if (c.requests === 0) { return ''; }
    const reused: number = c.planHits + c.paragraphHits;
    const average: number = c.timedBuilds > 0 ? c.sampledBuildMs / c.timedBuilds : 0;
    return `[DrawnText] scope=process_since_log_clear requests=${c.requests} planHits=${c.planHits}` +
      ` paragraphHits=${c.paragraphHits} misses=${c.paragraphMisses}` +
      ` reusePct=${(100 * reused / c.requests).toFixed(1)} builds=${c.paragraphBuilds}` +
      ` layoutCalls=${c.layoutCalls} outlines=${c.outlineBuilds} recolors=${c.colorUpdates}` +
      ` failures=${c.failures}\n` +
      `[DrawnTextTiming] scope=body_and_footer_build_and_layout sampling=first8_then_1in16` +
      ` samples=${c.timedBuilds} avgMs=${average.toFixed(3)}` +
      ` maxSampleMs=${c.sampledMaxBuildMs.toFixed(3)} totalSampleMs=${c.sampledBuildMs.toFixed(3)}\n`;
  }
}

export const drawnTextMetrics: DrawnTextMetrics = new DrawnTextMetrics();
