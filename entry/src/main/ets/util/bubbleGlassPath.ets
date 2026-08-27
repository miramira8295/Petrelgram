// 气泡 + 尾巴的整体轮廓（SVG path 命令），给气泡材质开着时的整块裁剪用。
// 纯函数，坐标单位由 scale 决定（组件里传 vp2px(1)，单测传 1）。
//
// 容器 = [尾巴/留白 | 气泡]（收到）或 [气泡 | 尾巴/留白]（发出）。尾巴与气泡重叠 1，
// 所以气泡在容器里的起点是 tailW - 1。尾巴取代了那一侧的底角：底边一直走到容器
// 底角的尖，再由**一段三次贝塞尔**收回气泡边缘的 H - tailH 处——直线斜边太生硬，
// 曲线才是官方客户端那个"甩出去又勾回来"的尾巴。
//
// inset：整条轮廓向内缩的量。裁剪用 0；描边用半个线宽，否则线的外半边被裁掉，
// 看着只有半根。

function n(v: number): string {
  return `${Math.round(v * 100) / 100}`;
}

// 尾巴的形状参数。尾巴由两条曲线围成：
//   外侧（上）：从气泡边缘的 yTail 甩出到尾尖，控制点按 tailH 取比例——
//     NEAR_TIP 贴着尖那侧竖直，尾尖因此是尖的、不是圆的；NEAR_BODY 决定线离开
//     气泡时的走向——**越大越往下压**（控制点越靠近 yTail，一出气泡就朝尖走），
//     越小则贴着气泡边缘多竖直走一段再甩出去，看着像靠气泡那侧往上翘。
//   内侧（下）：从气泡底边**向上兜回**尾尖，两个控制点抬高 HOOK_LIFT，
//     底边因此是凹的——这就是"勾"。HOOK_X 是它离开底边的位置（按 tailW 取比例）。
// 四个数就是尾巴的全部造型，调它们即可，别去动 path 的拼装。
const TAIL_CTRL_NEAR_TIP: number = 0.5;
const TAIL_CTRL_NEAR_BODY: number = 0.92;
const TAIL_HOOK_X: number = 0.85;
const TAIL_HOOK_LIFT: number = 0.3;

