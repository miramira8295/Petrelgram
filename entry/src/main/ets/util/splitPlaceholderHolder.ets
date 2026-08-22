import { ComponentContent, UIContext } from '@kit.ArkUI';

// 分栏右栏空态的 ComponentContent 持有者。
//
// **为什么不能只 new 一次就一直用**：HdsNavigation 的 splitPlaceholder 收的是
// ComponentContent，那是一棵**脱离主树**的子树。主树跟着深浅色资源重解析时它
// 不会——实测（平板，2026-08-22）打开夜间模式后左栏和会话页都变深，只有右栏
// 空态还停在浅色配色上。它必须在深浅色切换时整个重建。
//
// **为什么不能在切换回调里直接 dispose**：那一刻 HdsNavigation 仍持有旧节点，
// 新的要等下一次 build 才交出去。官方也说 dispose 不能在仍被使用时调用。
// 所以这里分两步：切换时把旧的移到 stale、把 current 清空（下次 build 自然
// 新建一个），新的建好之后再用 setTimeout(0) 把 stale 释放掉——那时候
// HdsNavigation 已经换成新节点了。
//
// 用法（三个分栏页签同一形状）：
//   private holder: SplitPlaceholderHolder = new SplitPlaceholderHolder();
//   ... build 里：.splitPlaceholder(this.holder.content(this.getUIContext(), builder))
//   ... 深浅色 @Watch 里：this.holder.invalidate();
//   ... aboutToDisappear 首句：this.holder.dispose();
@Observed
export class SplitPlaceholderHolder {
  private current: ComponentContent<Object> | null = null;
  // 等待释放的旧节点。只在"新的已经交出去"之后才真正 dispose。
  private stale: ComponentContent<Object> | null = null;

  // 懒建一次。build 每帧都跑，在调用点直接 new 就是每帧重建一棵子树。
  content(context: UIContext, builder: WrappedBuilder<[]>): ComponentContent<Object> {
    const existing: ComponentContent<Object> | null = this.current;
    if (existing !== null) {
      return existing;
    }
    const created: ComponentContent<Object> = new ComponentContent<Object>(context, builder);
    this.current = created;
    this.releaseStaleLater();
    return created;
  }

  // 深浅色（或别的需要整棵重建的因素）变了：让下一次 build 重新建。
  invalidate(): void {
    if (this.current === null) {
      return;
    }
    // 旧的先留着——这一刻 HdsNavigation 还在用它。
    this.disposeStale();
    this.stale = this.current;
    this.current = null;
  }

  // 页面销毁：两个都要放掉，否则 ComponentContent 持有的节点树泄漏。
  dispose(): void {
    this.disposeStale();
    if (this.current !== null) {
      this.current.dispose();
      this.current = null;
    }
  }

  private disposeStale(): void {
    if (this.stale !== null) {
      this.stale.dispose();
      this.stale = null;
    }
  }

  // 新节点已经建好，下一帧 HdsNavigation 就会拿到它——那之后释放旧的才安全。
  private releaseStaleLater(): void {
    if (this.stale === null) {
      return;
    }
    setTimeout((): void => { this.disposeStale(); }, 0);
  }
}
