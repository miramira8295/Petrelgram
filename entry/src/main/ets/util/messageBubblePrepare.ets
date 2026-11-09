// prepareMessageBubble 用到的两个「形状计算」纯函数。
//
// 【为什么单独成文件】这两个函数在消息行渲染的热路径上：时间线的每一行、每次
// build 都会各调一次。它们本身无状态——给定 AlbumGroup 与当前的全局播放位，
// 结果唯一确定——但它们决定的是行复用 id 与行缓存键的一部分，写错一个字符就
// 会表现成「整屏气泡一起重渲染」或「换了媒体的格子不重建」这类只能靠真机
// Frame 录制才发现的回归。搬出来配单测钉住，是为了让下一次「顺手简化」撞在
// 测试上而不是撞在用户身上。
//
// 【调用约定】一律用位置参数，不接对象字面量——每行每帧一次调用，多一个对象
// 字面量就是每帧几十次分配。函数体内也不新建数组/对象/闭包，不打任何日志。
//
// 页面侧保留薄包装（读 this.playSlotKey → 调这里 → 交给 prepareMessageBubble），
// prepareMessageBubble 的 cacheKey 拼法与 timelineRow / preparedMessageBubble
// 一概不动。

import { AlbumGroup } from './collapseAlbums';
import { slotKey, slotKeyMessageId } from '../pages/chat/playSlot';

// 相册行的复用形状串：张数 + 每一格的「视频/图片、缩略图落地没落地、有没有可下
// 载的封面文件、失败没失败、是不是当前播放位」+ **长宽比档**。进的是行复用 id，
// 所以只放会改变子树形状的位，不放下载进度这种走旁路通道的高频量。
//
// 【为什么要带长宽比 —— 2026-09-20 真机定位】格子的宽高是
// packAlbumRows(photoRatios, width) 算出来、**显式写在 .width()/.height() 上**的。
// 原来这个串里没有任何几何信息，于是两个都是 6 张、但长宽比不同的相册落进同一个
// 复用池；复用推参把活着的格子从 84x130 换成 91x140，Image 重新布局重绘——
// 用户看到的就是「相册消息闪一下」（#137/#140 的同一面）。
//
// 探针实测（17:44 那一轮）：destroyed=0、[Decode]=0，但 resized=27。
// 也就是说节点没被销毁、位图一直在缓存里，闪的**只能**是这个尺寸切换。
//
// 量化到 0.1：太细会把池子打散成「一个相册一个桶」，那比不复用还慢（见本文件
// 与 rowReuseId 抬头的警告）；太粗又分不开 84x130 和 91x140 这种真实差异。
// 0.1 这一档下，同一套 Telegram 马赛克预设的相册仍然共池。
export function albumReuseShape(g: AlbumGroup, playSlotKey: string): string {
  let shape: string = `${g.photoPaths.length}`;
  for (let i = 0; i < g.photoPaths.length; i++) {
    const memberId: number = g.memberIds[i] ?? 0;
    const ratio: number = g.photoRatios[i] ?? 0;
    shape += `:${g.photoIsVideo[i] ? 'v' : 'p'}` +
      `${g.photoPaths[i] !== '' ? 'r' : 'n'}${g.photoFileIds[i] !== 0 ? 'f' : 'z'}` +
      `${g.photoFailed[i] ? 'e' : 'o'}${playSlotKey === slotKey(memberId, i) ? 's' : 'i'}` +
      `${Math.round(ratio * 10)}`;
  }
  return shape;
}

// 这一行**自己**的播放位。不是本行拥有播放位时一律返回空串。
//
// 【为什么必须行局部化】播放位是全局单值，而 prepareMessageBubble 的缓存键
// 里原来放的是它的原值——于是播放位一变，整屏每一行的键同时变，缓存全作废，
// 每行都拿到一个新的 data 对象、每个气泡都重渲染一次。09-03 的 Frame 录制
// 里，每次向上翻页之后 100–250ms 内 15–33 个气泡同时更新（正常滚动是 1–3
// 个），就是这么来的：翻页 → driveVisibleWork → armPlaySlotSettle → 重新
// 竞选播放位 → 全屏作废。
//
// 气泡侧从来只拿它和**自己的**成员 id 比（MessageBubble.isPlaySlot /
// isAlbumCellPlaySlot），所以对不拥有播放位的行传空串与传原值完全等价。
export function rowPlaySlotKey(g: AlbumGroup, playSlotKey: string): string {
  if (playSlotKey === '') {
    return '';
  }
  return g.memberIds.indexOf(slotKeyMessageId(playSlotKey)) >= 0
    ? playSlotKey : '';
}
