// 机器人会话的「开始」按钮：要不要把输入框那块位置让给它。
//
// 官方端的规则是"私聊对象是机器人、且这个会话你还没开始过"。TDLib 没有
// "已开始"这个字段，官方端自己也是拿**历史为空**当判据：/start 一发，第一条
// 消息就落进历史，按钮自然消失，不需要额外的状态同步。
//
// 抽成纯函数是因为几个边界很容易搞错：还在加载时不能先亮出按钮（历史马上就
// 到，按钮会闪一下），话题视图里不该有，没有发言权时更不该有（那时该显示的
// 是"加入"或"无法加入"）。

export const MEMBERSHIP_BOT_START: string = 'botStart';
export const BOT_START_COMMAND: string = '/start';

export interface BotStartInput {
  // 私聊对方是 userTypeBot。
  isBot: boolean;
  // util/membershipState 的取值。
  membershipState: string;
  // 'loading' | 'ready' | 'error'
  loadState: string;
  // 当前窗口里的可见行数。
  visibleGroupCount: number;
  // 话题（评论区）视图的根消息，0 表示不是话题。
  threadRootId: number;
}

export function shouldOfferBotStart(input: BotStartInput): boolean {
  if (!input.isBot || input.threadRootId > 0) {
    return false;
  }
  // 没有发言权时那块位置另有归属（加入 / 无法加入 / 只读），别抢。
  if (input.membershipState !== 'writable') {
    return false;
  }
  // 只在**确认**历史为空时才让位。loading 期间空只是还没到货，先亮按钮会闪。
  return input.loadState === 'ready' && input.visibleGroupCount === 0;
}

// 那块位置最终显示什么：机器人开始优先，其余交回成员状态。
export function composerSlotState(input: BotStartInput): string {
  return shouldOfferBotStart(input) ? MEMBERSHIP_BOT_START : input.membershipState;
}
