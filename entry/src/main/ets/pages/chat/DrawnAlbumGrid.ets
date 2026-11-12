import { AlbumGroup } from '../../util/collapseAlbums';
import { AlbumCellRenderData } from '../../util/albumCellRenderData';
import { thumbBackdropColor } from '../../util/thumbBackdrop';
import { MINI_PLACEHOLDER_BLUR } from '../../util/miniThumbPlaceholder';
import { scrollPlaceholderState } from '../../util/scrollEffects';
import { str } from '../../util/strings';
import { chatEnv } from '../../util/chatEnvMirror';
import { DrawnBubbleTile } from './DrawnBubblePlan';
import { DrawnAlbumGridLayouts, DrawnAlbumGridPlan } from './DrawnAlbumGridLayout';
import { DrawnAlbumGridMedia } from './DrawnAlbumGridMedia';
import { DrawnAlbumGridSelection } from './DrawnAlbumGridSelection';
import { DrawnAlbumVideo } from './DrawnAlbumVideo';
import { LiveProgressRing } from './LiveProgressRing';
import { MessageBubbleContext } from './MessageBubbleShell';
import { MessageBubbleActions, MessageBubbleRenderData } from './ReusableMessageBubble';

// All intrinsic-content album routes use this grid: reactions, translation,
// complex captions, glass, accessibility and outgoing uploads. A fixed native
// anchor per tile preserves transition, clipping, click and accessibility;
// loading ownership and selection drawing are shared at grid scope.
@ComponentV2
export struct DrawnAlbumGrid {
  @Require @Param group: AlbumGroup;
  @Require @Param data: MessageBubbleRenderData;
  @Require @Param actions: MessageBubbleActions;
  @Require @Param context: MessageBubbleContext;
  @Param gridWidth: number = 0;
  @Param gridCorners: BorderRadiuses = {};
  @Local private imageEpoch: number = 0;
  private env = chatEnv;
  private scroll = scrollPlaceholderState;
  private layouts: DrawnAlbumGridLayouts = new DrawnAlbumGridLayouts();
  private media: DrawnAlbumGridMedia = new DrawnAlbumGridMedia((): void => { this.imageEpoch++; });
  private selectionPainter: DrawnAlbumGridSelection = new DrawnAlbumGridSelection();
  private active: boolean = false;
  private identity: string = '';
  private generation: number = 0;
  private touchedGeneration: number = -1;

