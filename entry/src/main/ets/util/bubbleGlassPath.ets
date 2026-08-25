// 气泡 + 尾巴的整体轮廓（SVG path 命令），给气泡材质开着时的整块裁剪用。
// 纯函数，坐标单位由 scale 决定（组件里传 vp2px(1)，单测传 1）。
//
// 容器 = [尾巴 | 气泡]（收到）或 [气泡 | 尾巴]（发出）。尾巴与气泡重叠 1，
// 所以气泡在容器里的起点是 tailW - 1。尾巴取代了那一侧的底角：从气泡边缘
// H - tailH 处斜出到容器底角的尖，再沿底边回到气泡。

function n(v: number): string {
  return `${Math.round(v * 100) / 100}`;
}

export function glassBubbleCommands(w: number, h: number, outgoing: boolean, hasTail: boolean,
  tl: number, tr: number, br: number, bl: number, tailW: number, tailH: number, scale: number): string {
  const inset = hasTail ? tailW - 1 : 0;
  const x0 = outgoing ? 0 : inset;
  const x1 = outgoing ? w - inset : w;
  const bw = x1 - x0;
  const cap = Math.max(0, Math.min(bw / 2, h / 2));
  const rTL = Math.min(tl, cap);
  const rTR = Math.min(tr, cap);
  const rBR = Math.min(br, cap);
  const rBL = Math.min(bl, cap);
  const s = scale;
  const parts: string[] = [];
  parts.push(`M${n((x0 + rTL) * s)} 0`);
  parts.push(`L${n((x1 - rTR) * s)} 0`);
  parts.push(`A${n(rTR * s)} ${n(rTR * s)} 0 0 1 ${n(x1 * s)} ${n(rTR * s)}`);
  if (outgoing && hasTail) {
    parts.push(`L${n(x1 * s)} ${n((h - tailH) * s)}`);
    parts.push(`L${n(w * s)} ${n(h * s)}`);
    parts.push(`L${n((x0 + rBL) * s)} ${n(h * s)}`);
  } else {
    parts.push(`L${n(x1 * s)} ${n((h - rBR) * s)}`);
    parts.push(`A${n(rBR * s)} ${n(rBR * s)} 0 0 1 ${n((x1 - rBR) * s)} ${n(h * s)}`);
    if (hasTail) {
      parts.push(`L0 ${n(h * s)}`);
      parts.push(`L${n(x0 * s)} ${n((h - tailH) * s)}`);
    } else {
      parts.push(`L${n((x0 + rBL) * s)} ${n(h * s)}`);
    }
  }
  if (outgoing || !hasTail) {
    parts.push(`A${n(rBL * s)} ${n(rBL * s)} 0 0 1 ${n(x0 * s)} ${n((h - rBL) * s)}`);
  }
  parts.push(`L${n(x0 * s)} ${n(rTL * s)}`);
  parts.push(`A${n(rTL * s)} ${n(rTL * s)} 0 0 1 ${n((x0 + rTL) * s)} 0`);
  parts.push('Z');
  return parts.join(' ');
}