export function glassBubbleCommands(w: number, h: number, outgoing: boolean, hasTail: boolean,
  tl: number, tr: number, br: number, bl: number, tailW: number, tailH: number, scale: number,
  inset: number = 0): string {
  // 没尾巴的行也留同宽的空位（气泡组件里是 bubbleTailGutter = tailW - 1），
  // 气泡边缘才能上下对齐。
  const gutter = tailW - 1;
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
  const yTail = yBottom - tailH;
  const cNear = yBottom - tailH * TAIL_CTRL_NEAR_TIP;
  const cBody = yBottom - tailH * TAIL_CTRL_NEAR_BODY;
  const hookX = tailW * TAIL_HOOK_X;
  const hookLift = tailH * TAIL_HOOK_LIFT;
  const s = scale;
  const parts: string[] = [];
  parts.push(`M${n((x0 + rTL) * s)} ${n(yTop * s)}`);
  parts.push(`L${n((x1 - rTR) * s)} ${n(yTop * s)}`);
  parts.push(`A${n(rTR * s)} ${n(rTR * s)} 0 0 1 ${n(x1 * s)} ${n((yTop + rTR) * s)}`);
  if (outgoing && hasTail) {
    // 右边缘走到 yTail，一段曲线甩出到尖，底边再直着回到左下角。
    parts.push(`L${n(x1 * s)} ${n(yTail * s)}`);
    parts.push(`C${n(x1 * s)} ${n(cBody * s)} ${n(xTip * s)} ${n(cNear * s)} ` +
      `${n(xTip * s)} ${n(yBottom * s)}`);
    // 尾尖 → 底边：抬高的两个控制点让这一段向上兜，尾巴底下是勾回来的。
    parts.push(`C${n((xTip + (x1 - xTip) * 0.25) * s)} ${n((yBottom - hookLift * 0.2) * s)} ` +
      `${n((x1 - hookX * 0.2) * s)} ${n((yBottom - hookLift) * s)} ` +
      `${n((x1 - hookX) * s)} ${n(yBottom * s)}`);
    parts.push(`L${n((x0 + rBL) * s)} ${n(yBottom * s)}`);
  } else {
    parts.push(`L${n(x1 * s)} ${n((yBottom - rBR) * s)}`);
    parts.push(`A${n(rBR * s)} ${n(rBR * s)} 0 0 1 ${n((x1 - rBR) * s)} ${n(yBottom * s)}`);
    if (hasTail) {
      // 底边 → 尾尖：抬高的两个控制点让这一段向上兜，尾巴底下是勾回来的。
      parts.push(`L${n((x0 + hookX) * s)} ${n(yBottom * s)}`);
      parts.push(`C${n((x0 + hookX * 0.2) * s)} ${n((yBottom - hookLift) * s)} ` +
        `${n((xTip + (x0 - xTip) * 0.25) * s)} ${n((yBottom - hookLift * 0.2) * s)} ` +
        `${n(xTip * s)} ${n(yBottom * s)}`);
      // 尾尖 → 气泡左边缘的外侧曲线。
      parts.push(`C${n(xTip * s)} ${n(cNear * s)} ${n(x0 * s)} ${n(cBody * s)} ` +
        `${n(x0 * s)} ${n(yTail * s)}`);
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

// 只有尾巴那一小块的形状（实心档用）。和整体轮廓里那段是同一条曲线，两档才长
// 得一样——材质关掉时尾巴是独立的填充节点，画的是这条。
// 坐标原点是尾巴自己那个 tailW × tailH 的盒子。
export function tailShapeCommands(outgoing: boolean, tailW: number, tailH: number,
  scale: number): string {
  const xBody = (outgoing ? 0 : tailW) * scale;
  const xTip = (outgoing ? tailW : 0) * scale;
  const bottom = tailH * scale;
  const cNear = tailH * (1 - TAIL_CTRL_NEAR_TIP) * scale;
  const cBody = tailH * (1 - TAIL_CTRL_NEAR_BODY) * scale;
  const hookLift = tailH * TAIL_HOOK_LIFT * scale;
  // 实心档的尾巴自己占一个盒子，底边就在盒子底：从贴气泡那条竖边下来，向上兜
  // 回尾尖（勾），再沿外侧曲线回到起点。和整体轮廓里那两段是同一组参数。
  const span = xTip - xBody;
  return `M${n(xBody)} 0 L${n(xBody)} ${n(bottom)} ` +
    `C${n(xBody + span * 0.15)} ${n(bottom - hookLift)} ` +
    `${n(xBody + span * 0.75)} ${n(bottom - hookLift * 0.2)} ` +
    `${n(xTip)} ${n(bottom)} ` +
    `C${n(xTip)} ${n(cNear)} ${n(xBody)} ${n(cBody)} ${n(xBody)} 0 Z`;
}

// 玻璃档「上色」与「裁剪」必须同一个开关。
//
// 容器是 [尾巴/留白 | 气泡]，留白恒为 tailW - 1 = 7vp（见 glassBubbleCommands
// 里的 gutter）。玻璃档下气泡本体是透明的，颜色/模糊都挂在这个容器上，气泡该有
// 的形状**完全**由 clipShape 给——而 clipShape 只有在 onAreaChange 量到尺寸
// （w/h > 0）之后才挂得上。
//
// 于是「已上色、还没量到」这一窗口里，容器是**没裁剪**的：整块 7vp 留白连着
// 气泡一起被涂成玻璃色，看上去就是气泡左边缘（发出的是右边缘）整整外扩 7vp、
// 而且没有尾巴。量到之后裁剪挂上，边缘再弹回去、尾巴冒出来——正是用户报的
// 「气泡左边一直在横跳，幅度就是尾巴那么宽」。
//
// 这个窗口不是罕见情形：行 key 一变，Repeat 就是删旧插新，新节点从复用池里出来
// 走 aboutToReuse，那里把 glassW/glassH 清零（复用成另一条消息后旧尺寸算出的
// 路径是错的，必须清）。而行 key 里编了 senderName、inlineCustomEmojiPaths、
// 自定义表情位图路径等一批**异步到达**的字段，所以每落地一张图/一个名字就横跳
// 一次。
//
// 修法是让上色跟着裁剪走：没量到就整档退回实心渲染（气泡自己上色 + 独立的
// 三角 Path 尾巴），形状始终是对的，只是这一两帧没有玻璃。
export function glassPaintReady(live: boolean, w: number, h: number): boolean {
  return live && w > 0 && h > 0;
}
