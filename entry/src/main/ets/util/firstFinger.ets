// 手势事件里的第一根手指。只判 fingerList.length 不够：线上崩溃榜（#228）里
// 有 length > 0 而 [0] 却是 undefined 的列表，长按读 localX 直接 TypeError。
// 取不到就返回 undefined，调用方按"没有坐标"处理（菜单居中、手势按默认起点）。
export function firstFinger<T>(list: T[] | undefined): T | undefined {
  if (list === undefined || list === null || list.length === 0) {
    return undefined;
  }
  const first: T | undefined = list[0];
  return first === null ? undefined : first;
}
