// 气泡左上角是圆弧，圆角半径越大，越靠近顶部的横向可用宽度越窄。
// 收到带发送者昵称的消息时，昵称行贴在气泡左上角，若内边距小于弧线在该
// 深度处切掉的宽度，文字就会越过弧线、露到气泡外面。
//
// 这里给出两个纯函数：弧线在某个深度处的横向切宽，以及为了让内容完全落在
// 弧线内侧还需要补多少左缩进。调用方（外壳与媒体组件）用同一套公式，保证
// 昵称与正文/图片共用同一个左基准，不会各算各的。

/** 圆角半径 radius 的气泡，在距顶边 depth 处的横向切宽（vp）。 */
export function cornerArcInset(radius: number, depth: number): number {
  if (radius <= 0) {
    return 0;
  }
  const d: number = Math.max(0, Math.min(radius, depth));
  const rest: number = radius - d;
  const squared: number = radius * radius - rest * rest;
  return radius - Math.sqrt(squared > 0 ? squared : 0);
}

/**
 * 内容已有 base 内边距时，为了完全避开弧线还需要补的左缩进（vp，向上取整）。
 * 返回 0 表示现有内边距已经够，不需要额外缩进。
 */
export function senderLeadInset(radius: number, base: number): number {
  const cut: number = cornerArcInset(radius, base);
  const extra: number = cut - base;
  return extra > 0 ? Math.ceil(extra) : 0;
}

/** BorderRadiuses 的角值可能是百分比字符串，只接受数字（vp）。 */
export function cornerPx(value: Length | undefined): number {
  return typeof value === 'number' ? value : 0;
}
