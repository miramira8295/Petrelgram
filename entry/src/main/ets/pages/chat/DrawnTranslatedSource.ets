import { MessageEntry } from '../../store/MessageEntry';
import { TdObject } from '../../tdkit/TdTypes';
import { TranslationStatus } from '../../util/translationChannel';
import { translationReplacesOriginal } from '../../util/translationMode';
import { languageDisplayName } from '../../services/TranslationService';
import { str } from '../../util/strings';
import { DrawnRichBlock, DrawnRichSource, DrawnRichSourceCache } from '../../util/drawnRichTextPolicy';

const DRAWN_TRANSLATION_LABEL_ENTITIES: TdObject[] = [];

// Original and translated entities each retain their own UTF-16 address space.
// Only block references are composed. Status/footer changes reuse both sources;
// no reparsing, string-key copies or per-character entity lookup is needed.
export class DrawnTranslatedSource {
  private original: DrawnRichSourceCache = new DrawnRichSourceCache();
  private translated: DrawnRichSourceCache | null = null;
  private labels: DrawnRichSourceCache | null = null;
  private previousOriginal: DrawnRichSource | null = null;
  private previousTranslation: DrawnRichSource | null = null;
  private previousLabel: string = '';
  private previousReplace: boolean = false;
  private previousHidden: boolean = false;
  private previousAction: string = '';
  private cached: DrawnRichSource | null = null;
  reason: string = '';

  prepare(content: string, entities: TdObject[], msg: MessageEntry, status: TranslationStatus | null,
    replaceOriginal: boolean, structured?: DrawnRichSource): DrawnRichSource | null {
    const original = structured ?? (content !== '' ? this.original.prepare(content, entities) : null);
    this.reason = this.original.reason;
    if (content !== '' && original === null) { return null; }
    if (msg.translatedText === '' && status === null) { return original; }
    let translated: DrawnRichSource | null = null;
    const replace = structured === undefined && translationReplacesOriginal(replaceOriginal, msg.translatedText, msg.translationHidden);
    let label: string;
    let action: 'translation-toggle' | 'translation-retry' | undefined;
    if (msg.translatedText !== '') {
      if (!msg.translationHidden) {
        if (this.translated === null) { this.translated = new DrawnRichSourceCache(); }
        translated = this.translated.prepare(msg.translatedText, msg.translatedEntities);
        if (translated === null) { this.reason = this.translated.reason; return null; }
      }
      label = str('mb_translated_into', languageDisplayName(msg.translatedLang)) + ' · ' +
        str(msg.translationHidden ? 'mb_show_translation' : 'mb_hide_translation');
      action = 'translation-toggle';
    } else {
      label = status?.phase === 'loading' ? str('mb_translating') :
        str('mb_translate_failed', status?.error ?? '') + ' · ' + str('settings_retry');
      action = status?.phase === 'failed' ? 'translation-retry' : undefined;
    }
    if (this.previousOriginal === original && this.previousTranslation === translated &&
      this.previousLabel === label && this.previousReplace === replace && this.previousHidden === msg.translationHidden &&
      this.previousAction === (action ?? '')) { return this.cached; }
    const blocks: DrawnRichBlock[] = [];
    if (!replace && original !== null) { this.append(blocks, original, false); }
    if (translated !== null) { this.append(blocks, translated, true); }
    if (this.labels === null) { this.labels = new DrawnRichSourceCache(); }
    const footer = this.labels.prepare(label, DRAWN_TRANSLATION_LABEL_ENTITIES);
    if (footer === null) { this.reason = this.labels.reason; return null; }
    blocks.push({ source: footer, kind: 'translation-label', offset: -1, expandable: false, language: '', action });
    const targets = new Set<string>();
    for (const block of blocks) { for (const target of block.source.targets) { targets.add(target); } }
    // Links/hits are assembled from the individual block plans; this list only
    // gates the optional busy-link overlay, so reuse existing link references.
    const links = blocks.flatMap((block: DrawnRichBlock) => block.source.links);
    this.cached = { hasEmbed: original?.hasEmbed === true, anchorPaths: original?.anchorPaths, footnotes: original?.footnotes, mediaItems: original?.mediaItems, audioItems: original?.audioItems, hasMath: original?.hasMath === true || translated?.hasMath === true, content, runs: [], links, targets, blocks };
    this.previousOriginal = original; this.previousTranslation = translated; this.previousLabel = label;
    this.previousReplace = replace; this.previousHidden = msg.translationHidden; this.previousAction = action ?? '';
    return this.cached;
  }
  private append(blocks: DrawnRichBlock[], source: DrawnRichSource, translated: boolean): void {
    if (source.blocks !== undefined) {
      for (const block of source.blocks) {
        blocks.push(translated ? { source: block.source, kind: block.kind, offset: -block.offset - 2,
          expandable: block.expandable, language: block.language } : block);
      }
    }
    else { blocks.push({ source, kind: 'text', offset: 0, expandable: false, language: '' }); }
  }
}
