// 登录错误该不该原样给用户看。
//
// PhoneNumberPage 原本是 `this.errorText = caught.message`，注释写着"让 TDLib
// 给出真实原因，而不是我们编一个"。这条原则对**服务端**错误是对的：
// PHONE_NUMBER_INVALID / PHONE_NUMBER_BANNED / FLOOD_WAIT_86400 都是用户能据此
// 行动的（换号码、去官方客户端解封、等一等），我们替换成"请稍后重试"反而把
// 信息删掉了。
//
// 但 TDLib 还有另一类消息：**它在抱怨自己的授权状态机对不上**，形如
// "Call to setAuthenticationPhoneNumber unexpected"。这类消息
//   · 是英文的，不随应用语言变；
//   · 说的是内部方法名，用户看不懂；
//   · 也没有任何可操作性——不是用户做错了什么。
// 手机模拟器上这两条能稳定复现（2026-08-22）：冷启动点扫码、以及扫码态下提交
// 手机号，两次都把这串英文原样糊在输入框下面。
//
// 所以判定收在这里，两边各得其所。

// 为什么匹配"Call to ... unexpected"这个完整形状，而不是裸的 indexOf('unexpected')：
// 后者会误伤任何含这个词的服务端错误。Telegram 现有的错误码全是大写下划线常量
// （UNEXPECTED_SERVER_RESPONSE 这类命名是存在的），裸匹配等于给未来埋一颗雷。
const INTERNAL_PREFIX: string = 'call to';
const INTERNAL_SUFFIX: string = 'unexpected';

// 这条消息是不是 TDLib 的内部状态抱怨——是则不该给用户看。
//
// 大小写和前后空白都归一化：TDLib 各版本的措辞有过出入，判定不该被这些细节
// 影响。空串返回 false，否则"没有错误"会被显示成一句提示。
export function isInternalAuthError(raw: string): boolean {
  const text: string = `${raw}`.trim().toLowerCase();
  if (text === '') {
    return false;
  }
  if (!text.startsWith(INTERNAL_PREFIX)) {
    return false;
  }
  return text.endsWith(INTERNAL_SUFFIX);
}

// TDLib 的扫码授权态字符串。与 AuthService 里的同名常量同值——这里再写一份是
// 为了让判定保持纯函数（不 import AuthService，否则单测要拖进整个 TdClient）。
export const QR_CONFIRMATION_STATE: string = 'authorizationStateWaitOtherDeviceConfirmation';

// 要不要清掉本地授权数据重来。
//
// **背景**：扫码授权态是持久化的。用户点过一次扫码登录，TDLib 就把
// authorizationStateWaitOtherDeviceConfirmation 写进 td.binlog；之后每次冷启动都
// 从 binlog 恢复成扫码态，**跳过 WaitPhoneNumber**，而 setAuthenticationPhoneNumber
// 只在 WaitPhoneNumber 下被接受，于是被永久拒绝——用户从此再也用不了手机号登录，
// 只能清除应用数据脱困。手机模拟器 hilog 实证：
//   污染态  WaitTdlibParameters -> WaitOtherDeviceConfirmation
//   干净态  WaitTdlibParameters -> WaitPhoneNumber
//
// **为什么之前三次都没修好**：c4b6c49 改的是 UI（冷启动不再直落扫码页），页面对了
// 但 TDLib 还在扫码态；e504235 和 7b56098 都把它当成瞬时竞态加了重试，而这是**持久
// 状态**，重试三次和一次没区别。
//
// **为什么判定要两个条件同时成立**：唯一的出路是 TDLib 的 destroy——它删掉本地
// 授权数据，是破坏性的。所以必须同时满足「TDLib 明确拒绝了」和「当前确实卡在扫码
// 态」才动手。少一个条件都可能把用户的本地状态白白毁掉：
//   · 同样的拒绝但不在扫码态 → 是别的时机问题，sendAuthRequest 的重试就够了；
//   · 在扫码态但错误是 PHONE_NUMBER_INVALID / FLOOD_WAIT → 号码或频率的问题，
//     清数据解决不了，只是白白毁掉状态。
export function needsAuthorizationReset(errorMessage: string, authType: string): boolean {
  if (authType !== QR_CONFIRMATION_STATE) {
    return false;
  }
  return isInternalAuthError(errorMessage);
}
