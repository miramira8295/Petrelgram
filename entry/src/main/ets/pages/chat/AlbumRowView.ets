import { AlbumCell } from '../../util/packAlbumRows';
import { AlbumGroup } from '../../util/collapseAlbums';
import { AlbumCellView, AlbumCellHooks } from './AlbumCellView';
import { MessageBubbleRenderData, MessageBubbleActions } from './ReusableMessageBubble';

// 相册里的一行（2026-09-20）。
//
// 【为什么要有这一层】原来 MessageBubble.albumGrid 是 6 行 × 3 格的固定槽位，
// 每一级都包着 `if`：
//
//     if (this.albumRows().length > r) { Row() {
//       if (this.albumRows()[r].length > c) { AlbumCellView({ ... }) }
//     } }
//
// 行复用时 ArkUI 会对**已经存在的**子组件重跑 paramsLambda 把新参数推进去，
// 却**不会**重新求值这些 `if`（同一条机制在 2026-09-20 早上造成过线上第一崩，
// 见 util/packAlbumRows 的注释）。于是一个画三行相册的气泡被复用去画一张图的
// 消息时，残留的行和格子还在：格子拿到越界的哨兵 0×0，看不见，但
// `Row/Column` 的 `space: 2` 照样给它留位——相册的高宽因此抖一下，
// 就是用户报的「相册消息闪动」（普通消息结构固定，所以一点事没有）。
//
// 【为什么挪进组件就对了】`if` 失效只发生在**跨组件边界的那一次复用推参**上。
// @Param 落地之后，本组件自己的 build() 是会完整重跑的，里面的 `if` 照常求值。
// 所以把"这一行/这一格存不存在"的判断放到这里，结构就能跟着数据走。
//
// 【为什么仍然不用 ForEach】理由与 albumGrid 原注释一致：ForEach 键值不变就
// 不重跑子构建函数，几何变了送不进去。这里每格仍是固定槽位，只是判据挪了位置。
//
// 【选中态为什么是三个布尔而不是一个数组】跨组件边界只传基本类型：数组每帧都是
// 新引用，白白触发比较；而 @Param 的深拷贝对数组也更贵。三格写死，够用。
@ComponentV2
export struct AlbumRowView {
  @Require @Param cells: AlbumCell[];
  @Require @Param group: AlbumGroup;
  @Require @Param data: MessageBubbleRenderData;
  @Require @Param actions: MessageBubbleActions;
  @Require @Param hooks: AlbumCellHooks;
  @Param selectionActive: boolean = false;
  @Param sel0: boolean = false;
  @Param sel1: boolean = false;
  @Param sel2: boolean = false;

  build() {
    // 空行整个不画——不是画一个 0 高的 Row。后者会吃掉外层 Column 的一档 space。
    if (this.cells.length > 0) {
      Row({ space: 2 }) {
        if (this.cells.length > 0) {
          AlbumCellView({
            cell: this.cells[0],
            group: this.group,
            data: this.data,
            actions: this.actions,
            hooks: this.hooks,
            selectionActive: this.selectionActive,
            selected: this.sel0
          });
        }
        if (this.cells.length > 1) {
          AlbumCellView({
            cell: this.cells[1],
            group: this.group,
            data: this.data,
            actions: this.actions,
            hooks: this.hooks,
            selectionActive: this.selectionActive,
            selected: this.sel1
          });
        }
        if (this.cells.length > 2) {
          AlbumCellView({
            cell: this.cells[2],
            group: this.group,
            data: this.data,
            actions: this.actions,
            hooks: this.hooks,
            selectionActive: this.selectionActive,
            selected: this.sel2
          });
        }
      }
    }
  }
}
