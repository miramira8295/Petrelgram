// 通知点击落在哪个账号上。
//
// 【问题】用户报：A 账号收到推送消息，切到 B 账号，再点系统通知栏那条推送会跳到
// 错误页面。原因是通知的 WantAgent 参数里只有 chat_id / message_id，**没有账号**
// （services/SystemNotificationPublisher）。点击时直接拿这个 chatId 去当前账号里
// 开会话——而这个 id 在 B 账号的库里要么不存在（空白/报错页），要么恰好是另一个
// 会话（更糟：打开了不相干的聊天）。
//
// 【判据】通知里带上发布时的槽位 id，点击时三选一。
export const NOTIFY_OPEN: string = 'open';      // 就是当前账号，直接开
export const NOTIFY_SWITCH: string = 'switch';  // 是另一个还在的账号，先切过去再开
export const NOTIFY_DROP: string = 'drop';      // 那个账号已经退掉了，丢弃

export function notifySlotAction(
  notifySlotId: string, activeSlotId: string, knownSlotIds: string[]
): string {
  // 升级之前发出的通知没有槽位信息：按当前账号打开，与改动前逐字一致。
  if (notifySlotId === '' || notifySlotId === activeSlotId) {
    return NOTIFY_OPEN;
  }
  return knownSlotIds.indexOf(notifySlotId) >= 0 ? NOTIFY_SWITCH : NOTIFY_DROP;
}
