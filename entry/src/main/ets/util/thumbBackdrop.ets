// 缩略图在**位图解出来之前**垫的那层底色。
//
// 【为什么需要它 —— 2026-09-20 真机定位】LiveThumbImage 的 build 是个 if/else：
//     路径为空 → 画调用方的占位（灰底 + 进度环）
//     路径到手 → 画 CachedImage
// 而 CachedImage 在解码完成前是 `Image(undefined)`，**什么都不画**。于是文件下好
// 的那一刻占位被整个撤掉、位图还没解出来，格子先变透明再出图——灰 → 透明 → 图，
// 中间那下透明就是用户报的"相册图片闪一下"。
//
// 真机读数把这条钉死了：空帧 508 次里 reblank=0，也就是**没有一次是"解过又被挤掉"**，
// 全部是第一次解码的那段窗口；而 CachedImage 的注释写着"调用方已经在下面垫了自己
// 的加载态"——LiveThumbImage 恰恰没垫，它给的 onReady（issue #90 专为此留）也没接。
//
// 【为什么是底色而不是把占位叠在下面】占位里有 LiveProgressRing，它按 fileId
// 订阅下载通道。一行相册 6–9 格，全叠上去就是 6–9 份多余订阅 + 6–9 个多余节点，
// 而这一层要的只是"别透出去"。底色是 Image 自己的一个属性，零新增节点。
//
// 【两个取值的来历】和 AlbumCellView.placeholderWithFile /
// MessageBubble.singleMediaPlaceholder 里原本各写一遍的字面量一致——搬到这里是为了
// 让"占位色"与"解码前的底色"永远同一个值：两者不一致就会在撤占位的那一帧看到跳色，
// 正是这次要消掉的现象。

// 视频缩略图偏冷灰：它上面还要叠白色播放钮，底色太浅会看不清。
const THUMB_BACKDROP_VIDEO: string = '#AEB6C0';
// 照片用更浅的灰，接近多数缩略图的平均亮度，出图时的明度跳变最小。
const THUMB_BACKDROP_PHOTO: string = '#D7DCE2';

export function thumbBackdropColor(isVideo: boolean): string {
  return isVideo ? THUMB_BACKDROP_VIDEO : THUMB_BACKDROP_PHOTO;
}
