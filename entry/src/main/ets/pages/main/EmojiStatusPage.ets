import { router, promptAction } from '@kit.ArkUI';
import { getTdClient } from '../../tdkit/Globals';
import { TdError, TdObject, TdRequest } from '../../tdkit/TdTypes';
import {
  clearRecentEmojiStatuses, getDefaultEmojiStatuses, getRecentEmojiStatuses, setEmojiStatus
} from '../../store/StickerApi';
import { TgsStickerView } from '../chat/TgsStickerView';
import {
  COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';
import { logE, logW } from '../../util/log';
import { HdsSubDestination } from '../common/HdsSubDestination';

const CARD_RADIUS: number = 14;
const CELL: number = 52;

interface StatusEmoji {
  customEmojiId: string;
  thumbPath: string;
  srcPath: string;
  format: string;
  fallback: string;
}

// 路由表（router_map.json）的 buildFunction 指向这里。系统在跳转时动态加载本模块
// 并调用它，页面因此不再进 main_pages.json——一个页面不能同时是 router 页和
// NavDestination。形状与试点的 PowerUsagePageBuilder 一致。
@Builder
export function EmojiStatusPageBuilder(): void {
  EmojiStatusPage();
}

@Component
export struct EmojiStatusPage {
  private hdsScroller: Scroller = new Scroller();
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State recent: StatusEmoji[] = [];
  @State suggested: StatusEmoji[] = [];
  @State loadState: string = 'loading';
  @State busy: boolean = false;
  private active: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    this.load();
  }

  aboutToDisappear(): void {
    this.active = false;
  }

  // Resolve custom-emoji ids to renderable stickers in one request.
  private resolve(ids: string[]): Promise<StatusEmoji[]> {
    if (ids.length === 0) { return Promise.resolve([]); }
    const req: TdRequest = { '@type': 'getCustomEmojiStickers' };
    req['custom_emoji_ids'] = ids;
    return getTdClient().send(req, 12000).then((result: TdObject): StatusEmoji[] => {
      const stickers = (result['stickers'] as TdObject[] | undefined) ?? [];
      const rows: StatusEmoji[] = [];
      for (const st of stickers) {
        const fullType = st['full_type'] as TdObject | undefined;
        const id = fullType !== undefined ? `${fullType['custom_emoji_id'] ?? ''}` : '';
        if (id === '') { continue; }
        const fmt = st['format'] as TdObject | undefined;
        const fmtName = fmt !== undefined ? ((fmt['@type'] as string | undefined) ?? '') : '';
        const row: StatusEmoji = {
          customEmojiId: id,
          thumbPath: '',
          srcPath: '',
          format: fmtName === 'stickerFormatTgs' ? 'tgs'
            : (fmtName === 'stickerFormatWebm' ? 'webm' : 'webp'),
          fallback: (st['emoji'] as string | undefined) ?? '🙂'
        };
        rows.push(row);
        const file = st['sticker'] as TdObject | undefined;
        const fileId = file !== undefined ? ((file['id'] as number | undefined) ?? 0) : 0;
        if (fileId > 0) { this.downloadSticker(id, fileId, row.format); }
      }
      return rows;
    });
  }

  private downloadSticker(customEmojiId: string, fileId: number, format: string): void {
    const req: TdRequest = { '@type': 'downloadFile' };
    req['file_id'] = fileId;
    req['priority'] = 4;
    req['synchronous'] = true;
    getTdClient().send(req, 20000).then((file: TdObject): void => {
      if (!this.active) { return; }
      const local = file['local'] as TdObject | undefined;
      const path = local !== undefined ? ((local['path'] as string | undefined) ?? '') : '';
      if (path === '') { return; }
      const patch = (rows: StatusEmoji[]): StatusEmoji[] => rows.map(
        (row: StatusEmoji): StatusEmoji => row.customEmojiId === customEmojiId
          ? {
            customEmojiId: row.customEmojiId,
            thumbPath: format === 'webp' ? path : row.thumbPath,
            srcPath: format === 'webp' ? row.srcPath : path,
            format: row.format, fallback: row.fallback
          } : row);
      this.recent = patch(this.recent);
      this.suggested = patch(this.suggested);
    }).catch((): void => {});
  }

  private load(): void {
    this.loadState = 'loading';
    Promise.all([getRecentEmojiStatuses(), getDefaultEmojiStatuses()])
      .then((lists: string[][]): Promise<StatusEmoji[][]> =>
        Promise.all([this.resolve(lists[0]), this.resolve(lists[1])]))
      .then((resolved: StatusEmoji[][]): void => {
        if (!this.active) { return; }
        this.recent = resolved[0];
        this.suggested = resolved[1];
        this.loadState = 'ready';
      }).catch((error: TdError): void => {
        if (!this.active) { return; }
        logE(`EmojiStatusPage.load failed: ${error.message}`);
        this.loadState = 'error';
      });
  }

  private apply(customEmojiId: string): void {
    if (this.busy) { return; }
    this.busy = true;
    setEmojiStatus(customEmojiId).then((): void => {
      if (!this.active) { return; }
      this.busy = false;
      promptAction.showToast({
        message: customEmojiId === '' ? $r('app.string.emoji_status_cleared') : $r('app.string.emoji_status_updated'), duration: 1500
      });
    }).catch((error: TdError): void => {
      if (!this.active) { return; }
      this.busy = false;
      logE(`EmojiStatusPage.apply failed: ${error.message}`);
      promptAction.showToast({
        message: error.message.indexOf('PREMIUM') >= 0 || error.message.indexOf('premium') >= 0
          ? $r('app.string.emoji_status_needs_premium') : $r('app.string.apply_failed_retry'),
        duration: 1900
      });
    });
  }

  @Builder
  cell(row: StatusEmoji) {
    Stack({ alignContent: Alignment.Center }) {
      if (row.format === 'tgs' && row.srcPath !== '') {
        TgsStickerView({
          tgsPath: row.srcPath, thumbPath: row.thumbPath,
          boxWidth: CELL - 10, boxHeight: CELL - 10, powerCategory: 'emoji'
        });
      } else if (row.thumbPath !== '') {
        Image(`file://${row.thumbPath}`).draggable(false).width(CELL - 12).height(CELL - 12)
          .objectFit(ImageFit.Contain);
      } else {
        Text(row.fallback).fontSize(24);
      }
    }
    .width(CELL).height(CELL).borderRadius(12)
    .onClick((): void => this.apply(row.customEmojiId));
  }

  @Builder
  section(title: ResourceStr, rows: StatusEmoji[]) {
    Column({ space: 8 }) {
      Text(title).fontSize(12).fontColor(COLOR_TEXT_SECONDARY).width('100%');
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        ForEach(rows, (row: StatusEmoji) => {
          Column() { this.cell(row); }.padding(3);
        }, (row: StatusEmoji): string => `st_${row.customEmojiId}`);
      }
    }
    .width('100%').padding(12).backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
  }

  build() {
    Column() {
    // 内联的顶栏搬进标题栏了。
    HdsSubDestination({ title: $r('app.string.settings_emoji_status'), pageBackground: COLOR_PAGE_BG, scroller: this.hdsScroller, subTitle: this.busy ? $r('app.string.refreshing') : '' }) {
      Column() {
      if (this.loadState === 'loading') {
        Column({ space: 9 }) {
          LoadingProgress().width(32).height(32).color(COLOR_PRIMARY);
          Text($r('app.string.emoji_status_loading')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else if (this.loadState === 'error') {
        Column({ space: 10 }) {
          Text($r('app.string.load_failed')).fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
          Button($r('app.string.settings_reload')).onClick((): void => this.load());
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else {
        Scroll(this.hdsScroller) {
          Column({ space: 12 }) {
            Row({ space: 10 }) {
              SymbolGlyph($r('sys.symbol.xmark_circle')).fontSize(18).fontColor([COLOR_PRIMARY]);
              Text($r('app.string.emoji_status_clear')).fontSize(15).fontColor(COLOR_PRIMARY).layoutWeight(1);
            }
            .width('100%').height(48).padding({ left: 14, right: 14 })
            .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS)
            .onClick((): void => this.apply(''));
            if (this.recent.length > 0) {
              this.section($r('app.string.emoji_status_recent'), this.recent);
            }
            if (this.suggested.length > 0) {
              this.section($r('app.string.emoji_status_suggested'), this.suggested);
            }
            if (this.recent.length > 0) {
              Text($r('app.string.emoji_status_clear_recent')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
                .onClick((): void => {
                  clearRecentEmojiStatuses().then((): void => {
                    this.recent = [];
                    promptAction.showToast({ message: $r('app.string.cleared'), duration: 1300 });
                  }).catch((): void => {});
                });
            }
            Text($r('app.string.emoji_status_note'))
              .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).lineHeight(18).width('100%');
          }.width('100%').padding({ left: 12, right: 12, bottom: this.bottomSafe + 24 });
        }
        // **Scroll 的 align 默认是 Center**，内容比视口短时会被垂直居中。
        // 本页在非 Premium 账号下只有"清除当前状态"一行加一句说明，于是整块
        // 悬在屏幕中间、离标题老远（issue #120）。全应用的纵向页面滚动区都要
        // 显式写这一句，别指望默认值。
        .align(Alignment.Top)
        .layoutWeight(1).width('100%').scrollBar(BarState.Off)
        // 不裁剪，内容才能穿到标题栏底下。
        .clip(false);
      }
      }.width('100%').height('100%');
    }
    }.width('100%').height('100%');
  }
}
