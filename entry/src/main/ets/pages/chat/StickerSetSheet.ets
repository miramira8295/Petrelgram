// 「这张贴纸是哪一包的」——点消息里的贴纸弹出来的合集面板。
//
// 只读一屏：合集名、内容网格、底部「添加/移除贴纸」。点格子直接把那张贴纸发到
// 当前会话（和官方端一致）。动态贴纸在这里只画缩略图，不起 Lottie/视频：一屏
// 几十格，全部动起来是一次可见的掉帧，而这张面板的用途是"认包"不是"看动画"。
import { getTdClient } from '../../tdkit/Globals';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import { parseStickerSetInfo, parseStickerSetItems, StickerSetInfo, StickerSetItem } from '../../util/stickerSetItems';
import { setStickerSetInstalled } from '../../store/StickerApi';
import { COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY, COLOR_PRIMARY } from '../../util/theme';
import { str } from '../../util/strings';
import { promptAction } from '@kit.ArkUI';
import { logE } from '../../util/log';

@ComponentV2
export struct StickerSetSheet {
  @Param setId: string = '';
  @Event onPick: (item: StickerSetItem) => void = (): void => {};

  @Local items: StickerSetItem[] = [];
  @Local info: StickerSetInfo = { id: '', title: '', name: '', installed: false, count: 0 };
  @Local loading: boolean = true;
  @Local failed: boolean = false;
  @Local busy: boolean = false;
  private disposed: boolean = false;

  aboutToAppear(): void {
    this.load();
  }

  aboutToDisappear(): void {
    this.disposed = true;
  }

  private load(): void {
    const req: TdRequest = { '@type': 'getStickerSet' };
    req['set_id'] = this.setId;
    getTdClient().send(req, 12000).then((res: TdObject): void => {
      if (this.disposed) { return; }
      this.info = parseStickerSetInfo(res);
      this.items = parseStickerSetItems(res);
      this.loading = false;
      this.failed = false;
      this.downloadThumbs();
    }).catch((e: TdError): void => {
      if (this.disposed) { return; }
      this.loading = false;
      this.failed = true;
      logE(`StickerSetSheet.getStickerSet failed: ${e.message}`);
    });
  }

  // 缩略图逐张同步下载（每张几 KB），到一张补一张。
  // 不批量等全部到齐：合集可以有 120 张，等齐就是一屏空白等好几秒。
  private downloadThumbs(): void {
    for (const item of this.items) {
      if (item.thumbFileId === 0 || item.thumbPath !== '') {
        continue;
      }
      const req: TdRequest = { '@type': 'downloadFile' };
      req['file_id'] = item.thumbFileId;
      req['priority'] = 1;
      req['synchronous'] = true;
      const wanted: number = item.fileId;
      getTdClient().send(req).then((f: TdObject): void => {
        if (this.disposed) { return; }
        const local = f['local'] as TdObject | undefined;
        const path: string = local !== undefined ? ((local['path'] as string | undefined) ?? '') : '';
        if (path === '') { return; }
        this.items = this.items.map((s: StickerSetItem): StickerSetItem => s.fileId !== wanted ? s : {
          fileId: s.fileId, thumbFileId: s.thumbFileId, thumbPath: path,
          format: s.format, emoji: s.emoji, width: s.width, height: s.height
        });
      }).catch((e: TdError): void => {
        logE(`StickerSetSheet.downloadThumb failed: ${e.message}`);
      });
    }
  }

  private toggleInstalled(): void {
    if (this.busy || this.info.id === '') { return; }
    this.busy = true;
    const next: boolean = !this.info.installed;
    setStickerSetInstalled(this.info.id, next, false).then((): void => {
      if (this.disposed) { return; }
      this.busy = false;
      this.info = {
        id: this.info.id, title: this.info.title, name: this.info.name,
        installed: next, count: this.info.count
      };
      promptAction.showToast({
        message: next ? $r('app.string.ss_added') : $r('app.string.ss_removed'), duration: 1500
      });
    }).catch((e: TdError): void => {
      if (this.disposed) { return; }
      this.busy = false;
      logE(`StickerSetSheet.changeStickerSet failed: ${e.message}`);
      promptAction.showToast({ message: $r('app.string.ss_action_failed'), duration: 1800 });
    });
  }

  build() {
    Column() {
      Column({ space: 2 }) {
        Text(this.info.title !== '' ? this.info.title : str('sticker_tab'))
          .fontSize(17).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(str('ss_count', `${this.items.length}`))
          .fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
      }
      .width('100%').alignItems(HorizontalAlign.Start)
      .padding({ left: 16, right: 56, bottom: 8 });

      if (this.loading) {
        Column() {
          LoadingProgress().width(36).height(36).color(COLOR_PRIMARY);
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center);
      } else if (this.failed) {
        Column() {
          Text($r('app.string.ss_load_failed'))
            .fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center);
      } else {
        Grid() {
          ForEach(this.items, (item: StickerSetItem): void => {
            GridItem() {
              Stack() {
                if (item.thumbPath !== '') {
                  Image(item.thumbPath.startsWith('/') ? `file://${item.thumbPath}` : item.thumbPath)
                    .draggable(false)
                    .width('86%').height('86%').objectFit(ImageFit.Contain);
                } else {
                  // 缩略图还没到：用贴纸自带的 emoji 顶位，格子高度不跳。
                  Text(item.emoji).fontSize(26);
                }
              }
              .width('100%').aspectRatio(1)
              .onClick((): void => { this.onPick(item); });
            }
          }, (item: StickerSetItem): string => `${item.fileId}`);
        }
        .columnsTemplate('1fr 1fr 1fr 1fr')
        .rowsGap(6).columnsGap(6)
        .width('100%').layoutWeight(1)
        .padding({ left: 12, right: 12 })
        .scrollBar(BarState.Off);
      }

      if (!this.loading && !this.failed) {
        Button(this.info.installed ? $r('app.string.ss_remove') : $r('app.string.ss_add'))
          .fontSize(16)
          .fontColor(this.info.installed ? Color.Red : Color.White)
          .backgroundColor(this.info.installed ? $r('app.color.surface_alt') : COLOR_PRIMARY)
          .width('100%').height(44).borderRadius(12)
          .enabled(!this.busy)
          .margin({ top: 10 })
          .onClick((): void => { this.toggleInstalled(); });
      }
    }
    .width('100%').height('100%')
    // 顶部 44 给 bindSheet 自带的关闭按钮让位（同 diceSheet）。
    .padding({ left: 16, right: 16, top: 44, bottom: 16 });
  }
}
