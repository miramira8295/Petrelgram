// 行内标签实测宽度的进程级记忆（P4 批 3c；批 2 的 SENDER_LABEL_WIDTHS 同款
// 思路的共享版）。
//
// 背景：时间层最小宽度要跟「气泡里最宽的兄弟」（转发标签/发送者名/评论行），
// 这些宽度是 onAreaChange 量出来的。V1 靠 @State「复用不清零」留住上一行的
// 近似值兜底；V2 的 @Local 复用必重置，改为按标签**文本**记忆——复用当口
// 先播种（同文本即同宽，比 V1 拿上一行随机标签的宽更准），实测回调落地后
// 回写。上限 FIFO 淘汰防涨。key 由调用方自带前缀（'sender:'/'forward:'…），
// 一张表服务所有标签类。

const widths: Map<string, number> = new Map<string, number>();
const LIMIT: number = 1024;

export function rememberLabelWidth(key: string, width: number): void {
  if (key === '' || !(width > 0)) {
    return;
  }
  if (!widths.has(key) && widths.size >= LIMIT) {
    const oldest = widths.keys().next().value as string | undefined;
    if (oldest !== undefined) {
      widths.delete(oldest);
    }
  }
  widths.set(key, width);
}

export function recallLabelWidth(key: string): number {
  return widths.get(key) ?? 0;
}