  @Computed
  private get plan(): DrawnAlbumGridPlan {
    const appearance = this.env.appearanceEpoch;
    return this.layouts.prepare(this.group, this.data, this.gridWidth,
      appearance < 0 ? 1 : this.getUIContext().vp2px(1));
  }
  private bindIdentity(): number {
    const key = `${this.data.chatId}:${this.group.head.rowId}`;
    if (key !== this.identity) { this.identity = key; this.generation++; this.touchedGeneration = -1; }
    return this.generation;
  }
  private sync(): void {
    this.bindIdentity();
    if (this.active) { this.media.prepare(this.getUIContext(), this.plan); }
  }
  @Monitor('plan', 'group')
  private inputChanged(): void { this.sync(); }
  aboutToAppear(): void { this.active = true; this.sync(); }
  aboutToReuse(): void { this.active = true; this.sync(); }
  aboutToRecycle(): void {
    this.active = false; this.generation++; this.identity = ''; this.touchedGeneration = -1; this.media.recycle();
  }
  aboutToDisappear(): void {
    this.active = false; this.generation++; this.identity = ''; this.touchedGeneration = -1; this.media.dispose();
  }
  private cellAt(index: number): AlbumCellRenderData | undefined { return this.plan.tiles[index]?.cell; }
  private missing(index: number): boolean { return this.imageEpoch >= 0 && (this.media.slots[index]?.path ?? '') === ''; }
  private ready(index: number): boolean {
    const cell = this.cellAt(index);
    return !this.missing(index) || cell?.thumbFileId === 0 || cell?.failed === true;
  }
  private label(index: number): string {
    const cell = this.cellAt(index), epoch = this.env.langEpoch;
    if (cell === undefined || epoch < 0) { return ''; }
    return cell.isVideo ? str('mb_album_item_video', index + 1)
      : cell.failed ? str('mb_photo_failed') : str('mb_album_item', index + 1);
  }
  private clickCallback(tile: DrawnBubbleTile): (event: ClickEvent) => void {
    const generation = this.bindIdentity(), index = tile.cell.idx, key = tile.key;
    return (event: ClickEvent): void => {
      const current = this.plan.tiles[index];
      if (!this.active || generation !== this.generation || current?.key !== key || this.context.gestureClaimed ||
        (event.source === SourceType.TouchScreen && this.touchedGeneration !== generation)) { return; }
      const cell = current.cell;
      if (cell.selectionActive) { this.actions.onToggleSelectedMessage(cell.messageId); }
      else if (cell.failed && cell.thumbFileId !== 0 && this.missing(index)) { this.actions.onSpecialPhotoRetry(cell.messageId); }
      else { this.actions.onMediaTap(cell.messageId, event.windowX, event.windowY); }
    };
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      ForEach(this.plan.tiles, (tile: DrawnBubbleTile) => {
        Stack() {
          if (this.imageEpoch >= 0 && this.media.slots[tile.cell.idx]?.pixels !== undefined &&
            !this.media.slots[tile.cell.idx]?.receiver.canDraw(this.media.slots[tile.cell.idx]?.pixels, ImageFit.Cover)) {
            Image(this.media.slots[tile.cell.idx]?.pixels).width(tile.width).height(tile.height)
              .draggable(false).objectFit(ImageFit.Cover).syncLoad(true);
          }
          if (this.imageEpoch >= 0 && this.media.slots[tile.cell.idx]?.showMini(this.scroll.active)) {
            Image(this.media.slots[tile.cell.idx]?.mini ?? '').width(tile.width).height(tile.height)
              .draggable(false).objectFit(ImageFit.Cover).blur(MINI_PLACEHOLDER_BLUR);
          }
          if (this.cellAt(tile.cell.idx)?.uploading) {
            LiveProgressRing({ fileId: this.cellAt(tile.cell.idx)?.isVideo
              ? this.cellAt(tile.cell.idx)?.videoFileId ?? 0 : this.cellAt(tile.cell.idx)?.thumbFileId ?? 0,
              initialPercent: 0, ringSize: Math.min(34, Math.min(tile.width, tile.height) * .4) });
          } else if (this.missing(tile.cell.idx)) {
            if (!this.cellAt(tile.cell.idx)?.isVideo &&
              (this.cellAt(tile.cell.idx)?.failed || this.cellAt(tile.cell.idx)?.thumbFileId === 0)) {
              Column({ space: 3 }) {
                SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(17).fontColor([Color.White]);
                Text($r('app.string.settings_retry')).fontSize(11).fontColor(Color.White);
              }.padding(7).backgroundColor('#80000000').borderRadius(18);
            } else if ((this.cellAt(tile.cell.idx)?.thumbFileId ?? 0) !== 0 && !this.cellAt(tile.cell.idx)?.failed) {
              LiveProgressRing({ fileId: this.cellAt(tile.cell.idx)?.thumbFileId ?? 0,
                initialPercent: this.cellAt(tile.cell.idx)?.progress ?? 0,
                ringSize: Math.min(34, Math.min(tile.width, tile.height) * .4) });
            }
          }
          if (tile.cell.isVideo || tile.cell.isLive) {
            DrawnAlbumVideo({ cell: this.cellAt(tile.cell.idx), actions: this.actions, thumbReady: this.ready(tile.cell.idx) });
          }
        }.width(tile.width).height(tile.height).position({ x: tile.x, y: tile.y })
        .backgroundColor(thumbBackdropColor(tile.cell.isVideo)).borderRadius(6).clip(true)
        .drawModifier(this.media.slots[tile.cell.idx]?.receiver)
        .geometryTransition(tile.cell.isVideo ? '' : `media_${tile.cell.chatId}_${tile.cell.messageId}`)
        .accessibilityText(this.label(tile.cell.idx))
        .onClick(this.clickCallback(tile));
      }, (tile: DrawnBubbleTile): string => tile.key);
      Row().width(this.plan.width).height(this.plan.height)
        .drawModifier(this.selectionPainter.bind(this.plan, this.env.appearanceEpoch)).hitTestBehavior(HitTestMode.None)
        .accessibilityLevel('no');
    }.width(this.plan.width).height(this.plan.height).borderRadius(this.gridCorners).clip(true)
    .onTouch((event: TouchEvent): void => {
      if (event.type === TouchType.Down) { this.touchedGeneration = this.bindIdentity(); }
      else if (event.type === TouchType.Cancel || event.touches.length > 1) { this.touchedGeneration = -1; }
    });
  }
}
