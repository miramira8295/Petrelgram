import { DrawnRichSource, DrawnRichBlock, DrawnRichSourceCache } from '../../util/drawnRichTextPolicy';
import { DrawnDocumentWidget } from '../../util/drawnDocumentWidget';
import { str } from '../../util/strings';

// The transfer/player clocks never enter this key. Only transcription content,
// phase, language or caption can change the document's variable-height area.
export class DrawnVoiceMessageSource {
  private state: string = '';
  private text: string = '';
  private environment: string = '';
  private body: DrawnRichSource | null = null;
  private cached: DrawnRichSource | null = null;
  private speech: DrawnRichSourceCache = new DrawnRichSourceCache();
  private labels: DrawnRichSourceCache = new DrawnRichSourceCache();
  private widget: DrawnDocumentWidget = { key: 'message-voice', kind: 'message-voice',
    name: '', mimeType: '', size: 0, latitude: 0, longitude: 0, zoom: 0, width: 240, height: 60 };

  prepare(body: DrawnRichSource | null, state: string, text: string, environment: string): DrawnRichSource | null {
    if (this.cached !== null && this.body === body && this.state === state && this.text === text &&
      this.environment === environment) { return this.cached; }
    const empty: DrawnRichSource = { content: '', runs: [], links: [], targets: new Set<string>() };
    const blocks: DrawnRichBlock[] = [{ source: empty, widget: this.widget,
      kind: 'text', offset: -200000, expandable: false, language: '' }];
    if (state === 'done' || state === 'pending' || state === 'error') {
      const content = text || (state === 'pending' ? str('voice_transcribing') : state === 'error' ? str('voice_transcribe_failed') : '');
      if (content !== '') {
        const speech = this.speech.prepare(content, []);
        if (speech === null) { return null; }
        blocks.push({ source: speech, kind: 'text', fontSize: 13.5, lineLimit: state === 'pending' ? 4 : undefined,
          offset: -200001, expandable: false, language: '' });
      }
    }
    if (state !== 'pending' && state !== 'done') {
      const label = this.labels.prepare(str('voice_transcribe'), []);
      if (label === null) { return null; }
      blocks.push({ source: label, kind: 'translation-label', action: 'voice-transcribe',
        offset: -200002, expandable: false, language: '' });
    }
    if (body?.blocks !== undefined) { for (const block of body.blocks) { blocks.push(block); } }
    else if (body !== null) { blocks.push({ source: body, kind: 'text', offset: 0, expandable: false, language: '' }); }
    this.cached = { content: body?.content ?? '', runs: [], links: body?.links ?? [],
      targets: body?.targets ?? empty.targets, blocks, hasMath: body?.hasMath };
    this.body = body; this.state = state; this.text = text; this.environment = environment;
    return this.cached;
  }
}
