// 缩略图到达合批（issue #201 第 7 条，壁纸页）。
//
// 几十张缩略图各自下载完成时，原来每张都 `this.thumbPaths = new Map(...)` 一次，
// 每换一次 Map 整张网格就重新 diff 一遍——进页面头两秒几十次全网格刷新，就是
// "卡"的来源。这里把到达的先攒着，调用方用一个短定时器一次性落进状态。
// 纯数据结构，不碰 UI，好单测。
export class ThumbBatch {
  private pending: Map<string, string> = new Map<string, string>();
  private armed: boolean = false;

  // 返回 true 表示调用方该安排一次落盘（自上次 drain/clear 以来的第一张）。
  add(key: string, path: string): boolean {
    this.pending.set(key, path);
    if (this.armed) {
      return false;
    }
    this.armed = true;
    return true;
  }

  drain(): Map<string, string> {
    const out: Map<string, string> = this.pending;
    this.pending = new Map<string, string>();
    this.armed = false;
    return out;
  }

  clear(): void {
    this.pending = new Map<string, string>();
    this.armed = false;
  }
}
