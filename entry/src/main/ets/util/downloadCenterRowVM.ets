import { DcRow, dcRowId, dcRowLayout } from './downloadCenterRows';
import { downloadCenterItemId } from './downloadCenterModel';

// 下载中心一行的可观察模型（2026-09-15 第四版：行组件复用）。
// 每个页签按行身份各留一份，刷新时原地改字段：进度、速度、勾选这些变化经 @Trace 只刷用到它的节点，不整行重建。
// 身份和布局构造时定下、不观察——布局变了（进行中 → 已完成）直接换一个新对象，key 跟着变。
// 只在值真的变了才写，速度按 KB/s 取整再写，免得每个字节都刷一次。

const SPEED_STEP: number = 1024;

@ObservedV2
export class DcRowVM {
  readonly rowId: string;
  readonly layout: string;
  @Trace section: string = '';
  @Trace count: number = 0;
  @Trace anyDownloading: boolean = false;
  @Trace sort: string = '';
  @Trace first: boolean = false;
  @Trace last: boolean = false;
  @Trace selected: boolean = false;
  @Trace groupCount: number = 0;
  @Trace groupBytes: number = 0;
  @Trace expanded: boolean = false;
  @Trace itemId: string = '';
  @Trace path: string = '';
  @Trace name: string = '';
  @Trace kind: string = '';
  @Trace state: string = '';
  @Trace sizeBytes: number = 0;
  @Trace downloaded: number = 0;
  @Trace speed: number = 0;
  @Trace session: string = '';
  @Trace mtime: number = 0;
  @Trace savedLocal: boolean = false;
  @Trace canJump: boolean = false;

  constructor(rowId: string, layout: string) {
    this.rowId = rowId;
    this.layout = layout;
  }

  static of(r: DcRow): DcRowVM {
    const vm: DcRowVM = new DcRowVM(dcRowId(r), dcRowLayout(r));
    vm.apply(r);
    return vm;
  }

  apply(r: DcRow): void {
    if (this.section !== r.section) {
      this.section = r.section;
    }
    if (this.count !== r.count) {
      this.count = r.count;
    }
    if (this.anyDownloading !== r.anyDownloading) {
      this.anyDownloading = r.anyDownloading;
    }
    if (this.sort !== r.sort) {
      this.sort = r.sort;
    }
    if (this.first !== r.first) {
      this.first = r.first;
    }
    if (this.last !== r.last) {
      this.last = r.last;
    }
    if (this.selected !== r.selected) {
      this.selected = r.selected;
    }
    if (this.groupCount !== r.groupCount) {
      this.groupCount = r.groupCount;
    }
    if (this.groupBytes !== r.groupBytes) {
      this.groupBytes = r.groupBytes;
    }
    if (this.expanded !== r.expanded) {
      this.expanded = r.expanded;
    }
    const it = r.item;
    if (it === null) {
      return;
    }
    const itemId: string = downloadCenterItemId(it);
    if (this.itemId !== itemId) {
      this.itemId = itemId;
    }
    if (this.path !== it.path) {
      this.path = it.path;
    }
    if (this.name !== it.name) {
      this.name = it.name;
    }
    if (this.kind !== it.kind) {
      this.kind = it.kind;
    }
    if (this.state !== it.state) {
      this.state = it.state;
    }
    if (this.sizeBytes !== it.size) {
      this.sizeBytes = it.size;
    }
    if (this.downloaded !== it.downloaded) {
      this.downloaded = it.downloaded;
    }
    const speed: number = Math.round(it.speed / SPEED_STEP) * SPEED_STEP;
    if (this.speed !== speed) {
      this.speed = speed;
    }
    if (this.session !== it.session) {
      this.session = it.session;
    }
    if (this.mtime !== it.mtime) {
      this.mtime = it.mtime;
    }
    if (this.savedLocal !== it.savedLocal) {
      this.savedLocal = it.savedLocal;
    }
    const canJump: boolean = it.chatId !== 0 && it.messageId !== 0;
    if (this.canJump !== canJump) {
      this.canJump = canJump;
    }
  }
}
