import { TdObject } from '../tdkit/TdTypes';
import { parseFormattedText, RichRun, RichSegment, richSegmentKey } from './richText';

export interface InlineCaptionRun {
  run: RichRun;
  key: string;
}

const EMPTY_RUNS: InlineCaptionRun[] = [];

// Only a single inline segment can skip the block renderer. Preserve the exact
// parser output (including offsets, links, styles and custom emoji), and keep
// code/quote/multi-segment captions on the existing complete path.
export class InlineCaptionCache {
  private text: string = '';
  private entities: TdObject[] | undefined = undefined;
  private segment: RichSegment | null = null;
  private items: InlineCaptionRun[] = EMPTY_RUNS;

  prepare(text: string, entities: TdObject[]): RichSegment | null {
    if (this.entities === entities && this.text === text) {
      return this.segment;
    }
    const segments = parseFormattedText(text, entities);
    this.segment = segments.length === 1 && segments[0].kind === 'text' ? segments[0] : null;
    if (this.segment !== null) {
      // Preserve the removed outer ForEach's invalidation boundary once per
      // source, not once per run on every render. Keep the parser's actual run
      // objects so formatting, offsets and click targets remain unchanged.
      const prefix: string = richSegmentKey(0, this.segment);
      this.items = this.segment.runs.map((run: RichRun, index: number): InlineCaptionRun => {
        return { run, key: `${prefix}|run_${index}_${run.offset}_${run.text}` };
      });
    } else {
      this.items = EMPTY_RUNS;
    }
    this.text = text;
    this.entities = entities;
    return this.segment;
  }

  runs(): InlineCaptionRun[] { return this.items; }
}
