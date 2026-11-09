// 「解码完成前先画 TDLib 内联的那张小图」这条路的两个常量与开关。
//
// 【它是什么】TDLib 在 photo / video / animation 的 JSON 里内联一张
// minithumbnail：约 40px 的 JPEG，base64，**跟消息正文一起到，不用下载、不排
// 解码队列**。真缩略图是个独立文件，要走 downloadFile 排队再解码，图多的会话里
// 排在几十张之后——那段等待就是用户看到的空窗（2026-09-21 真机：blank=559 /
// hit=462，且 reblank=0，也就是**全部是第一次加载**，正好是这条路的适用范围）。
//
// 【它不减少任何等待】只是把等待期间画的东西从灰块换成图本身。治的是"看得见的
// 空窗"，不是性能。
//
// 【已经在用的地方】首页列表行（formatPreview.previewThumbOf，issue #202）、
// 音乐气泡的专辑封面（musicTrackModel）。消息气泡的图片格和相册格是这次才接上的。

// 一键回退。相册一行 6–9 格，每格多一个 Image 节点——首页当初就为同一个理由
// 留了 CHATLIST_PREVIEW_THUMB_ENABLED（见记忆 chatlist-jank-root-cause：
// 首页对每行多一个节点敏感）。上机不理想就把这里改 false，不用回滚代码。
export const MINI_THUMB_PLACEHOLDER_ENABLED: boolean = true;

// 小图的模糊半径（vp）。
//
// 40px 拉到几百 px 必然是马赛克。叠一层模糊让它读起来像"正在变清晰"而不是
// "画糊了"——官方客户端也是这个做法。太小盖不住方块，太大就成一团色雾、
// 失去"这张图大概长什么样"的信息量。
export const MINI_PLACEHOLDER_BLUR: number = 12;

// 调用方统一走这里，别在各处写 `ENABLED ? url : ''`——漏一处就出现"有的格子
// 有占位有的没有"，比全都没有更难看。
export function miniPlaceholderOf(dataUrl: string): string {
  return MINI_THUMB_PLACEHOLDER_ENABLED ? dataUrl : '';
}
