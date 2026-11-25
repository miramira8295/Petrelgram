import { drawnFirstStrongRtl } from '../../util/drawnTextDirection';
import { MessageEntry } from '../../store/MessageEntry';
import { DrawnRichBlock, DrawnRichSource, DrawnRichLink } from '../../util/drawnRichTextPolicy';
import { linkPreviewPresentation } from '../../util/linkPreview';
import { str } from '../../util/strings';

function previewSource(content: string, bold: boolean): DrawnRichSource {
  return { content, rtl: drawnFirstStrongRtl(content), links: [], targets: new Set<string>(), runs: [{ offset: 0, text: content,
    bold, italic: false, underline: false, strike: false, code: false, spoiler: false,
    customEmojiId: '', link: false, url: '' }] };
}

// One retained document per physical row. Download progress/path is deliberately
// absent from the key: the local image layer consumes those updates independently.
export class DrawnWebPreviewSource {
  private previous: MessageEntry | null = null;
  private base: DrawnRichSource | null = null;
  private environment: string = '';
  private cached: DrawnRichSource | null = null;
  prepare(base: DrawnRichSource | null, msg: MessageEntry, environment: string): DrawnRichSource | null {
    if (msg.linkUrl === '' && msg.linkTitle === '' && msg.linkSiteName === '' &&
      msg.linkDescription === '' && msg.linkPhotoFileId === 0) { return base; }
    const old = this.previous;
    if (old !== null && this.base === base && this.environment === environment &&
      old.linkUrl === msg.linkUrl && old.linkTitle === msg.linkTitle && old.linkSiteName === msg.linkSiteName &&
      old.linkDescription === msg.linkDescription && old.linkPreviewType === msg.linkPreviewType &&
      (old.linkPhotoFileId !== 0) === (msg.linkPhotoFileId !== 0) && old.linkPhotoWidth === msg.linkPhotoWidth &&
      old.linkPhotoHeight === msg.linkPhotoHeight && old.linkPhotoFailed === msg.linkPhotoFailed) { return this.cached; }
    const blocks: DrawnRichBlock[] = [];
    if (base?.blocks !== undefined) { for (const block of base.blocks) { blocks.push(block); } }
    else if (base !== null) { blocks.push({ source: base, kind: 'text', offset: 0, expandable: false, language: '' }); }
    const presentation = linkPreviewPresentation(msg.linkUrl, msg.linkPreviewType, msg.linkSiteName);
    const action = presentation.actionable || msg.linkPhotoFailed ? 'web-preview' : undefined;
    const previewUrl = !msg.linkPhotoFailed && presentation.actionable ? msg.linkUrl : '';
    blocks.push({ source: previewSource(presentation.siteLabel, true), kind: 'preview-site', offset: -1,
      expandable: false, language: '', action, preview: true, previewUrl, fontSize: 12, lineLimit: 1 });
    if (msg.linkTitle !== '') {
      blocks.push({ source: previewSource(msg.linkTitle, true), kind: 'preview-text', offset: -1,
        expandable: false, language: '', action, preview: true, previewUrl, fontSize: 14, lineLimit: 2 });
    }
    if (msg.linkDescription !== '' || msg.linkTitle === '') {
      blocks.push({ source: previewSource(msg.linkDescription || str(presentation.isTelegram ? 'mb_telegram_link' : 'mb_web_link'), false),
        kind: 'preview-text', offset: -1, expandable: false, language: '', action, preview: true, previewUrl, fontSize: 13, lineLimit: 4 });
    }
    if (msg.linkPhotoFileId !== 0) {
      blocks.push({ source: previewSource(' ', false), kind: 'preview-image', offset: -1, expandable: false,
        language: '', action, preview: true, previewUrl, imageRatio: msg.linkPhotoWidth > 0 && msg.linkPhotoHeight > 0 ?
          Math.max(.82, Math.min(1.92, msg.linkPhotoWidth / msg.linkPhotoHeight)) : 1.5 });
    }
    blocks.push({ source: previewSource(msg.linkPhotoFailed ? str('mb_reload_preview') : presentation.actionLabel, true),
      kind: 'preview-action', offset: -1, expandable: false, language: '', action, preview: true, previewUrl, fontSize: 12 });
    const links: DrawnRichLink[] = base?.links ?? [];
    this.cached = { hasEmbed: base?.hasEmbed, anchorPaths: base?.anchorPaths, footnotes: base?.footnotes, mediaItems: base?.mediaItems, audioItems: base?.audioItems, hasMath: base?.hasMath, content: base?.content ?? '', runs: [], links, targets: base?.targets ?? new Set<string>(), blocks };
    this.previous = msg; this.base = base; this.environment = environment;
    return this.cached;
  }
}
