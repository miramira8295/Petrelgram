// 聊天详情页里消息气泡上的手势分工。
//
// 气泡上只有两个手势可以分配：单击和长按。两套方案换的就是它们各自干什么。
//
//   老交互（classic）  长按 → 菜单；单击留给气泡里的可交互元素
//   新交互（tapFirst） 单击 → 菜单；长按 → 直接进多选
//
// 抽成纯函数是为了把"两个都关就永远打不开菜单""长按同时干两件事"这类
// 坏组合钉在测试里，而不是散在 UI 代码的 if 里靠人看。
//
// 多选态不在这里管：ChatPage 的行外层在多选时把 hitTestBehavior 设成 Block，
// 所有点击都被行接走用于勾选，气泡收不到任何手势。

export const GESTURE_CLASSIC: string = 'classic';
export const GESTURE_TAP_FIRST: string = 'tapFirst';

export interface MessageGesturePolicy {
  tapOpensMenu: boolean;
  longPressOpensMenu: boolean;
  longPressSelects: boolean;
}

// 不认识的值一律当老交互。存量用户升上来读到的是空串；将来加了新方案又装回
// 旧版本时读到的是不认识的字符串——两种都不能把人扔进一个没有菜单的状态。
export function messageGesturePolicy(scheme: string): MessageGesturePolicy {
  if (scheme === GESTURE_TAP_FIRST) {
    return { tapOpensMenu: true, longPressOpensMenu: false, longPressSelects: true };
  }
  return { tapOpensMenu: false, longPressOpensMenu: true, longPressSelects: false };
}
