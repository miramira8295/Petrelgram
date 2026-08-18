// 音频队列参数只对音频气泡有意义（见 MessageBubble 的 contentType === 'audio'
// 分支）。把这个判定单独拿出来，是因为它在 ChatPage 的列表 item builder 里
// 承担了一个远比"少算几个数"重要的职责：
//
// 那四个参数要读整个 messages 数组。ArkUI 按"build 期实际读取"记录状态依赖，
// 所以无条件地算它们，会让**每一条消息行**的 build 都依赖整个 messages
// @State。于是 store 每 notify 一次（哪怕只是某张图的下载进度动了一下），
// 所有可见行都要重跑 build、拿到新的 MessageEntry、触发整行重建。
//
// 实测：notify 约 10 次/秒时 rebuild 约 140 次/秒，两者比值就是可见行数；
// notify 为 0 的那些秒 rebuild 恰好也是 0。
//
// 因此调用点必须写成三元短路，让非音频行完全不碰 messages。不要"化简"掉。
export function audioQueueApplies(contentType: string): boolean {
  return contentType === 'audio';
}
