// ⚠️ 临时探针（P4 批 0.5，判读完整个文件删除）。
//
// 回答 docs/superpowers/specs/2026-09-02-p4-bubble-v2-survey.md 的三个开放
// 问题：@ComponentV2 普通子组件在 @ReusableV2 父（ReusableMessageBubble）下
// 复用时——
//   Q1 aboutToRecycle/aboutToReuse 是否触发？触发时 @Param 是新值还是旧值？
//   Q2 @Local 重置发生在回调之前还是之后？
//   Q3 @Monitor 在复用参数落地时是否触发？首个 build 时各值是什么？
//
// 判读方法：装机后在长会话里连滑，抓 [V2Probe] 日志。
//   reuse 行存在          → 回调会触发（Q1a）
//   reuse 行 rowTag=新值   → @Param 先落地（Q1b）
//   reuse 行 localMark=-1  → @Local 重置在回调前（Q2）
//   monitor 行在 reuse 附近 → @Monitor 复用期会触发（Q3）
//   build 行的取值组合      → 首帧能读到什么（Q3 播种时机）
//
// 删除清单：本文件 + LightweightPlainTextBubble 里的一处插桩（搜 V2ReuseProbe）。

import { logW } from '../../util/log';

let probeSeq: number = 0;

@ComponentV2
export struct V2ReuseProbe {
  // 绑定 msg.rowId：复用换到别的行时它必变。
  @Param rowTag: number = 0;
  // 初值 -1：任何时刻读到 -1 就说明刚被框架重置过。
  @Local localMark: number = -1;
  // 无装饰器成员按官方表格视作常量、复用不重置——用它辨认「同一个实例」。
  private instanceId: number = ++probeSeq;
  private lastBuildTag: number = -2;

  @Monitor('rowTag')
  onRowTagChanged(monitor: IMonitor): void {
    const before = monitor.value('rowTag')?.before as number | undefined;
    logW(`[V2Probe] monitor inst=${this.instanceId} rowTag ${before}->${this.rowTag}` +
      ` localMark=${this.localMark}`);
  }

  aboutToAppear(): void {
    logW(`[V2Probe] appear inst=${this.instanceId} rowTag=${this.rowTag} localMark=${this.localMark}`);
    this.localMark = this.rowTag;
  }

  aboutToRecycle(): void {
    logW(`[V2Probe] recycle inst=${this.instanceId} rowTag=${this.rowTag} localMark=${this.localMark}`);
  }

  aboutToReuse(): void {
    logW(`[V2Probe] reuse inst=${this.instanceId} rowTag=${this.rowTag} localMark=${this.localMark}`);
    this.localMark = this.rowTag;
  }

  // build 里不能直接打日志，借一个属性求值口：只在换行后的第一次 build 记。
  private probeSize(): number {
    if (this.lastBuildTag !== this.rowTag) {
      logW(`[V2Probe] build inst=${this.instanceId} rowTag=${this.rowTag} localMark=${this.localMark}`);
      this.lastBuildTag = this.rowTag;
    }
    return 0;
  }

  build() {
    Column().width(this.probeSize()).height(0);
  }
}
