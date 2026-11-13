import { drawnStageMetrics } from './drawnStageMetrics';
// Fixed-cardinality process diagnostics. Counts are route entries/transitions,
// including predictive reuse, NOT unique messages or visible impressions.
// No clocks, logs, observed state or retained message collections. Optional
// fixed-name route markers share the existing default-off stage Trace switch.
export enum DrawnRouteReason { Drawn, Disabled, Material, Accessibility, Policy, BodyDisabled,
  Translation, Rtl, Chrome, LayoutNull, Exception }
const ROUTE_NAMES: string[] = ['drawn', 'disabled', 'material', 'a11y', 'policy', 'body-disabled',
  'translation', 'rtl', 'chrome', 'layout-null', 'exception'];

const ROUTE_TRACE_NAMES: string[] = ROUTE_NAMES.map((name: string): string => `PG/route/${name}`);

export class DrawnRouteMetrics {
  epoch: number = 0;
  private counts: number[] = new Array<number>(11).fill(0);
  record(reason: DrawnRouteReason): void {
    if (this.counts[reason] < 2147483647) { this.counts[reason]++; }
    drawnStageMetrics.markRoute(ROUTE_TRACE_NAMES[reason]);
  }
  reset(): void { this.counts.fill(0); this.epoch++; }
  summary(): string {
    let result = '[DrawnRoute] scope=process_since_log_clear unit=route_entry_or_change includes_predict=true';
    for (let i = 0; i < ROUTE_NAMES.length; i++) { result += ` ${ROUTE_NAMES[i]}=${this.counts[i]}`; }
    return result + '\n';
  }
}
export const drawnRouteMetrics: DrawnRouteMetrics = new DrawnRouteMetrics();

export class DrawnRouteTracker {
  private chatId: number = 0;
  private rowId: number = 0;
  private reason: number = -1;
  private epoch: number = -1;
  record(chatId: number, rowId: number, reason: DrawnRouteReason): void {
    if (this.chatId === chatId && this.rowId === rowId && this.reason === reason &&
      this.epoch === drawnRouteMetrics.epoch) { return; }
    this.chatId = chatId; this.rowId = rowId; this.reason = reason; this.epoch = drawnRouteMetrics.epoch;
    drawnRouteMetrics.record(reason);
  }
  reset(): void { this.reason = -1; }
}
