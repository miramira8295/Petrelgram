// TdClient 到点就不等了（`TdError(-1, 'request timeout')`，见 TdClient.send 里的
// scheduleTimeoutTimer），但那只说明**回执**没回来，**不说明请求没被执行**——
// TDLib 多半已经把它发出去了，服务端也可能已经受理。
//
// 所以「超时」的正确语义是**结果未知**，既不能当成成功，更不能当成失败。这条已经
// 被踩过两次：
//   · 新建群组：超时后按失败处理、让用户重试，结果建出两个群
//     （newGroupCreationOutcomeUncertain 就是为此加的）；
//   · 机器人回调按钮（issue #178）：频道搜索里点翻页/链接，机器人其实已经把消息
//     编辑好了（翻页确实生效），只是 answerCallbackQuery 的回执没在 15s 内回来。
//     这时弹「操作失败，请重试」不但是假的，还引诱用户再按一次——那才会真的翻两页。
//
// 判法沿用既有的那处：按文案匹配。这句文案是本仓自己写死的常量（TdClient 里唯一
// 的产生点），不是服务端返回的文本，所以稳定。
export function requestOutcomeUncertain(rawMessage: string): boolean {
  return rawMessage.toLowerCase().indexOf('request timeout') >= 0;
}
