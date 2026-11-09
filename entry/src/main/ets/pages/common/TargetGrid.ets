import { ShareRow, targetDisplayKey } from '../../util/shareSearch';
import { KeyedListDataSource } from './KeyedListDataSource';
import { TargetAvatarCell } from './TargetAvatarCell';
import { forwardColumnsTemplate, forwardGridColumns } from '../../util/forwardFolders';

@Observed
export class TargetRowState {
  readonly id: number;
  row: ShareRow;
  private signature: string;
  constructor(row: ShareRow) {
    this.id = row.chatId;
    this.row = row;
    this.signature = targetDisplayKey(row);
  }
  update(row: ShareRow): void {
    const signature: string = targetDisplayKey(row);
    if (signature !== this.signature) {
      this.signature = signature;
      this.row = row;
    }
  }
}

@Component
struct TargetRowCell {
  @ObjectLink target: TargetRowState;
  @Prop selected: boolean = false;
  @Prop busy: boolean = false;
  build() {
    TargetAvatarCell({ avatarPath: this.target.row.avatarPath, initials: this.target.row.initials,
      colorSeed: this.target.id, savedMessages: this.target.row.isSavedMessages,
      title: this.target.row.title, selected: this.selected, busy: this.busy });
  }
}

@Component
export struct TargetGrid {
  @Prop @Watch('syncRows') rows: ShareRow[] = [];
  @Prop selectedIds: number[] = [];
  @Prop busyId: number = 0;
  @StorageProp('screenWidthVp') screenW: number = 360;
  onToggle: (id: number) => void = (): void => {};
  onMore: () => void = (): void => {};
  private states: Map<number, TargetRowState> = new Map<number, TargetRowState>();
  private data: KeyedListDataSource<TargetRowState> = new KeyedListDataSource<TargetRowState>('target-grid');

  aboutToAppear(): void { this.syncRows(); }
  private syncRows(): void {
    const next: TargetRowState[] = [];
    const live: Set<number> = new Set<number>();
    for (const row of this.rows) {
      if (live.has(row.chatId)) { continue; }
      live.add(row.chatId);
      let state: TargetRowState | undefined = this.states.get(row.chatId);
      if (state === undefined) {
        state = new TargetRowState(row);
        this.states.set(row.chatId, state);
      } else { state.update(row); }
      next.push(state);
    }
    this.states.forEach((_state: TargetRowState, id: number): void => {
      if (!live.has(id)) { this.states.delete(id); }
    });
    const ids: string[] = next.map((state: TargetRowState): string => `${state.id}`);
    this.data.update(next, ids, ids);
  }
  build() {
    Grid() {
      LazyForEach(this.data, (target: TargetRowState): void => {
        GridItem() {
          TargetRowCell({ target, selected: this.selectedIds.indexOf(target.id) >= 0,
            busy: this.busyId === target.id })
            .onClick((): void => { this.onToggle(target.id); });
        }
      }, (target: TargetRowState): string => `${target.id}`);
    }
    .columnsTemplate(forwardColumnsTemplate(forwardGridColumns(this.screenW - 40)))
    .rowsGap(4).columnsGap(4).width('100%').height('100%')
    .cachedCount(2).scrollBar(BarState.Auto).onReachEnd((): void => { this.onMore(); });
  }
}
