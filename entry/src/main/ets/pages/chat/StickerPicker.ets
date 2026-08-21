import { getTdClient } from '../../tdkit/Globals';
import { guardKey } from '../../util/keyGuard';
import { TgsStickerView } from './TgsStickerView';
import { SmartLoopVideo } from '../common/SmartLoopVideo';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import {
  KEY_POWER_ACTIVE, KEY_POWER_EMOJI, KEY_POWER_STICKERS, KEY_POWER_STICKER_AUTOPLAY, KEY_REDUCE_ANIM
} from '../../store/AppSettings';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import {
  addFavoriteSticker, getFavoriteStickers, getRecentStickers, rememberRecentSticker,
  removeFavoriteSticker
} from '../../store/StickerApi';
import { promptAction, LengthMetrics } from '@kit.ArkUI';
import { str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { probeEvent, probeHit } from '../../util/panelProbe';
import {
  overlayMaterial, overlayGlassFill, overlayBackdropBlur, MATERIAL_EPOCH
} from '../../util/overlayMaterial';
import { logE, logI } from '../../util/log';

export interface StickerItem {
  fileId: number;   // the sticker's own file (what gets sent)
  width: number;
  height: number;
  thumbPath: string; // raster thumbnail local path ('' while downloading)
  thumbFileId: number; // raster thumbnail file id (0 if none)
  emoji: string;
  format: string;    // 'webp' | 'tgs' | 'webm' | 'unicode'
  srcPath: string;   // local TGS source path ('' until downloaded) — drives animation
  customEmojiId: string; // custom emoji id ('' for regular stickers)
}

// One row of the continuous grid: a full-width pack header or a sticker cell.
interface FlatEntry {
  kind: string;   // 'header' | 'sticker'
  title: string;
  setIdx: number; // owning pack index — drives the tab highlight while scrolling
  // Position within the owning pack. It exists only to make the grid key
  // unique: the same sticker legitimately appears in several packs — recents
  // and favourites repeat what the packs already hold — so a key built from
  // fileId and paths produced two cells with the SAME key. That is the
  // "Use repeat key" warning in the device log, and it makes the grid reuse
  // the wrong cell.
  pos: number;
  sticker: StickerItem | null;
}

// Minimal IDataSource so the grid virtualizes (only visible cells mount their
// Lottie canvases — a full set would otherwise run 100+ animations at once).
class StickerDataSource implements IDataSource {
  private items: FlatEntry[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): FlatEntry {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((l: DataChangeListener) => l !== listener);
  }

  update(next: FlatEntry[]): void {
    // 探针：这里是无条件整表 RELOAD，贴纸包一个个加载回来会连发多次。
    probeEvent('sticker.reload', `items=${this.items.length}->${next.length}`);
    this.items = next;
    for (const l of this.listeners) {
      l.onDatasetChange([{ type: DataOperationType.RELOAD } as DataReloadOperation]);
    }
  }
}

interface StickerSetTab {
  id: string;    // int64 set id — kept as the string TDLib's JSON delivers
  title: string;
  iconPath: string; // pack cover thumbnail for the tab strip ('' = text fallback)
  iconText: string; // emoji glyph tab icon (classic unicode packs)
  loaded: boolean;
  failed: boolean;
  stickers: StickerItem[];
}

// A built-in unicode emoji section shown as a synthetic pack before the
// network packs (the chat panel's classic emoji).
export interface ClassicPack {
  title: string;
  icon: string;
  emoji: string[];
}

const SET_LIMIT: number = 20;

// Sticker picker for the input panel: installed sticker sets as horizontal
// tabs, the selected set as a grid. Tapping a sticker sends it.
// stickerType 'custom_emoji' (+ includeTrending) turns it into the emoji
// library used by the avatar builder — installed emoji packs plus the
// server's trending packs, like the official client.
@Component
export struct StickerPicker {
  // 材质档位（厚度/光感）改变时重绘。overlayMaterial 是 util，订阅不了
  // AppStorage，只能由调用方订阅，同 LANGUAGE_EPOCH 的做法。
  @StorageProp(MATERIAL_EPOCH) private materialEpoch: number = 0;
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  // 正在被按住的格子（setIdx_pos）。空串表示没有。
  @State private pressedCell: string = '';
  onPick: (s: StickerItem, x: number, y: number) => void = (): void => {};
  // 能不能显示搜索框。挂在自定义键盘（聊天页的表情抽屉）里时必须关掉：
  // 官方《自定义键盘》写明"自定义键盘无法获取焦点，但是会拦截手势事件"，
  // 里面的 TextInput 点得到却永远输不进字。头像编辑器那种普通页面不受限。
  allowSearch: boolean = true;
  stickerType: string = 'regular'; // 'regular' | 'custom_emoji'
  includeTrending: boolean = false;
  classicPacks: ClassicPack[] = []; // built-in unicode sections, shown first
  // false = static thumbnails only (no Lottie/ijkplayer cells) — used by the
  // avatar picker dialog where a grid full of players stutters.
  animate: boolean = true;
  @StorageProp(KEY_POWER_ACTIVE) @Watch('onPlaybackSettingsChanged') powerSaving: boolean = false;
  @StorageProp(KEY_REDUCE_ANIM) @Watch('onPlaybackSettingsChanged') reduceAnimations: boolean = false;
  @StorageProp(KEY_POWER_STICKERS) @Watch('onPlaybackSettingsChanged') stickersEnabled: boolean = true;
  @StorageProp(KEY_POWER_STICKER_AUTOPLAY) @Watch('onPlaybackSettingsChanged') stickerAutoplay: boolean = true;
  @StorageProp(KEY_POWER_EMOJI) @Watch('onPlaybackSettingsChanged') emojiEnabled: boolean = true;
  @State sets: StickerSetTab[] = [];
  @State curSet: number = 0;
  @State loading: boolean = true;
  @State loadError: string = '';
  @State searchLoading: boolean = false;
  @State searchError: string = '';
  @State contentError: string = '';
  private initialized: boolean = false;
  private loadSeq: number = 0;
  private sourceLoading: Set<number> = new Set<number>();
  private gridData: StickerDataSource = new StickerDataSource();

  aboutToAppear(): void {
    if (this.initialized) {
      return;
    }
    this.initialized = true;
    if (this.classicPacks.length > 0) {
      this.sets = this.classicPacks.map((c: ClassicPack, i: number): StickerSetTab => ({
        id: `classic_${i}`,
        title: c.title,
        iconPath: '',
        iconText: c.icon,
        loaded: true,
        failed: false,
        stickers: c.emoji.map((ch: string): StickerItem => ({
          fileId: 0, width: 0, height: 0, thumbPath: '', thumbFileId: 0, emoji: ch, format: 'unicode', srcPath: '', customEmojiId: ''
        }))
      }));
      this.loading = false;
      this.refreshGrid();
    }
    this.loadQuickSections();
    this.loadSets();
  }

  // 收藏 / 最近 sections, prepended before the installed packs like the
  // official clients. Custom-emoji mode has no such server lists.
  private loadQuickSections(): void {
    if (this.stickerType === 'custom_emoji') { return; }
    const seq = this.loadSeq;
    Promise.all([getFavoriteStickers(), getRecentStickers()])
      .then((lists: TdObject[][]): void => {
        if (seq !== this.loadSeq) { return; }
        const sections: StickerSetTab[] = [];
        const specs: string[][] = [
          ['fav', str('sp_favourites'), '⭐'], ['recent', str('sp_recent'), '🕘']
        ];
        lists.forEach((raw: TdObject[], index: number): void => {
          if (raw.length === 0) { return; }
          const spec = specs[index];
          const items = raw.map((st: TdObject): StickerItem => this.stickerItemOf(st))
            .filter((it: StickerItem): boolean => it.fileId !== 0);
          if (items.length === 0) { return; }
          sections.push({
            id: spec[0], title: spec[1], iconPath: '', iconText: spec[2],
            loaded: true, failed: false, stickers: items
          });
          for (const st of raw) {
            const file = st['sticker'] as TdObject | undefined;
            const fileId = file !== undefined ? ((file['id'] as number | undefined) ?? 0) : 0;
            if (fileId !== 0) {
              this.downloadThumb(spec[0], fileId, st['thumbnail'] as TdObject | undefined);
              if (this.playbackEnabled()) { this.downloadSource(spec[0], fileId); }
            }
          }
        });
        if (sections.length === 0) { return; }
        this.sets = [...sections, ...this.sets];
        this.refreshGrid();
      }).catch((): void => {});
  }

  private toggleFavorite(s: StickerItem): void {
    if (s.fileId === 0 || this.stickerType === 'custom_emoji') { return; }
    const favSection = this.sets.find((t: StickerSetTab): boolean => t.id === 'fav');
    const isFav = favSection !== undefined &&
      favSection.stickers.some((it: StickerItem): boolean => it.fileId === s.fileId);
    const task: Promise<void> = isFav
      ? removeFavoriteSticker(s.fileId) : addFavoriteSticker(s.fileId);
    task.then((): void => {
      promptAction.showToast({
        message: isFav ? $r('app.string.sp_unfavourited') : $r('app.string.sp_favourited'), duration: 1300
      });
    }).catch((): void => {
      promptAction.showToast({ message: $r('app.string.sp_favourite_failed'), duration: 1300 });
    });
  }

  // Shared TDLib sticker → StickerItem mapping (packs, search, quick sections).
  private stickerItemOf(st: TdObject): StickerItem {
    const file = st['sticker'] as TdObject | undefined;
    const fileId = file !== undefined ? ((file['id'] as number | undefined) ?? 0) : 0;
    const fmt = st['format'] as TdObject | undefined;
    const fmtName = fmt !== undefined ? ((fmt['@type'] as string | undefined) ?? '') : '';
    const format = fmtName === 'stickerFormatWebp' ? 'webp'
      : (fmtName === 'stickerFormatTgs' ? 'tgs' : 'webm');
    const fullType = st['full_type'] as TdObject | undefined;
    const ceId = fullType !== undefined
      && ((fullType['@type'] as string | undefined) ?? '') === 'stickerFullTypeCustomEmoji'
      ? `${fullType['custom_emoji_id']}` : '';
    const rasterThumb = this.rasterThumbFile(st['thumbnail'] as TdObject | undefined);
    return {
      fileId,
      width: (st['width'] as number | undefined) ?? 512,
      height: (st['height'] as number | undefined) ?? 512,
      thumbPath: '',
      thumbFileId: rasterThumb !== undefined ? ((rasterThumb['id'] as number | undefined) ?? 0) : 0,
      emoji: (st['emoji'] as string | undefined) ?? '',
      format, srcPath: '', customEmojiId: ceId
    };
  }

  private typeObj(): TdObject {
    return {
      '@type': this.stickerType === 'custom_emoji' ? 'stickerTypeCustomEmoji' : 'stickerTypeRegular'
    } as TdObject;
  }

  private playbackEnabled(): boolean {
    if (!this.animate || this.powerSaving || this.reduceAnimations) {
      return false;
    }
    return this.stickerType === 'custom_emoji'
      ? this.emojiEnabled
      : this.stickersEnabled && this.stickerAutoplay;
  }

  private onPlaybackSettingsChanged(): void {
    if (!this.playbackEnabled()) {
      return;
    }
    for (const set of this.sets) {
      if (!set.loaded || set.id.startsWith('classic_')) {
        continue;
      }
      for (const sticker of set.stickers) {
        if ((sticker.format === 'tgs' || sticker.format === 'webm') &&
          sticker.srcPath === '' && !this.sourceLoading.has(sticker.fileId)) {
          this.downloadSource(set.id, sticker.fileId);
        }
      }
    }
  }

  private loadSets(): void {
    const seq: number = ++this.loadSeq;
    this.loadError = '';
    if (this.sets.length === 0) {
      this.loading = true;
    }
    const req: TdRequest = { '@type': 'getInstalledStickerSets' };
    req['sticker_type'] = this.typeObj();
    getTdClient().send(req).then((res: TdObject) => {
      if (seq !== this.loadSeq) {
        return;
      }
      const raw = (res['sets'] as TdObject[] | undefined) ?? [];
      const tabs: StickerSetTab[] = [];
      for (const s of raw.slice(0, SET_LIMIT)) {
        const id = `${s['id']}`; // int64 arrives as a string in TDLib JSON — keep verbatim
        tabs.push({
          id,
          title: (s['title'] as string | undefined) ?? '',
          iconPath: '',
          iconText: '',
          loaded: false,
          failed: false,
          stickers: []
        });
      }
      this.sets = [...this.sets, ...tabs];
      for (const s of raw.slice(0, SET_LIMIT)) {
        this.resolveTabIcon(`${s['id']}`, s);
      }
      this.loading = false;
      if (this.classicPacks.length === 0 && tabs.length > 0) {
        this.selectSet(0);
      } else {
        this.refreshGrid();
      }
      if (this.includeTrending) {
        this.loadTrending();
      }
    }).catch((e: TdError) => {
      if (seq !== this.loadSeq) {
        return;
      }
      logE(`StickerPicker.getInstalledStickerSets failed: ${e.message}`);
      this.loading = false;
      if (this.sets.length === 0) {
        this.loadError = this.stickerType === 'custom_emoji' ? str('sp_emoji_load_failed') : str('sp_sticker_load_failed');
      }
      if (this.includeTrending) {
        this.loadTrending();
      }
    });
  }

  // Server-trending packs appended after the installed ones (deduped).
  private loadTrending(): void {
    const req: TdRequest = { '@type': 'getTrendingStickerSets' };
    req['sticker_type'] = this.typeObj();
    req['offset'] = 0;
    req['limit'] = 30;
    getTdClient().send(req).then((res: TdObject) => {
      const raw = (res['sets'] as TdObject[] | undefined) ?? [];
      const known = new Set<string>(this.sets.map((t: StickerSetTab) => t.id));
      const extra: StickerSetTab[] = [];
      for (const s of raw) {
        const id = `${s['id']}`;
        if (known.has(id)) {
          continue;
        }
        known.add(id);
        extra.push({
          id,
          title: (s['title'] as string | undefined) ?? '',
          iconPath: '',
          iconText: '',
          loaded: false,
          failed: false,
          stickers: []
        });
        this.resolveTabIcon(id, s);
      }
      if (extra.length > 0) {
        const hadNone = this.sets.length === 0;
        this.sets = [...this.sets, ...extra];
        const extraIds = new Set<string>(extra.map((t: StickerSetTab) => t.id));
        for (const s of raw) {
          const id = `${s['id']}`;
          if (extraIds.has(id)) {
            this.resolveTabIcon(id, s);
          }
        }
        this.loading = false;
        if (hadNone) {
          this.selectSet(0);
        }
      }
    }).catch((e: TdError) => {
      logE(`StickerPicker.getTrendingStickerSets failed: ${e.message}`);
    });
  }

  // Only raster thumbnails render in an Image — animated (tgs/webm) covers
  // would show as a blank tab.
  private rasterThumbFile(thumb: TdObject | undefined): TdObject | undefined {
    if (thumb === undefined) {
      return undefined;
    }
    const fmt = thumb['format'] as TdObject | undefined;
    const name = fmt !== undefined ? ((fmt['@type'] as string | undefined) ?? '') : '';
    const isRaster = name === 'thumbnailFormatWebp' || name === 'thumbnailFormatJpeg'
      || name === 'thumbnailFormatPng';
    return isRaster ? (thumb['file'] as TdObject | undefined) : undefined;
  }

  // Pack cover → tab icon (thumbnail of the set's thumbnail or first cover).
  private resolveTabIcon(setId: string, info: TdObject): void {
    let file = this.rasterThumbFile(info['thumbnail'] as TdObject | undefined);
    if (file === undefined) {
      const covers = (info['covers'] as TdObject[] | undefined) ?? [];
      if (covers.length > 0) {
        file = this.rasterThumbFile(covers[0]['thumbnail'] as TdObject | undefined);
      }
    }
    const fileId = file !== undefined ? ((file['id'] as number | undefined) ?? 0) : 0;
    if (fileId === 0) {
      return;
    }
    const req: TdRequest = { '@type': 'downloadFile' };
    req['file_id'] = fileId;
    req['priority'] = 1;
    req['synchronous'] = true;
    getTdClient().send(req).then((f: TdObject) => {
      const local = f['local'] as TdObject | undefined;
      const path = local !== undefined ? ((local['path'] as string | undefined) ?? '') : '';
      if (path === '') {
        return;
      }
      this.sets = this.sets.map((t: StickerSetTab): StickerSetTab => t.id === setId
        ? {
          id: t.id, title: t.title, iconPath: path, iconText: t.iconText,
          loaded: t.loaded, failed: t.failed, stickers: t.stickers
        } : t);
    }).catch((e: TdError) => {
      logE(`StickerPicker.resolveTabIcon failed: ${e.message}`);
    });
  }

  // --- search (searchStickers over public packs) ---
  // 搜索条不再常占一行：折进包条右端那颗按钮里，点开才展开成输入框。
  @State searchOpen: boolean = false;
  @State searchQuery: string = '';
  @State searchItems: StickerItem[] = [];
  private searchTimer: number = -1;
  private searchSeq: number = 0;

  // 关搜索时把结果和请求一起丢掉，回到当前包——否则再点开会闪一下旧结果。
  private toggleSearch(): void {
    if (this.searchOpen) {
      this.searchSeq++;
      this.searchOpen = false;
      this.searchQuery = '';
      this.searchItems = [];
      this.searchLoading = false;
      this.searchError = '';
      this.refreshGrid();
      return;
    }
    this.searchOpen = true;
  }

  private onSearchChanged(v: string): void {
    this.searchQuery = v;
    this.searchError = '';
    if (this.searchTimer !== -1) {
      clearTimeout(this.searchTimer);
    }
    if (v.trim() === '') {
      this.searchSeq++;
      this.searchLoading = false;
      this.searchItems = [];
      this.refreshGrid();
      return;
    }
    this.searchLoading = true;
    this.searchTimer = setTimeout(() => {
      this.searchTimer = -1;
      this.runStickerSearch();
    }, 300);
  }

  private runStickerSearch(): void {
    const q = this.searchQuery.trim();
    const seq = ++this.searchSeq;
    if (q === '') {
      this.searchLoading = false;
      this.searchError = '';
      this.searchItems = [];
      this.refreshGrid();
      return;
    }
    const req: TdRequest = { '@type': 'searchStickers' };
    req['sticker_type'] = this.typeObj();
    // Both fields set: emoji input matches by emoji, words match by keyword
    // (whichever this TDLib build supports wins; extras are ignored).
    req['emojis'] = q;
    req['query'] = q;
    req['limit'] = 60;
    getTdClient().send(req).then((res: TdObject) => {
      if (seq !== this.searchSeq) {
        return;
      }
      const raw = (res['stickers'] as TdObject[] | undefined) ?? [];
      const items: StickerItem[] = [];
      for (const st of raw) {
        const file = st['sticker'] as TdObject | undefined;
        const fileId = file !== undefined ? ((file['id'] as number | undefined) ?? 0) : 0;
        if (fileId === 0) {
          continue;
        }
        const fmt = st['format'] as TdObject | undefined;
        const fmtName = fmt !== undefined ? ((fmt['@type'] as string | undefined) ?? '') : '';
        const format = fmtName === 'stickerFormatWebp' ? 'webp'
          : (fmtName === 'stickerFormatTgs' ? 'tgs' : 'webm');
        const fullType = st['full_type'] as TdObject | undefined;
        const ceId = fullType !== undefined
          && ((fullType['@type'] as string | undefined) ?? '') === 'stickerFullTypeCustomEmoji'
          ? `${fullType['custom_emoji_id']}` : '';
        const rasterThumb = this.rasterThumbFile(st['thumbnail'] as TdObject | undefined);
        items.push({
          fileId,
          width: (st['width'] as number | undefined) ?? 512,
          height: (st['height'] as number | undefined) ?? 512,
          thumbPath: '',
          thumbFileId: rasterThumb !== undefined ? ((rasterThumb['id'] as number | undefined) ?? 0) : 0,
          emoji: (st['emoji'] as string | undefined) ?? '',
          format, srcPath: '', customEmojiId: ceId
        });
      }
      this.searchItems = items;
      this.searchLoading = false;
      this.searchError = '';
      this.refreshGrid();
      // Publish results before downloading thumbnails so a fast completion
      // cannot patch the previous empty array.
      for (const st of raw) {
        const file = st['sticker'] as TdObject | undefined;
        const fileId = file !== undefined ? ((file['id'] as number | undefined) ?? 0) : 0;
        if (fileId !== 0) {
          this.downloadSearchThumb(fileId, st['thumbnail'] as TdObject | undefined, seq);
        }
      }
    }).catch((e: TdError) => {
      if (seq !== this.searchSeq) {
        return;
      }
      logE(`StickerPicker.searchStickers failed: ${e.message}`);
      this.searchLoading = false;
      this.searchError = str('search_failed');
      this.searchItems = [];
      this.refreshGrid();
    });
  }

  private downloadSearchThumb(stickerFileId: number, thumb: TdObject | undefined, seq: number): void {
    const file = this.rasterThumbFile(thumb);
    const fileId = file !== undefined ? ((file['id'] as number | undefined) ?? 0) : 0;
    if (fileId === 0) {
      return;
    }
    const req: TdRequest = { '@type': 'downloadFile' };
    req['file_id'] = fileId;
    req['priority'] = 1;
    req['synchronous'] = true;
    getTdClient().send(req).then((f: TdObject) => {
      if (seq !== this.searchSeq) {
        return;
      }
      const local = f['local'] as TdObject | undefined;
      const path = local !== undefined ? ((local['path'] as string | undefined) ?? '') : '';
      if (path === '') {
        return;
      }
      this.searchItems = this.searchItems.map((it: StickerItem): StickerItem => it.fileId === stickerFileId
        ? {
          fileId: it.fileId, width: it.width, height: it.height,
          thumbPath: path, thumbFileId: it.thumbFileId, emoji: it.emoji,
          format: it.format, srcPath: it.srcPath, customEmojiId: it.customEmojiId
        } : it);
      if (this.searchQuery.trim() !== '') {
        this.refreshGrid();
      }
    }).catch((e: TdError) => {
      logE(`StickerPicker.downloadSearchThumb failed: ${e.message}`);
    });
  }

  // The grid shows sets[anchor..] as ONE continuous scroll; packs load in
  // order as the user scrolls down, and the tab highlight follows the pack
  // at the top of the viewport. Tapping a tab re-anchors the grid there.
  private anchor: number = 0;
  private flatEntries: FlatEntry[] = [];
  private gridScroller: Scroller = new Scroller();
  @State loadingSet: boolean = false;

  private selectSet(idx: number): void {
    this.contentError = '';
    this.curSet = idx;
    this.anchor = idx;
    this.refreshGrid();
    this.gridScroller.scrollToIndex(0);
    if (idx >= 0 && idx < this.sets.length && !this.sets[idx].loaded) {
      this.loadSetContents(idx);
    }
  }

  // Load the next unloaded pack after the anchor (keeps the flat list contiguous).
  private loadNextSet(): void {
    for (let i = this.anchor; i < this.sets.length; i++) {
      if (!this.sets[i].loaded && !this.sets[i].failed) {
        this.loadSetContents(i);
        return;
      }
    }
  }

  private flatten(): FlatEntry[] {
    const out: FlatEntry[] = [];
    for (let i = this.anchor; i < this.sets.length; i++) {
      const t = this.sets[i];
      if (!t.loaded) {
        break; // contiguity: stop at the first not-yet-loaded pack
      }
      out.push({ kind: 'header', title: t.title, setIdx: i, pos: -1, sticker: null });
      let pos = 0;
      for (const st of t.stickers) {
        out.push({ kind: 'sticker', title: '', setIdx: i, pos: pos, sticker: st });
        pos++;
      }
    }
    return out;
  }

  // Scroll position → owning pack: highlight its tab and keep it visible.
  private onGridScrolled(first: number, last: number): void {
    if (this.searchQuery.trim() !== '') {
      return;
    }
    if (first >= 0 && first < this.flatEntries.length) {
      const owner = this.flatEntries[first].setIdx;
      if (owner !== this.curSet) {
        this.curSet = owner;
        this.tabScroller.scrollTo({
          xOffset: Math.max(0, owner * 44 - 120), yOffset: 0,
          animation: { duration: 200, curve: Curve.EaseOut }
        });
      }
    }
    if (last >= this.flatEntries.length - 12 && !this.loadingSet) {
      this.loadNextSet();
    }
  }

  private tabScroller: Scroller = new Scroller();

  private loadSetContents(idx: number): void {
    if (idx < 0 || idx >= this.sets.length || this.sets[idx].loaded || this.loadingSet) {
      return;
    }
    this.loadingSet = true;
    this.contentError = '';
    const setId = this.sets[idx].id;
    this.sets = this.sets.map((t: StickerSetTab): StickerSetTab =>
      t.id === setId
        ? {
          id: t.id, title: t.title, iconPath: t.iconPath, iconText: t.iconText,
          loaded: t.loaded, failed: false, stickers: t.stickers
        }
        : t);
    const req: TdRequest = { '@type': 'getStickerSet' };
    req['set_id'] = setId;
    getTdClient().send(req).then((res: TdObject) => {
      const raw = (res['stickers'] as TdObject[] | undefined) ?? [];
      const items: StickerItem[] = [];
      for (const st of raw) {
        const file = st['sticker'] as TdObject | undefined;
        const fileId = file !== undefined ? ((file['id'] as number | undefined) ?? 0) : 0;
        if (fileId === 0) {
          continue;
        }
        const fmt = st['format'] as TdObject | undefined;
        const fmtName = fmt !== undefined ? ((fmt['@type'] as string | undefined) ?? '') : '';
        const format = fmtName === 'stickerFormatWebp' ? 'webp'
          : (fmtName === 'stickerFormatTgs' ? 'tgs' : 'webm');
        const fullType = st['full_type'] as TdObject | undefined;
        const ceId = fullType !== undefined
          && ((fullType['@type'] as string | undefined) ?? '') === 'stickerFullTypeCustomEmoji'
          ? `${fullType['custom_emoji_id']}` : '';
        const rasterThumb = this.rasterThumbFile(st['thumbnail'] as TdObject | undefined);
        items.push({
          fileId,
          width: (st['width'] as number | undefined) ?? 512,
          height: (st['height'] as number | undefined) ?? 512,
          thumbPath: '',
          thumbFileId: rasterThumb !== undefined ? ((rasterThumb['id'] as number | undefined) ?? 0) : 0,
          emoji: (st['emoji'] as string | undefined) ?? '',
          format,
          srcPath: '',
          customEmojiId: ceId
        });
        this.downloadThumb(setId, fileId, st['thumbnail'] as TdObject | undefined);
        if (this.playbackEnabled() && (format === 'tgs' || format === 'webm')) {
          this.downloadSource(setId, fileId);
        }
      }
      let tgs = 0;
      let webm = 0;
      let webp = 0;
      for (const it of items) {
        if (it.format === 'tgs') { tgs++; } else if (it.format === 'webm') { webm++; } else { webp++; }
      }
      logI(`StickerPicker: set ${setId} loaded ${items.length} stickers (tgs=${tgs} webm=${webm} webp=${webp})`);
      this.sets = this.sets.map((t: StickerSetTab): StickerSetTab =>
        t.id === setId
          ? {
            id: t.id, title: t.title, iconPath: t.iconPath, iconText: t.iconText,
            loaded: true, failed: false, stickers: items
          }
          : t);
      this.loadingSet = false;
      this.contentError = '';
      this.refreshGrid();
    }).catch((e: TdError) => {
      this.loadingSet = false;
      this.contentError = str('sp_sticker_load_failed');
      this.sets = this.sets.map((t: StickerSetTab): StickerSetTab =>
        t.id === setId
          ? {
            id: t.id, title: t.title, iconPath: t.iconPath, iconText: t.iconText,
            loaded: false, failed: true, stickers: t.stickers
          }
          : t);
      logE(`StickerPicker.getStickerSet failed: ${e.message}`);
    });
  }

  // Download the raster thumbnail (synchronous download — thumbs are tiny),
  // then patch it into the right set/sticker immutably.
  private downloadThumb(setId: string, stickerFileId: number, thumb: TdObject | undefined) {
    const format = thumb !== undefined ? (thumb['format'] as TdObject | undefined) : undefined;
    const formatName = format !== undefined ? ((format['@type'] as string | undefined) ?? '') : '';
    const isRaster = formatName === 'thumbnailFormatWebp' || formatName === 'thumbnailFormatJpeg'
      || formatName === 'thumbnailFormatPng';
    const thumbFile = thumb !== undefined && isRaster ? (thumb['file'] as TdObject | undefined) : undefined;
    const thumbFileId = thumbFile !== undefined ? ((thumbFile['id'] as number | undefined) ?? 0) : 0;
    if (thumbFileId === 0) {
      return;
    }
    const req: TdRequest = { '@type': 'downloadFile' };
    req['file_id'] = thumbFileId;
    req['priority'] = 1;
    req['synchronous'] = true;
    getTdClient().send(req).then((f: TdObject) => {
      const local = f['local'] as TdObject | undefined;
      const path = local !== undefined ? ((local['path'] as string | undefined) ?? '') : '';
      if (path === '') {
        return;
      }
      this.patchSticker(setId, stickerFileId, (s: StickerItem): StickerItem => ({
        fileId: s.fileId, width: s.width, height: s.height, thumbPath: path,
        thumbFileId: s.thumbFileId, emoji: s.emoji, format: s.format,
        srcPath: s.srcPath, customEmojiId: s.customEmojiId
      }));
    }).catch((e: TdError) => {
      logE(`StickerPicker.downloadThumb failed: ${e.message}`);
    });
  }

  private patchSticker(setId: string, stickerFileId: number,
    patch: (s: StickerItem) => StickerItem): void {
    this.sets = this.sets.map((t: StickerSetTab): StickerSetTab => {
      if (t.id !== setId) {
        return t;
      }
      const stickers = t.stickers.map((s: StickerItem): StickerItem =>
        s.fileId === stickerFileId ? patch(s) : s);
      return {
        id: t.id, title: t.title, iconPath: t.iconPath, iconText: t.iconText,
        loaded: t.loaded, failed: t.failed, stickers
      };
    });
    this.refreshGrid();
  }

  private refreshTimer: number = -1;

  // Debounced: a freshly opened set fires one thumb + one source patch per
  // sticker in quick succession; reloading the grid for each one rebuilds
  // visible cells (and their native players) dozens of times.
  private refreshGrid(): void {
    if (this.refreshTimer !== -1) {
      return;
    }
    this.refreshTimer = setTimeout(() => {
      this.refreshTimer = -1;
      if (this.searchQuery.trim() !== '') {
        this.flatEntries = this.searchItems.map((st: StickerItem, idx: number): FlatEntry =>
          ({ kind: 'sticker', title: '', setIdx: -1, pos: idx, sticker: st }));
      } else {
        this.flatEntries = this.flatten();
      }
      this.gridData.update(this.flatEntries);
    }, 80);
  }

  // Sticker source download (small) → animate the grid cell (Lottie / ijk).
  private downloadSource(setId: string, stickerFileId: number): void {
    if (this.sourceLoading.has(stickerFileId)) {
      return;
    }
    this.sourceLoading.add(stickerFileId);
    const req: TdRequest = { '@type': 'downloadFile' };
    req['file_id'] = stickerFileId;
    req['priority'] = 1;
    req['synchronous'] = true;
    getTdClient().send(req).then((f: TdObject) => {
      this.sourceLoading.delete(stickerFileId);
      const local = f['local'] as TdObject | undefined;
      const path = local !== undefined ? ((local['path'] as string | undefined) ?? '') : '';
      if (path === '') {
        return;
      }
      this.patchSticker(setId, stickerFileId, (s: StickerItem): StickerItem => ({
        fileId: s.fileId, width: s.width, height: s.height, thumbPath: s.thumbPath,
        thumbFileId: s.thumbFileId, emoji: s.emoji, format: s.format,
        srcPath: path, customEmojiId: s.customEmojiId
      }));
    }).catch((e: TdError) => {
      this.sourceLoading.delete(stickerFileId);
      logE(`StickerPicker.downloadSource failed: ${e.message}`);
    });
  }

  // Emoji grids use smaller cells (8 columns) — less canvas area per Lottie.
  // 探针：格子构建计数。挂在 cellPx 上而不是写一条裸语句——ArkUI 的
  // builder 体里不接受那种写法，而每个格子构建时本来就要问一次尺寸。
  private cellPxProbed(): number {
    probeHit('sticker.cell');
    return this.cellPx();
  }

  private cellPx(): number {
    return this.stickerType === 'custom_emoji' ? 38 : 62;
  }

  private playbackCategory(): string {
    return this.stickerType === 'custom_emoji' ? 'emojiPicker' : 'sticker';
  }

  private retryInitialLoad(): void {
    this.loadError = '';
    this.loading = true;
    this.sets = this.sets.filter((t: StickerSetTab): boolean => t.id.startsWith('classic_'));
    this.refreshGrid();
    this.loadSets();
  }

  private retryCurrentSet(): void {
    if (this.curSet >= 0 && this.curSet < this.sets.length) {
      this.loadSetContents(this.curSet);
    }
  }

  // 按压态自己管，不用 stateStyles。格子在 Grid 里，而 Grid 自带的滑动手势
  // 优先级更高，stateStyles 的按压判定要等它先放弃——表现出来就是"按下去
  // 半天才有反应"。onTouch 是基础事件，按下即到。
  private pressedCellStyleScale(cellKey: string): number {
    return this.pressedCell === cellKey ? 0.9 : 1;
  }

  @Builder
  stickerCell(s: StickerItem, cellKey: string) {
    Stack() {
      if (this.animate && s.format === 'tgs' && s.srcPath !== '') {
        Column() {
          TgsStickerView({
            tgsPath: s.srcPath, thumbPath: s.thumbPath,
            boxWidth: this.cellPxProbed(), boxHeight: this.cellPx(),
            powerCategory: this.playbackCategory()
          });
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.Center);
      } else if (this.animate && s.format === 'webm' && s.srcPath !== '') {
        Column() {
          SmartLoopVideo({
            videoPath: s.srcPath, thumbPath: s.thumbPath,
            boxWidth: this.cellPxProbed(), boxHeight: this.cellPx(),
            powerCategory: this.playbackCategory()
          });
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.Center);
      } else if (s.thumbPath !== '') {
        Image(`file://${s.thumbPath}`).draggable(false)
          .width('100%').height('100%').objectFit(ImageFit.Contain);
      } else {
        Text(s.emoji)
          .fontSize(this.stickerType === 'custom_emoji' ? 26 : 30)
          .textAlign(TextAlign.Center)
          .width('100%').height('100%');
      }
    }
    .width('100%').aspectRatio(1)
    // 这里**不挂材质**。每格挂一层 THIN 材质之后，每个 emoji 都变成一块独立
    // 的玻璃砖，边缘连成一片网格线——API 26 真机上一眼就能看到（截图为证）。
    // 材质属于面板那一层，格子只负责按压反馈。
    .opacity(this.pressedCell === cellKey ? 0.72 : 1)
    .scale({ x: this.pressedCellStyleScale(cellKey), y: this.pressedCellStyleScale(cellKey) })
    .onTouch((event: TouchEvent): void => {
      if (event.type === TouchType.Down) {
        this.pressedCell = cellKey;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressedCell = '';
      }
    })
    .animation({
      duration: this.reduceAnimations || this.powerSaving ? 0 : 110,
      curve: Curve.EaseOut
    })
    .onClick((e: ClickEvent) => {
      if (s.fileId !== 0 && this.stickerType !== 'custom_emoji') {
        rememberRecentSticker(s.fileId);
      }
      // 坐标用于"贴纸飞出"动画的起点，窗口坐标系与浮层一致。
      this.onPick(s, e.windowX, e.windowY);
    })
    // Long-press to (un)favorite — the 收藏 section refreshes on next open.
    .gesture(LongPressGesture().onAction(() => { this.toggleFavorite(s); }));
  }

  @Builder
  stateMessage(symbol: Resource, title: string, detail: string, retry: boolean) {
    Column({ space: 8 }) {
      SymbolGlyph(symbol).fontSize(28).fontColor([COLOR_TEXT_SECONDARY]);
      Text(title).fontSize(15).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
      Text(detail).fontSize(13).fontColor(COLOR_TEXT_SECONDARY).textAlign(TextAlign.Center);
      if (retry) {
        Text($r('app.string.settings_reload'))
          .fontSize(14).fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Medium)
          .padding({ left: 16, right: 16, top: 7, bottom: 7 })
          .backgroundColor($r('app.color.selected_pill')).borderRadius(16)
          .onClick(() => { this.retryInitialLoad(); });
      }
    }
    .layoutWeight(1).width('100%')
    .justifyContent(FlexAlign.Center);
  }

  build() {
    Column() {
      if (this.loading) {
        Column() {
          LoadingProgress().width(28).height(28).color(COLOR_PRIMARY);
          Text(this.stickerType === 'custom_emoji' ? $r('app.string.sp_loading_emoji') : $r('app.string.sp_loading_stickers'))
            .fontSize(13).fontColor(COLOR_TEXT_SECONDARY).margin({ top: 8 });
        }
        .layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else if (this.loadError !== '') {
        this.stateMessage($r('sys.symbol.exclamationmark_circle'), this.loadError,
          str('check_network_retry'), true);
      } else if (this.sets.length === 0) {
        this.stateMessage(
          this.stickerType === 'custom_emoji' ? $r('sys.symbol.face_smiling') : $r('sys.symbol.gift'),
          this.stickerType === 'custom_emoji' ? str('sp_no_emoji_packs') : str('sp_no_sticker_sets'),
          this.stickerType === 'custom_emoji' ? str('sp_classic_still_works') : str('sp_install_hint'),
          false
        );
      } else {
        // 顶部这一行身兼两职：平时是包切换条，点右端的放大镜就整行变成搜索框。
        // 原先搜索独占一行 30 高，在 260 的抽屉里和包条、标签条一起吃掉 108，
        // 留给表情网格的还不到一半。
        Stack({ alignContent: Alignment.End }) {
          if (!this.searchOpen) {
            // Pack tabs: cover thumbnails (official-style), title initial fallback.
            Scroll(this.tabScroller) {
              Row({ space: 6 }) {
                ForEach(this.sets, (t: StickerSetTab, idx: number) => {
                  Column() {
                    if (t.iconPath !== '') {
                      Image(`file://${t.iconPath}`).draggable(false)
                        .width(30).height(30).objectFit(ImageFit.Contain);
                    } else if (t.iconText !== '') {
                      Text(t.iconText).fontSize(22);
                    } else {
                      Text(t.title.length > 0 ? t.title.substring(0, 1) : '?')
                        .fontSize(15).fontWeight(FontWeight.Medium)
                        .fontColor(this.curSet === idx ? COLOR_PRIMARY : COLOR_TEXT_PRIMARY);
                    }
                  }
                  .width(38).height(38)
                  .justifyContent(FlexAlign.Center)
                  // 不画框：选中态用透明度区分。原来压一块 selected_pill 的圆角底，
                  // 在玻璃面板上看着就是给这个表情描了个边。
                  .backgroundColor(Color.Transparent)
                  .opacity(this.curSet === idx && this.searchQuery.trim() === '' ? 1 : 0.45)
                  .borderRadius(10)
                  .onClick(() => {
                    this.searchQuery = '';
                    this.searchItems = [];
                    this.selectSet(idx);
                  });
                }, (t: StickerSetTab) => `${t.id}_${t.iconPath}`);
              }
              // 右边留出按钮的位置，否则最后一个包永远压在按钮底下点不着。
              .padding({ left: 16, right: 52 });
            }
            .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
            // 让内容自己在右端淡出，而不是拿一块底色去挡。垫底色那版试过，
            // 玻璃面板上就是一块突兀的白，比露半个包还难看。
            .fadingEdge(true, { fadingEdgeLength: LengthMetrics.vp(28) })
            .width('100%').height(44);
          } else if (this.allowSearch) {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(15).fontColor([COLOR_TEXT_SECONDARY]);
              TextInput({
                text: this.searchQuery,
                placeholder: this.stickerType === 'custom_emoji' ? $r('app.string.sp_search_emoji') : $r('app.string.sp_search_stickers')
              })
                .fontSize(14).layoutWeight(1).height(30)
                .backgroundColor(Color.Transparent).padding(0)
                .placeholderColor(COLOR_TEXT_SECONDARY)
                .defaultFocus(true)
                .onChange((v: string) => { this.onSearchChanged(v); });
            }
            // 宽度得把两边的外边距一起扣掉。写 100% 再挂 margin，父容器是
            // Stack 且右对齐，多出来的 32 全从左边溢出去了。
            .width('calc(100% - 64vp)').height(32)
            .padding({ left: 12, right: 12 })
            .backgroundColor($r('app.color.surface_alt')).borderRadius(16)
            .alignItems(VerticalAlign.Center)
            // 右边 48 是给常驻按钮留的位置。
            .margin({ left: 16, right: 48 });
          }

          // 常驻按钮。自己是一块独立的玻璃（'control' 档：带按压光感），
          // 所以不用垫底色去挡——包滑到它下面时，两层玻璃叠着反而分得清。
          if (this.allowSearch) {
            Row() {
              Column() {
                SymbolGlyph(this.searchOpen ? $r('sys.symbol.xmark') : $r('sys.symbol.magnifyingglass'))
                  .fontSize(17)
                  .fontColor([this.searchOpen ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY]);
              }
              .width(32).height(32).borderRadius(16).clip(true)
              .justifyContent(FlexAlign.Center)
              .backgroundColor(overlayGlassFill('control', $r('app.color.surface_alt')))
              .backdropBlur(overlayBackdropBlur('control'))
              .systemMaterial(overlayMaterial('control'))
              .onClick(() => { this.toggleSearch(); });
            }
            .width(48).height(44)
            .justifyContent(FlexAlign.Center)
            .padding({ right: 12 })
            .hitTestBehavior(HitTestMode.Transparent);
          }
        }
        .width('100%').height(44);
        if (this.contentError !== '' && this.searchQuery.trim() === '') {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
              .fontSize(15).fontColor([COLOR_TEXT_SECONDARY]);
            Text(this.contentError).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
            Blank().layoutWeight(1);
            Text($r('app.string.settings_retry')).fontSize(13).fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Medium)
              .onClick(() => { this.retryCurrentSet(); });
          }
          .width('100%').height(30).padding({ left: 14, right: 14 })
          .backgroundColor($r('app.color.surface_alt'));
        } else if (this.loadingSet && this.searchQuery.trim() === '') {
          Row({ space: 7 }) {
            LoadingProgress().width(15).height(15).color(COLOR_PRIMARY);
            Text($r('app.string.sp_loading_sets')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
          }
          .width('100%').height(26).padding({ left: 14, right: 14 });
        }
        // Continuous grid: every loaded pack in one scroll, section headers
        // between packs; the tab strip follows the pack at the viewport top.
        if (this.searchLoading) {
          Column() {
            LoadingProgress().width(24).height(24).color(COLOR_PRIMARY);
            Text($r('app.string.searching')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY).margin({ top: 7 });
          }
          .layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
        } else if (this.searchError !== '') {
          Column({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.exclamationmark_circle')).fontSize(24)
              .fontColor([COLOR_TEXT_SECONDARY]);
            Text(this.searchError).fontSize(14).fontColor(COLOR_TEXT_PRIMARY);
            Text($r('app.string.settings_retry')).fontSize(14).fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Medium)
              .onClick(() => { this.runStickerSearch(); });
          }
          .layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
        } else if (this.searchQuery.trim() !== '' && this.searchItems.length === 0) {
          Column({ space: 7 }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(24)
              .fontColor([COLOR_TEXT_SECONDARY]);
            Text($r('app.string.no_results')).fontSize(14).fontColor(COLOR_TEXT_PRIMARY);
            Text($r('app.string.sp_try_another')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
          }
          .layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
        } else {
          Grid(this.gridScroller) {
            // LazyForEach: only visible cells mount, so at most a screenful of
            // Lottie canvases animate at once.
            LazyForEach(this.gridData, (e: FlatEntry) => {
              if (e.kind === 'header') {
                GridItem() {
                  Text(e.title)
                    .fontSize(13).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_SECONDARY)
                    .width('100%')
                    .padding({ top: 8, bottom: 2 });
                }
                .columnStart(0).columnEnd(this.stickerType === 'custom_emoji' ? 7 : 4);
              } else if (e.sticker !== null) {
                GridItem() {
                  this.stickerCell(e.sticker, `${e.setIdx}_${e.pos}`);
                }
              }
            }, (e: FlatEntry, index: number) => guardKey('stickers', index,
              e.kind === 'header'
                ? `h_${e.setIdx}_${e.title}`
                // setIdx + pos are what make this unique; the paths stay in so
                // the cell still rebuilds as its files arrive.
                : `s_${e.setIdx}_${e.pos}_${e.sticker!.fileId}_${e.sticker!.thumbPath}_${e.sticker!.srcPath}`));
          }
          .columnsTemplate(this.stickerType === 'custom_emoji'
            ? '1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr' : '1fr 1fr 1fr 1fr 1fr')
          .columnsGap(6).rowsGap(6)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .layoutWeight(1).width('100%')
          .onScrollIndex((first: number, last: number) => { this.onGridScrolled(first, last); });
        }
      }
    }
    .width('100%').height('100%');
  }
}
