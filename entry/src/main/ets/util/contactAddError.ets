// 「加联系人失败」的错误归类。纯函数，没有 kit 依赖，单测直接跑。
//
// 【为什么需要单独一个文件】用户 2026-10-30 报：「联系人 → 新建联系人 → 添加
// 联系人，提示无法添加联系人，请重试」。查下来提示语本身是兜底那一句，而三条
// 特判里有两条**永远不可能命中**：
//
//   · TDLib 的错误文案分两个来源，形状完全不同：
//       服务端（MTProto）→ UPPER_SNAKE，如 PHONE_NUMBER_INVALID、
//                         PHONE_NUMBER_UNOCCUPIED、FLOOD_WAIT_12
//       客户端（TDLib 自己判的）→ 带空格的英文句子，如 "User not found"、
//                         "Phone number is invalid"
//   · 原来的三条特判全写下划线（USER_NOT_FOUND / PHONE_NUMBER_NOT_OCCUPIED），
//     客户端那几种一次都认不出来；
//   · 其中 PHONE_NUMBER_NOT_OCCUPIED 这个名字干脆是错的——MTProto 里叫
//     PHONE_NUMBER_UNOCCUPIED。
//
// 结果是：哪怕错误就是 ProfilePage 注释里写明的「400 User not found」，用户
// 看到的也是「添加联系人失败，请稍后重试」——像是网络抖了一下，其实重试多少次
// 都一样。所以这里两种写法都认。

// 号码本身不合法（格式 / 被服务端拒收）。
export const CONTACT_ERR_BAD_PHONE: string = 'bad_phone';
// 这个号码背后没有 Telegram 用户。
export const CONTACT_ERR_NO_USER: string = 'no_user';
// 网络 / 超时 / 频率限制：换条路径再打一次也不会更好。
export const CONTACT_ERR_NETWORK: string = 'network';
// 没认出来的错误。
export const CONTACT_ERR_OTHER: string = 'other';

export function contactAddErrorKind(message: string): string {
  const text: string = message.toUpperCase();
  if (text.includes('PHONE_NUMBER_INVALID') ||
    text.includes('PHONE NUMBER IS INVALID') ||
    text.includes('INVALID PHONE NUMBER') ||
    text.includes('INVALID TARGET PHONE NUMBER') ||
    text.includes('WRONG PHONE NUMBER') ||
    text.includes('MUST CONTAIN A VALID PHONE NUMBER') ||
    text.includes('PHONE NUMBER MUST BE')) {
    return CONTACT_ERR_BAD_PHONE;
  }
  if (text.includes('PHONE_NUMBER_UNOCCUPIED') ||
    // 旧写法，留着兼容：这个错误码本来就叫错了名字。
    text.includes('PHONE_NUMBER_NOT_OCCUPIED') ||
    text.includes('PHONE NUMBER IS NOT OCCUPIED') ||
    text.includes('PHONE NUMBER IS UNOCCUPIED') ||
    text.includes('USER_NOT_FOUND') ||
    text.includes('USER NOT FOUND')) {
    return CONTACT_ERR_NO_USER;
  }
  if (text.includes('NETWORK') || text.includes('TIMEOUT') ||
    text.includes('CONNECTION') || text.includes('FLOOD')) {
    return CONTACT_ERR_NETWORK;
  }
  return CONTACT_ERR_OTHER;
}

// 这一步失败之后值不值得再换一条路试。
//
// 「查不到这个人」值得——下一步正是按号码把人找回来，或者交给服务器导入；
// 没认出来的错误也值得（多半也是"人没找着"的变体）。号码不合法和网络问题
// 不值得：同样的号码 / 同样断着的网，换哪条路都一样失败，白白让用户多等两轮。
export function contactErrorRecoverable(kind: string): boolean {
  return kind === CONTACT_ERR_NO_USER || kind === CONTACT_ERR_OTHER;
}
