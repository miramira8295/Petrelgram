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
// 尾尖圆角（vp）。原来尾巴是「勾回曲线 + 外侧曲线」两条三次曲线在尖上交成
// 一个直角，放大看是个极尖的毛刺。这里把两段合成**一段**三次曲线：起点落在
// 底边上（切线与底边水平），终点落在左边缘（切线与左边缘垂直），尾巴往外甩
// 再勾回来的走向由两个控制点给足——所以尖没了，但尾巴形态还是那条反曲线。
const TAIL_TIP_RADIUS: number = 0.8;

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
  const yTail = yBottom - tailH;
  const cNear = yBottom - tailH * TAIL_CTRL_NEAR_TIP;
  const cBody = yBottom - tailH * TAIL_CTRL_NEAR_BODY;
  const hookX = tailW * TAIL_HOOK_X;
  const hookLift = tailH * TAIL_HOOK_LIFT;
  const tipR = Math.min(TAIL_TIP_RADIUS, tailW * 0.4, tailH * 0.4) * scale;
  // 尾尖真圆弧半径：A 指令用它，保证起点/终点两处同时相切。
  const rTail = Math.min(TAIL_TIP_RADIUS, tailW * 0.4, tailH * 0.4) * scale;
  const s = scale;
  const parts: string[] = [];
  parts.push(`M${n((x0 + rTL) * s)} ${n(yTop * s)}`);
  parts.push(`L${n((x1 - rTR) * s)} ${n(yTop * s)}`);
  parts.push(`A${n(rTR * s)} ${n(rTR * s)} 0 0 1 ${n(x1 * s)} ${n((yTop + rTR) * s)}`);
  if (outgoing && hasTail) {
    // 右边缘走到 yTail，一段曲线甩出到尖，底边再直着回到左下角。
    // 反曲线：从气泡右边缘下来 → 向外鼓 → 收到尾尖上方的圆弧起点（切线竖直）。
    parts.push(`L${n(x1 * s)} ${n(yTail * s)}`);
    parts.push(`C${n(x1 * s)} ${n((yTail + tailH * 0.52) * s)} ` +
      `${n(xTip * s)} ${n((yTail + tailH * 0.86) * s)} ` +
      `${n(xTip * s)} ${n((yBottom - rTail) * s)}`);
    // 尾尖 0.8vp 真圆弧：与上面的竖直切线、下面的水平底边同时相切。
    parts.push(`A${n(rTail * s)} ${n(rTail * s)} 0 0 0 ${n((xTip - rTail) * s)} ${n(yBottom * s)}`);
    parts.push(`L${n((x0 + rBL) * s)} ${n(yBottom * s)}`);
  } else {
    parts.push(`L${n(x1 * s)} ${n((yBottom - rBR) * s)}`);
    parts.push(`A${n(rBR * s)} ${n(rBR * s)} 0 0 1 ${n((x1 - rBR) * s)} ${n(yBottom * s)}`);
    if (hasTail) {
      // 倒着走轮廓：底边先到圆弧起点，圆弧转到尾尖的竖直切线，再反曲线收回气泡边。
      parts.push(`L${n((xTip + rTail) * s)} ${n(yBottom * s)}`);
      parts.push(`A${n(rTail * s)} ${n(rTail * s)} 0 0 1 ${n(xTip * s)} ${n((yBottom - rTail) * s)}`);
      parts.push(`C${n(xTip * s)} ${n((yTail + tailH * 0.86) * s)} ` +
        `${n(x0 * s)} ${n((yTail + tailH * 0.52) * s)} ` +
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
  // 尾巴自己的盒子：贴气泡那条边在 xBody，尾尖在外侧 xTip。
  const xBody = (outgoing ? 0 : tailW) * scale;
  const xTip = (outgoing ? tailW : 0) * scale;
  const bottom = tailH * scale;
  const r = Math.min(TAIL_TIP_RADIUS, tailW * 0.4, tailH * 0.4) * scale;
  // 圆弧终点落在底边上、离尾尖 r；发出的气泡镜像到另一侧。
  const arcEnd = outgoing ? xTip - r : xTip + r;
  // sweep：收到的从竖直切到水平取 0，发出的镜像取 1。
  const sweep = outgoing ? 1 : 0;

  // ① 贴气泡的上端
  // ② 反曲线：先沿气泡边下来（控制点 1 在 xBody），再向外扬到尾尖上方（控制点 2 在 xTip）
  // ③ 尾尖 0.8vp 真圆弧：起点切线与②竖直相切、终点切线与底边水平相切
  // ④ 底边回到气泡边，再沿气泡边回到起点闭合
  return `M${n(xBody)} 0 ` +
    `C${n(xBody)} ${n(bottom * 0.52)} ` +
    `${n(xTip)} ${n(bottom * 0.86)} ` +
    `${n(xTip)} ${n(bottom - r)} ` +
    `A${n(r)} ${n(r)} 0 0 ${sweep} ${n(arcEnd)} ${n(bottom)} ` +
    `L${n(xBody)} ${n(bottom)} ` +
    `L${n(xBody)} 0 Z`;
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
