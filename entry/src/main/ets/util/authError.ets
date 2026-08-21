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
