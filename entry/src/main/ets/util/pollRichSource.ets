import { TdObject } from '../tdkit/TdTypes';
import { DrawnRichSource, DrawnRichSourceCache } from './drawnRichTextPolicy';

// TD updates may replace equivalent entity arrays. Compare only when identity
// changes; keep a single signature and reuse the original paragraph source.
export class PollRichSource {
  private text: string = '';
  private bold: boolean = false;
  private entities: TdObject[] | null = null;
  private signature: string = '';
  private result: DrawnRichSource | null = null;
  private cache: DrawnRichSourceCache = new DrawnRichSourceCache();
  prepare(text: string, entities: TdObject[], bold: boolean = false): DrawnRichSource | null {
    if (this.entities === entities && this.text === text && this.bold === bold) { return this.result; }
    const signature = JSON.stringify(entities);
    if (this.entities !== null && this.text === text && this.signature === signature && this.bold === bold) {
      this.entities = entities; return this.result;
    }
    let formatted = entities;
    if (bold && text.length > 0) {
      formatted = entities.slice();
      const kind: TdObject = { '@type': 'textEntityTypeBold' };
      const entity: TdObject = {};
      entity['offset'] = 0; entity['length'] = text.length; entity['type'] = kind;
      formatted.push(entity);
    }
    const result = this.cache.prepare(text, formatted);
    this.bold = bold;
    this.text = text; this.entities = entities; this.signature = signature; this.result = result;
    return result;
  }
}
