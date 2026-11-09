import { StickerPreviewHold } from './StickerPreviewHold';
import { getTdClient } from '../../tdkit/Globals';
import { TdObject, TdRequest } from '../../tdkit/TdTypes';
import { rememberFavoriteSticker } from '../../store/FavoriteStickers';
import { COLOR_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { TgsStickerView } from './TgsStickerView';
import { SmartLoopVideo } from '../common/SmartLoopVideo';
import { StickerPreviewData, StickerPreviewSession, StickerPreviewSnapshot, emptyStickerPreview } from './StickerPreviewSession';

@CustomDialog
export struct StickerPreviewDialog {
  controller?: CustomDialogController;
  hold: StickerPreviewHold = new StickerPreviewHold();
  @State selected: boolean = false;
  data: StickerPreviewData = { fileId: 0, format: '', emoji: '', thumbPath: '', width: 512, height: 512, canFavorite: true };
  onClosed: () => void = (): void => {};
  ownerActive: () => boolean = (): boolean => true;
  onFavorite: (favorite: boolean) => void = (): void => {};
  @State view: StickerPreviewSnapshot = emptyStickerPreview();
  @StorageProp('appIsForeground') @Watch('onForeground') foreground: boolean = true;
  @StorageProp('tdSessionEpoch') @Watch('close') accountEpoch: number = 0;
  private session: StickerPreviewSession | null = null;
  private alive: boolean = false;

  aboutToAppear(): void {
    this.alive = true;
    this.hold.onSelection = (selected: boolean): void => { this.selected = selected; };
    const client = getTdClient();
    this.session = new StickerPreviewSession({
      send: (request: TdRequest, timeout: number): Promise<TdObject> => client.send(request, timeout)
    }, this.data, (): boolean => this.alive && this.foreground && this.ownerActive() && getTdClient() === client,
    (view: StickerPreviewSnapshot): void => { this.view = view; },
    (favorite: boolean): void => {
      rememberFavoriteSticker(this.data.fileId, favorite);
      this.onFavorite(favorite);
    });
    this.session.loadFile();
  }
  aboutToDisappear(): void {
    this.hold.cancel();
    this.alive = false; this.session?.close(); this.session = null; this.onClosed();
  }
  private close(): void { this.hold.cancel(); this.alive = false; this.session?.close(); this.controller?.close(); }
  private onForeground(): void { if (!this.foreground) { this.close(); } }
  private boxWidth(): number { return 240 * Math.min(1, Math.max(1, this.data.width) / Math.max(1, this.data.height)); }
  private boxHeight(): number { return 240 * Math.min(1, Math.max(1, this.data.height) / Math.max(1, this.data.width)); }

  build() {
    Column({ space: 16 }) {
      Stack() {
        if (this.view.path !== '') {
          if (this.data.format === 'tgs') {
            TgsStickerView({ tgsPath: this.view.path, thumbPath: this.data.thumbPath,
              boxWidth: this.boxWidth(), boxHeight: this.boxHeight(), powerCategory: this.data.canFavorite ? 'sticker' : 'emojiPicker' });
          } else if (this.data.format === 'webm') {
            SmartLoopVideo({ videoPath: this.view.path, stickerUid: this.view.uid, thumbPath: this.data.thumbPath,
              boxWidth: this.boxWidth(), boxHeight: this.boxHeight(), powerCategory: this.data.canFavorite ? 'sticker' : 'emojiPicker' });
          } else {
            Image(`file://${this.view.path}`).width(this.boxWidth()).height(this.boxHeight())
              .objectFit(ImageFit.Contain).draggable(false);
          }
        } else if (this.data.thumbPath !== '') {
          Image(this.data.thumbPath.startsWith('/') ? `file://${this.data.thumbPath}` : this.data.thumbPath)
            .width(240).height(240).objectFit(ImageFit.Contain).draggable(false);
        } else {
          Text(this.data.emoji).fontSize(64);
        }
        if (this.view.loading) { LoadingProgress().width(36).height(36).color(COLOR_PRIMARY); }
      }.width(240).height(240)
      .border({ width: this.selected ? 3 : 0, color: COLOR_PRIMARY }).borderRadius(16)
      .backgroundColor(this.selected ? $r('app.color.selected_pill') : Color.Transparent)
      .onAreaChange((_old: Area, area: Area): void => {
        this.hold.bounds(Number(area.globalPosition.x), Number(area.globalPosition.y), Number(area.width), Number(area.height));
      });
      if (this.view.failed) {
        Text($r('app.string.load_failed')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
      }
    }.padding(20).backgroundColor($r('app.color.surface')).borderRadius(24)
      .hitTestBehavior(HitTestMode.None);
  }
}
