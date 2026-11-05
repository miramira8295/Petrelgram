// 气泡 + 尾巴的整体轮廓（SVG path 命令），给气泡材质开着时的整块裁剪用。
// 纯函数，坐标单位由 scale 决定（组件里传 vp2px(1)，单测传 1）。
//
// 尾巴按约 30° 向外倾转：左侧逆时针，右侧镜像。连接气泡的端点沿原圆角
// 接回底边，实心尾巴、玻璃裁剪和阴影共用同一段轮廓。
// inset：描边向内缩半个线宽，避免外半边被裁掉。

function n(v: number): string {
  return `${Math.round(v * 100) / 100}`;
}

const TAIL_CTRL_NEAR_TIP: number = 0.5;
const TAIL_HOOK_X: number = 0.85;
const TAIL_HOOK_LIFT: number = 0.45;
const TAIL_TILT_COS: number = Math.sqrt(3) / 2;
const TAIL_TILT_SIN: number = 0.5;
const TAIL_INNER_WIDTH_SCALE: number = 1.5;
const TAIL_DOWN_SHIFT: number = 2;

interface TailPoint {
  x: number;
  y: number;
}

function tiltedTailPoint(x: number, y: number, pivotX: number, pivotY: number,
  sine: number, fit: number): TailPoint {
  const dx = x - pivotX;
  const dy = y - pivotY;
  return {
    x: pivotX + (dx * TAIL_TILT_COS - dy * sine) * fit,
    y: pivotY + (dx * sine + dy * TAIL_TILT_COS) * fit
  };
}

function tailBoundaryCommands(outgoing: boolean, xBody: number, xTip: number,
  yBottom: number, radius: number, tailH: number, scale: number): string {
  const direction = outgoing ? 1 : -1;
  const height = Math.max(tailH, radius);
  const arcInset = radius * (1 - Math.SQRT1_2);
  const yRoot = yBottom - height + arcInset;
  const span = xTip - xBody;
  const lift = tailH * TAIL_HOOK_LIFT;
  const xBottom = xBody - direction * radius;
  const pivotY = yRoot + height / 2;
  const sine = direction * TAIL_TILT_SIN;
  // 旋转后等比收进原尾巴留白，避免尾尖超出玻璃容器而被裁掉。
  const tipReach = span * TAIL_TILT_COS + height / 2 * sine;
  const fit = tipReach === 0 ? 1 : Math.min(1, Math.abs(span / tipReach));
  const root = tiltedTailPoint(xBody, yRoot, xBody, pivotY, sine, fit);
  const tip = tiltedTailPoint(xTip, yRoot, xBody, pivotY, sine, fit);
  const hookBody = tiltedTailPoint(xBody + span * (1 - TAIL_HOOK_X), yRoot + lift,
    xBody, pivotY, sine, fit);
  const hookTip = tiltedTailPoint(xBody + span * 0.75, yRoot + lift * 0.2,
    xBody, pivotY, sine, fit);
  const nearTip = tiltedTailPoint(xTip, yRoot + height * TAIL_CTRL_NEAR_TIP,
    xBody, pivotY, sine, fit);
  const inner = tiltedTailPoint(xBody - direction * arcInset, yBottom,
    xBody, pivotY, sine, fit);
  // 加宽靠气泡一侧的根部开口，外侧尾尖只下移；保持原来的 30° 倾转形态。
  const oldJoinY = Math.max(yBottom - radius, Math.min(yBottom, inner.y));
  const oldInnerWidth = Math.max(0, oldJoinY - root.y);
  const innerWidth = Math.min(height, oldInnerWidth * TAIL_INNER_WIDTH_SCALE);
  const innerScale = oldInnerWidth > 0 ? innerWidth / oldInnerWidth : 1;
  inner.y = Math.min(yBottom, (root.y + oldJoinY + innerWidth) / 2 + TAIL_DOWN_SHIFT);
  root.y = inner.y - innerWidth;
  hookBody.y = inner.y - (oldJoinY - hookBody.y) * innerScale;
  tip.y += TAIL_DOWN_SHIFT;
  hookTip.y += TAIL_DOWN_SHIFT;
  nearTip.y = Math.min(yBottom, nearTip.y + TAIL_DOWN_SHIFT);
  // 内侧随旋转抬起后，沿实际圆弧切线接回主体，保证连接连续。
  const joinLift = Math.max(0, Math.min(radius, yBottom - inner.y));
  const joinRun = Math.sqrt(Math.max(0, radius * radius - (radius - joinLift) * (radius - joinLift)));
  const xJoin = xBottom + direction * joinRun;
  const yJoin = yBottom - joinLift;
  const tangent = (radius > 0 ? Math.min(lift, radius * 0.35) : lift) * fit;
  const nearJoinX = xJoin + direction * tangent * (radius > 0 ? (radius - joinLift) / radius : 1);
  const nearJoinY = yJoin - (radius > 0 ? tangent * joinRun / radius : 0);
  const s = scale;
  if (outgoing) {
    return `L${n(xBody * s)} ${n(root.y * s)} ` +
      `C${n(hookBody.x * s)} ${n(hookBody.y * s)} ${n(hookTip.x * s)} ${n(hookTip.y * s)} ${n(tip.x * s)} ${n(tip.y * s)} ` +
      `C${n(nearTip.x * s)} ${n(nearTip.y * s)} ${n(nearJoinX * s)} ${n(nearJoinY * s)} ${n(xJoin * s)} ${n(yJoin * s)} ` +
      `A${n(radius * s)} ${n(radius * s)} 0 0 1 ${n(xBottom * s)} ${n(yBottom * s)}`;
  }
  return `L${n(xBottom * s)} ${n(yBottom * s)} ` +
    `A${n(radius * s)} ${n(radius * s)} 0 0 1 ${n(xJoin * s)} ${n(yJoin * s)} ` +
    `C${n(nearJoinX * s)} ${n(nearJoinY * s)} ${n(nearTip.x * s)} ${n(nearTip.y * s)} ${n(tip.x * s)} ${n(tip.y * s)} ` +
    `C${n(hookTip.x * s)} ${n(hookTip.y * s)} ${n(hookBody.x * s)} ${n(hookBody.y * s)} ${n(xBody * s)} ${n(root.y * s)}`;
}

