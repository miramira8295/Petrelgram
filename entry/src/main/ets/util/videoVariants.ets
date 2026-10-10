// 视频的多清晰度（Telegram 的 alternative_videos，2026-10-10）。纯函数，宿主上可测。
//
// 服务器给不少视频另外转了几档（1080/720/480/360…），每档带编码（h264/h265/av1）。
// 这里决定「有哪几档可选」和「这次播哪一档」。原片总是一档（codec 未知，记 ''）。

export const QUALITY_AUTO: number = 0;
// 流量网络下「自动」最高只到这一档。
export const AUTO_METERED_MAX_HEIGHT: number = 720;

// 我们解不了的编码：FFmpeg 里没有 AV1 软解（未带 dav1d），系统硬解也只接了 H.264/HEVC。
const UNPLAYABLE_CODECS: string[] = ['av1', 'av01'];

export interface VideoVariant {
  fileId: number;
  width: number;
  height: number;
  size: number;
  // 'h264' | 'h265' | 'av1' …；原片 ''。
  codec: string;
}

// 档位标签用的高度：取短边（竖屏 1080x1920 也叫 1080p）。
export function variantLabelHeight(v: VideoVariant): number {
  const w: number = Math.max(0, v.width);
  const h: number = Math.max(0, v.height);
  return w > 0 && h > 0 ? Math.min(w, h) : Math.max(w, h);
}

function playable(v: VideoVariant): boolean {
  return v.fileId !== 0 && UNPLAYABLE_CODECS.indexOf(v.codec.toLowerCase()) < 0;
}

// 可选的档：原片打头，其余去掉解不了的编码；与原片同档或彼此同档的只留文件最小的一份
// （同档里 HEVC 往往比 H.264 小，系统硬解两者都接）。结果按清晰度从高到低。
export function playableVariants(original: VideoVariant, alternatives: VideoVariant[]): VideoVariant[] {
  const originalHeight: number = variantLabelHeight(original);
  const best: Map<number, VideoVariant> = new Map();
  for (const alt of alternatives) {
    if (!playable(alt) || alt.fileId === original.fileId) {
      continue;
    }
    const h: number = variantLabelHeight(alt);
    if (h <= 0 || h === originalHeight) {
      continue;
    }
    const cur: VideoVariant | undefined = best.get(h);
    if (cur === undefined || (alt.size > 0 && (cur.size <= 0 || alt.size < cur.size))) {
      best.set(h, alt);
    }
  }
  const rest: VideoVariant[] = Array.from(best.values())
    .sort((a: VideoVariant, b: VideoVariant): number => variantLabelHeight(b) - variantLabelHeight(a));
  return [original, ...rest];
}

// 这次播哪一档。list 是 playableVariants 的结果（第一项是原片）。
// quality：QUALITY_AUTO 或想要的高度。手动档没有正好的，取不高于它的最高一档，再没有取最低。
// 自动：原片已经整份在本地（自动播放、后台缓存下好的）就用原片——不花流量、离线也能播；
// 否则不计流量的网络用原片，计流量的取不超过 720p 的最高一档。
// **查看器和列表的头部预取必须用同一个调用**（util/entryVideoVariant），预取的才是点开要播的那档。
export function pickVideoVariant(list: VideoVariant[], quality: number, metered: boolean,
  originalLocal: boolean = false): VideoVariant {
  if (list.length === 0) {
    return { fileId: 0, width: 0, height: 0, size: 0, codec: '' };
  }
  if (quality === QUALITY_AUTO && (originalLocal || !metered)) {
    return list[0];
  }
  const cap: number = quality === QUALITY_AUTO ? AUTO_METERED_MAX_HEIGHT : quality;
  let pick: VideoVariant | null = null;
  for (const v of list) {
    const h: number = variantLabelHeight(v);
    if (h <= cap && (pick === null || h > variantLabelHeight(pick))) {
      pick = v;
    }
  }
  if (pick !== null) {
    return pick;
  }
  let lowest: VideoVariant = list[0];
  for (const v of list) {
    if (variantLabelHeight(v) < variantLabelHeight(lowest)) {
      lowest = v;
    }
  }
  return lowest;
}

// 档位名（"720p"）。
export function variantLabel(v: VideoVariant): string {
  const h: number = variantLabelHeight(v);
  return h > 0 ? `${h}p` : '';
}

// 「当前网络算不算流量」。currentNetworkType 由 NetworkStateService 写：
// none | wifi | mobile | roaming | vpn | other。只有 mobile / roaming 计流量。
export function networkIsMetered(networkType: string): boolean {
  return networkType === 'mobile' || networkType === 'roaming';
}

// fileId 是不是这条视频的某一档（原片或任一清晰度）。
export function variantsOwnFile(originalFileId: number, alternatives: VideoVariant[], fileId: number): boolean {
  if (fileId === 0) {
    return false;
  }
  return fileId === originalFileId || alternatives.some((v: VideoVariant): boolean => v.fileId === fileId);
}

// 会话里自动播放小窗的目标清晰度。
export const INLINE_TARGET_HEIGHT: number = 480;

// 自动播放小窗播哪一档：原片已在本地用原片；否则取不低于 480p 的最低一档（小窗看不出更高的
// 清晰度，省下载也省解码）；都低于 480p 就取其中最高的。与网络类型无关——小窗在 Wi-Fi 下
// 播原片也是白费。
export function pickInlineVariant(list: VideoVariant[], originalLocal: boolean): VideoVariant {
  if (list.length === 0) {
    return { fileId: 0, width: 0, height: 0, size: 0, codec: '' };
  }
  if (originalLocal) {
    return list[0];
  }
  let atLeast: VideoVariant | null = null;
  let below: VideoVariant | null = null;
  for (const v of list) {
    const h: number = variantLabelHeight(v);
    if (h >= INLINE_TARGET_HEIGHT) {
      if (atLeast === null || h < variantLabelHeight(atLeast)) {
        atLeast = v;
      }
    } else if (below === null || h > variantLabelHeight(below)) {
      below = v;
    }
  }
  return atLeast !== null ? atLeast : (below !== null ? below : list[0]);
}
