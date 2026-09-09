// 我在这个会话里能做什么：正常发言、需要先加入、被挡在外面、还是只能看。
//
// 判定来自 TDLib 的 ChatMemberStatus，规则有几处反直觉，写在各自分支上。
// 抽出来是因为错了很隐蔽：判反一处，用户要么对着一个发不出去的输入框打字，
// 要么明明能发言却只看到一个"加入"按钮。

export const MEMBERSHIP_WRITABLE: string = 'writable';   // 正常输入区
export const MEMBERSHIP_JOINABLE: string = 'joinable';   // 显示"加入"
export const MEMBERSHIP_BLOCKED: string = 'blocked';     // 显示"无法加入"
export const MEMBERSHIP_READONLY: string = 'readonly';   // 只读，位置让给静音开关
export const MEMBERSHIP_CHECKING: string = 'checking';   // 补充请求在途

export interface MemberStatusInput {
  // ChatMemberStatus 的 @type，取不到时为空串。
  statusType: string;
  // chatMemberStatusRestricted 才有意义：被限制但仍在群里。
  isMember: boolean;
  // 广播频道（而非超级群）。
  isChannel: boolean;
  // chatMemberStatusAdministrator 的 rights.can_post_messages。
  canPostMessages: boolean;
  // chat.permissions.can_send_basic_messages —— **群的默认权限**，管的是普通
  // 成员。"只有管理员能发言"的锁群就是把它设成 false。字段缺失时调用方传 true
  // （兜底放行，与本文件其余兜底方向一致）。
  chatCanSendBasic: boolean;
  // chatMemberStatusRestricted 自己那份 permissions.can_send_basic_messages。
  // 被禁言的人看这个，不看群默认的：群里别人能说话不代表他能。
  restrictedCanSendBasic: boolean;
}

export function membershipStateOf(input: MemberStatusInput): string {
  if (input.statusType === 'chatMemberStatusLeft') {
    return MEMBERSHIP_JOINABLE;
  }
  if (input.statusType === 'chatMemberStatusRestricted') {
    // 被限制**但仍在群里**不等于不在场——限制的是权限细项。判反的话，一个
    // 只是被禁发图片的人会看到"加入"按钮。
    if (!input.isMember) {
      return MEMBERSHIP_JOINABLE;
    }
    // 但**在场也不等于能说话**：细项里就有 can_send_basic_messages。
    // 原来这一支无条件放行，被禁言的人对着一个发不出去的输入框打字。
    return input.restrictedCanSendBasic ? MEMBERSHIP_WRITABLE : MEMBERSHIP_READONLY;
  }
  if (input.statusType === 'chatMemberStatusBanned') {
    return MEMBERSHIP_BLOCKED;
  }
  if (input.isChannel && input.statusType === 'chatMemberStatusMember') {
    // 广播频道的订阅者永远不能发帖，只有创建者和有发帖权的管理员可以。
    // 这一条只对频道成立：超级群的普通成员当然能发言。
    return MEMBERSHIP_READONLY;
  }
  if (input.isChannel && input.statusType === 'chatMemberStatusAdministrator') {
    // 频道管理员不等于能发帖——权限是逐项授予的。
    return input.canPostMessages ? MEMBERSHIP_WRITABLE : MEMBERSHIP_READONLY;
  }
  // 超级群/基础群的普通成员：**还要看群的默认权限**。
  //
  // 「不能聊天但是显示聊天输入框」（用户 2026-09-09，从首页进的会话）就出在
  // 这里——判据原来只看 ChatMemberStatus，从来没看过 chat.permissions，于是
  // "只有管理员能发言"的锁群里普通成员一路判成 writable，输入框照出，打完字
  // 发送才被 TDLib 驳回（真机日志：Need administrator rights in the channel
  // chat；MTProto 里超级群本身就叫 channel，这句不代表是广播频道）。
  //
  // 创建者和管理员不走这一支：锁群本来就是给他们用的，群默认权限不约束他们。
  if (input.statusType === 'chatMemberStatusMember' && !input.chatCanSendBasic) {
    return MEMBERSHIP_READONLY;
  }
  // 其余（创建者、管理员、能发言的普通成员、私聊、密聊、拿不到状态）一律放行。
  // 兜底选 writable 而不是 blocked 是有意的：状态查不到时把输入框藏起来，
  // 用户就彻底没救了；放行最多是发送时报错。
  return MEMBERSHIP_WRITABLE;
}

// 失去发言权时要把输入区连带的东西全清掉（草稿条、补全面板、录音…）。
// 只有 writable 不需要。
export function membershipLosesComposer(state: string): boolean {
  return state !== MEMBERSHIP_WRITABLE;
}