export function glassBubbleCommands(w: number, h: number, outgoing: boolean, hasTail: boolean,
  tl: number, tr: number, br: number, bl: number, tailW: number, tailH: number, scale: number,
  inset: number = 0, tailGutter: number = tailW - 1): string {
  // 没尾巴的行也留同宽的空位（气泡组件里是 bubbleTailGutter = tailW - 1），
  // 气泡边缘才能上下对齐。
  const gutter = tailGutter;
  const x0 = (outgoing ? 0 : gutter) + inset;
  const x1 = (outgoing ? w - gutter : w) - inset;
  const yTop = inset;
  const yBottom = h - inset;
  const xTip = outgoing ? w - inset : inset;
  const bw = x1 - x0;
  const bh = yBottom - yTop;
  const cap = Math.max(0, Math.min(bw / 2, bh / 2));
  const rTL = Math.min(tl, cap);
  const rTR = Math.min(tr, cap);
  const rBR = Math.min(br, cap);
  const rBL = Math.min(bl, cap);
  const s = scale;
  const parts: string[] = [];
  parts.push(`M${n((x0 + rTL) * s)} ${n(yTop * s)}`);
  parts.push(`L${n((x1 - rTR) * s)} ${n(yTop * s)}`);
  parts.push(`A${n(rTR * s)} ${n(rTR * s)} 0 0 1 ${n(x1 * s)} ${n((yTop + rTR) * s)}`);
  if (outgoing && hasTail) {
    parts.push(tailBoundaryCommands(true, x1, xTip, yBottom, rBR, tailH, s));
    parts.push(`L${n((x0 + rBL) * s)} ${n(yBottom * s)}`);
  } else {
    parts.push(`L${n(x1 * s)} ${n((yBottom - rBR) * s)}`);
    parts.push(`A${n(rBR * s)} ${n(rBR * s)} 0 0 1 ${n((x1 - rBR) * s)} ${n(yBottom * s)}`);
    if (hasTail) {
      parts.push(tailBoundaryCommands(false, x0, xTip, yBottom, rBL, tailH, s));
    } else {
      parts.push(`L${n((x0 + rBL) * s)} ${n(yBottom * s)}`);
    }
  }
  if (outgoing || !hasTail) {
    parts.push(`A${n(rBL * s)} ${n(rBL * s)} 0 0 1 ${n(x0 * s)} ${n((yBottom - rBL) * s)}`);
  }
  parts.push(`L${n(x0 * s)} ${n((yTop + rTL) * s)}`);
  parts.push(`A${n(rTL * s)} ${n(rTL * s)} 0 0 1 ${n((x0 + rTL) * s)} ${n(yTop * s)}`);
  parts.push('Z');
  return parts.join(' ');
}

