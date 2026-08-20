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
}

export function membershipStateOf(input: MemberStatusInput): string {
  if (input.statusType === 'chatMemberStatusLeft') {
    return MEMBERSHIP_JOINABLE;
  }
  if (input.statusType === 'chatMemberStatusRestricted') {
    // 被限制**但仍在群里**照样能发言——限制的是权限细项，不是在场与否。
    // 判反的话，一个只是被禁发图片的人会看到"加入"按钮。
    return input.isMember ? MEMBERSHIP_WRITABLE : MEMBERSHIP_JOINABLE;
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
  // 其余（创建者、超级群普通成员、私聊、密聊、拿不到状态）一律放行。
  // 兜底选 writable 而不是 blocked 是有意的：状态查不到时把输入框藏起来，
  // 用户就彻底没救了；放行最多是发送时报错。
  return MEMBERSHIP_WRITABLE;
}

// 失去发言权时要把输入区连带的东西全清掉（草稿条、补全面板、录音…）。
// 只有 writable 不需要。
export function membershipLosesComposer(state: string): boolean {
  return state !== MEMBERSHIP_WRITABLE;
}
