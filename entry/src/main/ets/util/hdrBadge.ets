// 控制条左侧那枚 HDR 角标该不该亮。
//
// 数据来自 AVPlayer.getTrackDescription() 里视频轨的 MD_KEY_HDR_TYPE
// （'hdr_type'，API 12+）。官方把值域定义成 HdrType 枚举
// （AV_HDR_TYPE_NONE=0 / AV_HDR_TYPE_VIVID=1），却把「对应键值类型」写成
// string——数字和字符串两种都可能拿到，所以两种都认。
//
// 【两条刻意的局限，都是"宁可不标也不标错"】
//   1. HdrType 只区分 None / HDR Vivid，**没有 HDR10 / HLG 的枚举值**。一条
//      HDR10 片源很可能报 0，角标就不出现。漏标只是少个信息，错标是骗人。
//   2. 角标只在 AVPlayer 引擎上出现。ijkplayer 那套既检测不了、也渲染不出
//      HDR（着色器只有 BT.601/709，没有 PQ/HLG），在那边挂一枚 HDR 是谎报。

export const HDR_BADGE_TEXT: string = 'HDR';

export function isHdrTrackValue(raw: string): boolean {
  const text: string = raw.trim();
  if (text === '') {
    return false;
  }
  const num: number = Number(text);
  if (Number.isFinite(num)) {
    // AV_HDR_TYPE_NONE = 0，其余非零值都是某种 HDR。
    return num > 0;
  }
  // 非数字串（真拿到 'vivid' 这类的时候）：只要不是明确的 none 就算 HDR。
  return text.toLowerCase() !== 'none';
}