// 实心尾巴向气泡内部延伸一个圆角半径，填充圆弧与尾巴之间的连接区域。
// 调用方用负 margin 抵消这部分宽度，消息正文和尾尖的横向位置保持不变。
export function tailShapeCommands(outgoing: boolean, tailW: number, tailH: number,
  scale: number, radius: number = 0, overlap: number = 0): string {
  const height = Math.max(tailH, radius);
  const xBody = outgoing ? radius + overlap : tailW - overlap;
  const xTip = outgoing ? radius + tailW : 0;
  const xInner = outgoing ? overlap : tailW - overlap + radius;
  const boundary = tailBoundaryCommands(outgoing, xBody, xTip, height, radius, tailH, scale);
  const close = outgoing ? '' : `L${n(xBody * scale)} 0 `;
  return `M${n((outgoing ? xBody : xInner) * scale)} 0 ${boundary} ${close}L${n(xInner * scale)} 0 Z`;
}

// 玻璃档分三段点亮，判据集中在这里。
//
// 【为什么需要分段】容器是 [尾巴/留白 | 气泡]，留白恒为 tailW - 1 = 7vp（见
// glassBubbleCommands 里的 gutter）。玻璃档下**气泡该有的形状全靠 clipShape**，
// 而 clipShape 要等 onAreaChange 量到 w/h 才挂得上（bubbleGlassModifier 里
// w<=0||h<=0 时 path 传 null）。
//
// 于是「已上色、还没量到」这一窗口里，容器是没裁剪的：整块玻璃把 7vp 留白一起
// 涂满，没有尾巴、没有描边，左边缘比正常位置外扩整整 7vp。量到之后裁剪挂上，
// 边缘弹回、尾巴冒出来 —— 这就是用户报的横跳。
//
// 【为什么不能退回实心档】第一版修法让没量到的那一帧整行退回实心渲染。形状是
// 对了，但**实心气泡是不透明白底**，于是横跳换成了「白闪一下」——真机原话
// 「1 会变白，闪透明」。拿一个 artifact 换另一个 artifact，不算修好。
//
// 【现在的做法】把玻璃拆成两层，各自的点亮条件不同：
//
//   'off'      不要玻璃（材质关掉 / 离屏 / 省电 / 大表情贴纸）——走实心档。
//   'bodyOnly' 要玻璃、但还没量到尺寸。**只有气泡本体**上玻璃色和模糊；容器
//              保持全透明、不挂裁剪、不描边，尾巴那一格只占位不画。
//              气泡本体天然就在留白右侧，圆角也是它自己的 borderRadius，
//              不需要任何绝对坐标——所以这一帧看到的是一个「位置完全正确、
//              只是还没长出尾巴」的玻璃气泡。和最终形态的差异只有一个尾巴。
//   'full'     量到了。玻璃色/模糊切换到容器，气泡本体退为透明；容器负责整体
//              轮廓裁剪/描边，尾巴长出来。任一时刻都只有一层背景模糊。
//
// 关键点：'bodyOnly' → 'full' 期间**气泡本体的左边缘一动不动**，因为它的位置
// 由布局里的 7vp 留白决定，与裁剪无关。会变的只有「尾巴有没有」。
export type GlassStage = 'off' | 'bodyOnly' | 'full';

export function glassStage(wanted: boolean, w: number, h: number): GlassStage {
  if (!wanted) {
    return 'off';
  }
  return w > 0 && h > 0 ? 'full' : 'bodyOnly';
}

// 是否处于玻璃结构模式：'bodyOnly' 和 'full' 都是。调用方用它决定尾巴占位、
// 阴影等结构；本体是否真的绘制背景由下面的 glassBodyFallbackPainted 决定。
export function glassBodyPainted(wanted: boolean, w: number, h: number): boolean {
  return glassStage(wanted, w, h) !== 'off';
}

// 气泡本体要不要临时承担玻璃绘制。它只服务还没量到外层尺寸的首帧：一旦完整
// 轮廓可用，背景色和模糊都切到外层，避免本体与容器在同一区域重复合成。
export function glassBodyFallbackPainted(wanted: boolean, w: number, h: number): boolean {
  return glassStage(wanted, w, h) === 'bodyOnly';
}

// **容器**要不要上玻璃（连带裁剪与描边）：只有量到尺寸的 'full' 才行。
// 没量到就让容器彻底透明——它跨着那 7vp 留白，没有裁剪时一上色就外扩。
export function glassPaintReady(wanted: boolean, w: number, h: number): boolean {
  return glassStage(wanted, w, h) === 'full';
}
