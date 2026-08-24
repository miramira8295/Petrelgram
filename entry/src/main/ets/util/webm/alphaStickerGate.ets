// 哪些素材值得走透明贴纸这条自解码链路。
//
// **这里原本还有一条 API 版本门槛，已经拆掉。**
// 那条门槛写的是"系统 VP9 解码器是 API 23 才有的，低于这个版本一律走
// ijkplayer"——前提在解码器换成随包自带的 libvpx（third_party/libvpx-ohos）
// 之后就不成立了：现在设备有没有 VP9 与本功能无关，20 上和 26 上跑的是同一份
// 解码器。留着它只会把 API 20~22 的机器白白挡在门外，让它们继续用 ijkplayer
// 播出黑底的透明贴纸——而那正是这条链路要修的毛病。
//
// 拆掉之后运行期唯一的条件是原生模块加载成功，见 AlphaStickerStore 的
// nativeAvailable()。

// 带 alpha 的素材只有贴纸和各类表情。GIF、视频本来就不透明，让它们也去试一次
// 自解封装只是白花一次读文件 + 拆包。
export function alphaStickerCandidate(powerCategory: string): boolean {
  return powerCategory === 'sticker' || powerCategory === 'emojiChat'
    || powerCategory === 'emojiPicker' || powerCategory === 'emoji'
    || powerCategory === 'emojiReaction' || powerCategory === 'emojiStatus';
}
