// 发送者名字行宽度的进程级记忆，**按发送者可观测**。
//
// 【为什么不是每行一个 @Local】V2 的 @Local 在 aboutToReuse 时被框架重置回初值：
// 名字宽度每复用一行就是「0（重置）+ 实测值（回填）」两次通知。2026-11-06 的
// 采集里 senderLabelW 变了 1185 次，其中 603 次是 0——全是这条链路，不是我们
// 主动写的脏数据。
//
// 【为什么不是一张大表】如果把整张表做成一个 @Trace，任何一次写入都会让**所有**
// 正在显示名字的行重算（版本号式依赖）。这里按发送者拆成独立单元：行只读自己
// 那个单元的 width，写入只唤醒同一个发送者的行。
//
// 单元在首次读取时惰性创建——创建发生在 build 里，但写的是普通 Map，不产生通知。
// 发送者数量有上限，超出按 FIFO 淘汰，防止长期运行涨表。
@ObservedV2
export class SenderLabelCell {
  @Trace width: number = 0;
}

const LIMIT: number = 512;

export class SenderLabelWidths {
  private cells: Map<string, SenderLabelCell> = new Map<string, SenderLabelCell>();

  // 读：没有就是 0（未测量），这是合法状态，不再需要"播种"。
  cell(name: string): SenderLabelCell {
    let cell: SenderLabelCell | undefined = this.cells.get(name);
    if (cell === undefined) {
      cell = new SenderLabelCell();
      this.cells.set(name, cell);
      if (this.cells.size > LIMIT) {
        const oldest: string | undefined = this.cells.keys().next().value as string | undefined;
        if (oldest !== undefined && oldest !== name) {
          this.cells.delete(oldest);
        }
      }
    }
    return cell;
  }

  widthOf(name: string): number {
    const cell: SenderLabelCell | undefined = this.cells.get(name);
    // 没有单元时也返回 0；此时不读任何 @Trace，行不会因此建立依赖——
    // 等第一次写入创建单元后，行会在下一次复用/刷新时读到它。
    return cell !== undefined ? cell.width : 0;
  }

  // 写：同值不写。只有真的变了才唤醒读过这个单元的行。
  remember(name: string, width: number): void {
    if (name === '' || !(width > 0)) {
      return;
    }
    const cell: SenderLabelCell = this.cell(name);
    if (cell.width !== width) {
      cell.width = width;
    }
  }
}

export const senderLabelWidths: SenderLabelWidths = new SenderLabelWidths();
