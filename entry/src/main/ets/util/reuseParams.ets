// aboutToReuse 入参的安全读取。
//
// 背景（P3 批 1 遗留的头号风险）：父级 ReusableMessageBubble 现在是
// @ReusableV2。官方《@ReusableV2装饰器：V2组件复用》只写了「在复用阶段，会
// 递归地调用所有子组件的 aboutToReuse 回调（即使子组件未被标记可复用）」，
// **没有写清递归到 V1 子组件时 params 传的是空对象 {} 还是根本不传
// （undefined）**。而 V1 子组件的方法体第一句往往就是 params['xxx']——
// 若框架传的是 undefined，那是每次复用都必炸的 TypeError。
//
// 设备不可用，两种情况都无法排除，所以这里写成「两种都安全」：
// - params 是 {}：取不到 key，返回 undefined；
// - params 是 undefined：短路，返回 undefined。
// 两种情况调用点都自然落到已有的 setTimeout 兜底分支（那五条兜底就是为这个
// 准备的），绝不抛。
//
// 注意入参类型故意写成可空：调用点的 aboutToReuse 签名保持
// `params: Record<string, Object>` 不动——把签名改成可选参数本身可能影响
// ets-loader 对生命周期方法的识别，那是一个同样无法离线验证的改动。
// 非空实参传进可空形参是安全的隐式放宽，编译期与运行期都没有代价。
export function reuseParam(
  params: Record<string, Object> | undefined, key: string): Object | undefined {
  if (params === undefined || params === null) {
    return undefined;
  }
  return params[key];
}
