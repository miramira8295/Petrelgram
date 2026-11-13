import { drawnStageMetrics } from './drawnStageMetrics';
// Fixed-cardinality process diagnostics. Counts are route entries/transitions,
// including predictive reuse, NOT unique messages or visible impressions.
// No clocks, logs, observed state or retained message collections. Optional
// fixed-name route markers share the existing default-off stage Trace switch.
export enum DrawnRouteReason { Drawn, Disabled, Material, Accessibility, Policy, BodyDisabled,
  Translation, Rtl, Chrome, LayoutNull, Exception,
  InvalidGeometry, MissingGrid, SourceEmpty, TextLimit, EntityLimit, TextTab, TextBom, TextDirection,
  TextSegments, TextSegmentKind, TextSegmentOffset, TextRunLimit, InlineCode, Spoiler,
  EmptyRun, RunOffset, TextCoverage, LinkLimit, SourceUnknown,
  ChromeForward, ChromeSender, ChromeRole, ChromeReplySender, ChromeReplyText, SourceParserException }
const ROUTE_NAMES: string[] = ['drawn', 'disabled', 'material', 'a11y', 'policy', 'body-disabled',
  'translation', 'rtl', 'chrome', 'layout-null', 'exception',
  'layout-geometry', 'layout-grid', 'body-empty', 'body-text-limit', 'body-entity-limit',
  'body-tab', 'body-bom', 'body-direction', 'body-segments', 'body-segment-kind', 'body-segment-offset',
  'body-run-limit', 'body-inline-code', 'body-spoiler', 'body-empty-run', 'body-run-offset',
  'body-coverage', 'body-link-limit', 'body-source-unknown',
  'chrome-forward', 'chrome-sender', 'chrome-role', 'chrome-reply-sender', 'chrome-reply-text', 'body-parser-exception'];

const ROUTE_TRACE_NAMES: string[] = ROUTE_NAMES.map((name: string): string => `PG/route/${name}`);

export class DrawnRouteMetrics {
  epoch: number = 0;
  private counts: number[] = new Array<number>(ROUTE_NAMES.length).fill(0);
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

// Consume the source cache's existing rejection; never reparse text/entities to
// explain it. Fixed-length codes become fixed trace names, never message text.
export function drawnSourceRouteReason(reason: string): DrawnRouteReason {
  switch (reason) {
    case 'parser-exception': return DrawnRouteReason.SourceParserException;
    case 'empty': return DrawnRouteReason.SourceEmpty;
    case 'text-limit': return DrawnRouteReason.TextLimit;
    case 'entity-limit': return DrawnRouteReason.EntityLimit;
    case 'direction-or-control:U+9': return DrawnRouteReason.TextTab;
    case 'direction-or-control:U+feff': return DrawnRouteReason.TextBom;
    case 'segment-offset': return DrawnRouteReason.TextSegmentOffset;
    case 'run-limit': return DrawnRouteReason.TextRunLimit;
    case 'inline-code': return DrawnRouteReason.InlineCode;
    case 'spoiler': return DrawnRouteReason.Spoiler;
    case 'empty-run': return DrawnRouteReason.EmptyRun;
    case 'run-offset': return DrawnRouteReason.RunOffset;
    case 'text-coverage': return DrawnRouteReason.TextCoverage;
    case 'link-limit': return DrawnRouteReason.LinkLimit;
    default:
      if (reason.startsWith('direction-or-control:')) { return DrawnRouteReason.TextDirection; }
      if (reason.startsWith('segments:')) { return DrawnRouteReason.TextSegments; }
      if (reason.startsWith('segment-kind:')) { return DrawnRouteReason.TextSegmentKind; }
      return DrawnRouteReason.SourceUnknown;
  }
}
