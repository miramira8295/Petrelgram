import { MINI_PLACEHOLDER_BLUR } from '../../util/miniThumbPlaceholder';
import { DrawnMediaRetry } from './DrawnMediaRetry';
import { DrawnPaidMediaGridCell, DrawnPaidMediaGridPlan } from './DrawnPaidMediaGridLayout';
import { DrawnPaidMediaGridController } from './DrawnPaidMediaGridController';
import { DrawnDocumentPlayback } from './DrawnDocumentPlayback';
import { PaidMediaSet } from '../../util/paidMediaModel';
import { str } from '../../util/strings';
import { LiveProgressRing } from './LiveProgressRing';

@ComponentV2
export struct DrawnPaidMediaGrid {
  @Require @Param mediaSet: PaidMediaSet;
  @Require @Param gridPlan: DrawnPaidMediaGridPlan;
  @Param ownerKey: string = '';
  @Param locked: boolean = true;
  @Param density: number = 1;
  @Event onOpen: (index: number) => void = (): void => {};
  @Local private imageRevision: number = 0;
  private media: DrawnPaidMediaGridController = new DrawnPaidMediaGridController((): void => { this.imageRevision++; });
  private active: boolean = false;
  private generation: number = 0;
  private boundOwner: string = '';
  private boundSet: PaidMediaSet | null = null;
  private touchGeneration: number = -1;
  private sync(): void {
    if (this.boundOwner !== this.ownerKey || this.boundSet !== this.mediaSet) {
      this.generation++; this.touchGeneration = -1; this.boundOwner = this.ownerKey; this.boundSet = this.mediaSet;
    }
    if (this.active) { this.media.bind(this.getUIContext(), this.mediaSet, this.gridPlan, this.ownerKey, this.locked, this.density); }
  }
  @Monitor('mediaSet', 'gridPlan', 'ownerKey', 'locked', 'density') private changed(): void { this.sync(); }
  aboutToAppear(): void { this.active = true; this.sync(); }
  aboutToReuse(): void { this.active = true; this.generation++; this.touchGeneration = -1; this.sync(); }
  aboutToRecycle(): void { this.active = false; this.generation++; this.touchGeneration = -1; this.media.recycle(); }
  aboutToDisappear(): void { this.active = false; this.generation++; this.media.dispose(); }
  private hasPixels(index: number, _revision: number): boolean { return this.media.slots[index]?.pixels !== undefined; }
  private nativePixels(index: number, _revision: number): boolean {
    const slot = this.media.slots[index];
    return slot?.pixels !== undefined && !slot.receiver.canDraw(slot.pixels, ImageFit.Cover);
  }
  private click(index: number): (event: ClickEvent) => void {
    const generation = this.generation;
    return (event: ClickEvent): void => {
      if (!this.active || generation !== this.generation || this.mediaSet.items[index] === undefined ||
        (event.source === SourceType.TouchScreen && this.touchGeneration !== generation)) { return; }
      // Even loading/failed cells remain openable. The viewer owns the full-file
      // request; a poster retry must not swallow the media click.
      this.onOpen(index);
    };
  }
  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      ForEach(this.gridPlan.cells, (cell: DrawnPaidMediaGridCell) => {
        Stack() {
          if (this.nativePixels(cell.index, this.imageRevision)) {
            Image(this.media.slots[cell.index]?.pixels).width(cell.width).height(cell.height)
              .draggable(false).syncLoad(true).objectFit(ImageFit.Cover);
          }
          if (!this.hasPixels(cell.index, this.imageRevision)) {
            if ((this.mediaSet.items[cell.index]?.mini ?? '') !== '') {
              // Locked previews retain immediate obscuring; never show an unfiltered frame while a cache job waits.
              Image(this.mediaSet.items[cell.index]?.mini ?? '').width(cell.width).height(cell.height)
                .objectFit(ImageFit.Cover).draggable(false).blur(MINI_PLACEHOLDER_BLUR);
            }
            if (!this.locked && (this.media.slots[cell.index]?.fileId ?? 0) > 0) {
              if (this.media.slots[cell.index]?.failed) {
                DrawnMediaRetry({ labelKey: '', iconSize: 22, paddingX: 0, paddingY: 0, tone: '#00000000', maxWidth: cell.width });
              } else {
                LiveProgressRing({ fileId: this.media.slots[cell.index]?.fileId ?? 0,
                  ringSize: Math.min(34, Math.min(cell.width, cell.height) * .4) });
              }
            }
          }
          if (!this.locked && this.mediaSet.items[cell.index]?.media?.kind === 'video') {
            DrawnDocumentPlayback({ media: this.mediaSet.items[cell.index].media!,
              boxWidth: cell.width, boxHeight: cell.height, posterPath: this.media.slots[cell.index]?.path ?? '' })
              .hitTestBehavior(HitTestMode.None);
          }
        }
        .width(cell.width).height(cell.height).position({ x: cell.x, y: cell.y })
        .backgroundColor('#D8DDE4').borderRadius(cell.corners).clip(true)
        .drawModifier(this.media.slots[cell.index]?.receiver)
        .accessibilityText(str(this.mediaSet.items[cell.index]?.kind === 'video' ? 'preview_video' : 'preview_photo'))
        .onClick(this.click(cell.index));
      }, (cell: DrawnPaidMediaGridCell): string => `${cell.index}`);
    }
    .width(this.gridPlan.width).height(this.gridPlan.height).borderRadius(12).clip(true)
    .onTouch((event: TouchEvent): void => {
      if (event.type === TouchType.Down) { this.touchGeneration = this.generation; }
      else if (event.type === TouchType.Cancel || event.touches.length > 1) { this.touchGeneration = -1; }
    });
  }
}
