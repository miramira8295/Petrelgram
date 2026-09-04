// 引用块（气泡里那一小条 + 输入栏回复条）左侧那张缩略图。
//
// 【为什么只看 photoPath 一个字段】贴纸、图片、视频封面、GIF 封面在
// MessageEntry 里用的是**同一个** photoPath：
//   · 图片    —— 内联尺寸的那张
//   · 视频/GIF —— 封面（formatMsgContent 把 thumbnail 落到 photoLocalPath）
//   · 贴纸    —— 它自己的位图（webp 取源文件，动图取缩略图，见 stickerMsgContent）
// 所以判据不是「按类型列举」，而是「这条消息有没有可画的位图」。列举法每加
// 一种新内容类型都得记得来这里补一笔，漏了就是没有缩略图；看 photoPath 则是
// 有就显示、没有就不显示，天然覆盖以后新增的类型。
//
// 【付费媒体没解锁时一律不给】那张封面就是要花钱才能看的东西，引用块把它
// 露出来等于白送。

export interface ReplyThumbInput {
  contentType: string;
  photoPath: string;
  paidMediaLocked: boolean;
}

// 返回缩略图的本地路径；空串表示这条消息没有可画的图。
export function replyThumbOf(m: ReplyThumbInput): string {
  if (m.contentType === 'paidMedia' && m.paidMediaLocked) {
    return '';
  }
  return m.photoPath.trim();
}

// 贴纸要 Contain + 透明底：它本来就是不规则形状、四周留白，按 Cover 裁成方块
// 会把主体切掉。图片和视频封面反过来，Cover 铺满那个小方块才好看。
export function replyThumbIsSticker(contentType: string): boolean {
  return contentType === 'sticker';
}

// 本地绝对路径要加 file:// 才喂得进 Image；已经是 URL 的原样返回。
// 和气泡里其它几处贴图的写法保持一致（`path.startsWith('/') ? file://... : path`）。
export function replyThumbSrc(path: string): string {
  return path.startsWith('/') ? `file://${path}` : path;
}
