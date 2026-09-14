// 消息行 prepare 用的页面级输入（第三刀，2026-09-14）。
//
// 【为什么】ChatPage.prepareMessageBubble 每一行都要读二十来个页面级状态拼 cacheKey，
// 每次读取都要登记一次依赖（stateMgmt 的 addRef4IdInternal），四个 @Local 数组还要在
// 代理上跑 indexOf（autoProxyObject）。13:52 profile 里 preparedMessageBubble 名下的
// 依赖登记 95.6ms/15s，animationPaused 等四个查询在代理上约 28ms/15s。
//
// 做法：ChatPage 用一个 @Computed 把这些状态读一次、交给这里算好（键片段 + 四个 Set），
// 每行只读这一个计算属性；值只在其中某个状态变了时重算。
//
// 【什么能放进来，什么不能】
//   · 必须是**状态**（@Local / @Param / @Trace）：普通字段（firstUnreadId、chatId、
//     messageListRevision……）变了不会让计算属性重算，放进来就会一直是旧值。
//   · 必须是**每行都无条件读**的：只有部分行才读的（nowSec 只有发出的消息/投票读，
//     playSlotStartMs 只有占着播放位的那一行读，messageListRevision 只有音频行读）
//     放进来，会让它一变就把所有行一起拖着重跑。
//   · 由**页面状态本身**决定读不读的可以放（例如通话进行中才读 liveGroupCallId）：
//     计算属性的依赖按实际读到的登记，条件翻转时依赖跟着变。

export interface RowPageInputsSource {
  isGroup: boolean;
  isChannel: boolean;
  translationActive: boolean;
  editingActive: boolean;
  liveCallActive: boolean;
  liveGroupCallId: number;
  liveLocationMessageId: number;
  autoplayMuted: boolean;
  appearanceEpoch: number;
  materialEpoch: number;
  appDark: boolean;
  selectionActive: boolean;
  chatContentWidth: number;
  canReply: boolean;
  playSlotKey: string;
  freshSinceId: number;
  pausedAnimationIds: number[];
  forcedAnimationIds: number[];
  failedAnimationIds: number[];
  paidMediaPendingIds: number[];
}

export interface RowPageInputs {
  // 页面级 cacheKey 片段，接在行级片段后面。
  keyPart: string;
  isGroup: boolean;
  isChannel: boolean;
  translationActive: boolean;
  editingActive: boolean;
  liveCallActive: boolean;
  liveGroupCallId: number;
  liveLocationMessageId: number;
  autoplayMuted: boolean;
  selectionActive: boolean;
  chatContentWidth: number;
  canReply: boolean;
  playSlotKey: string;
  freshSinceId: number;
  pausedIds: Set<number>;
  forcedIds: Set<number>;
  failedIds: Set<number>;
  paidMediaPendingIds: Set<number>;
}

function bit(v: boolean): string {
  return v ? '1' : '0';
}

// 页面级 cacheKey 片段。取值与改造前逐段相同（布尔一律 0/1），只是从行级片段中间
// 挪到了末尾；各段前缀固定、顺序固定，拼出来的键仍然一一对应。
export function rowPageKeyPart(src: RowPageInputsSource): string {
  return `|g${bit(src.isGroup)}${bit(src.isChannel)}` +
    `|tr${bit(src.translationActive)}` +
    `|edit${bit(src.editingActive)}` +
    `|live${src.liveLocationMessageId}|call${src.liveGroupCallId}` +
    `|mute${bit(src.autoplayMuted)}` +
    `|appearance${src.appearanceEpoch}|material${src.materialEpoch}|dark${bit(src.appDark)}` +
    `|select${bit(src.selectionActive)}` +
    `|reply${bit(src.canReply)}`;
}

export function buildRowPageInputs(src: RowPageInputsSource): RowPageInputs {
  return {
    keyPart: rowPageKeyPart(src),
    isGroup: src.isGroup,
    isChannel: src.isChannel,
    translationActive: src.translationActive,
    editingActive: src.editingActive,
    liveCallActive: src.liveCallActive,
    liveGroupCallId: src.liveGroupCallId,
    liveLocationMessageId: src.liveLocationMessageId,
    autoplayMuted: src.autoplayMuted,
    selectionActive: src.selectionActive,
    chatContentWidth: src.chatContentWidth,
    canReply: src.canReply,
    playSlotKey: src.playSlotKey,
    freshSinceId: src.freshSinceId,
    pausedIds: new Set<number>(src.pausedAnimationIds),
    forcedIds: new Set<number>(src.forcedAnimationIds),
    failedIds: new Set<number>(src.failedAnimationIds),
    paidMediaPendingIds: new Set<number>(src.paidMediaPendingIds)
  };
}
