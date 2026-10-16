import { FolderInfo } from '../../store/FolderStore';
import { forwardFolderChips, ForwardFolderChip } from '../../util/forwardFolders';
import { COLOR_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';

@Component
export struct TargetFolderTabs {
  @Prop folders: FolderInfo[] = [];
  @Prop folderId: number = 0;
  onSelect: (id: number) => void = (): void => {};

  build() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(forwardFolderChips(this.folders), (chip: ForwardFolderChip) => {
          Text(chip.isAll ? $r('app.string.filter_all') : chip.title)
            .fontSize(13)
            .fontWeight(chip.id === this.folderId ? FontWeight.Medium : FontWeight.Regular)
            .fontColor(chip.id === this.folderId ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: 140 })
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(16)
            .backgroundColor(chip.id === this.folderId ? '#1A3390EC' : $r('app.color.surface_alt'))
            .onClick((): void => { this.onSelect(chip.id); });
        }, (chip: ForwardFolderChip): string => `chip_${chip.id}`);
      }
      .padding({ left: 2, right: 2 });
    }
    .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
    .width('100%').align(Alignment.Start);
  }
}
