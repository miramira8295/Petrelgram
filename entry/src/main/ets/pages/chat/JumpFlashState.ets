// 跳转目标高亮：回复/置顶/链接跳转落地后，在目标行上叠一条半透明色带，
// 闪烁两拍确认"就是这一条"。从 ChatPage 整体搬出（B13 批）。
//
// 【为什么这几个字段拼在一起】
// 四个 @Trace 显示态（top/height/alpha/shown）只有一处渲染读点：
// ChatTimelineHost.build() 里那个与 List 同级、挂在外层 Stack 下的
// `if (this.flash.shown) { Column()... }` 高亮矩形（兄弟节点，不是 List 的
// 子节点——已核实，读这四个 @Trace 只会让这个 if 分支自己标脏，不会牵连
// List）。flashSeq/flashTargetIdx/flashTargetId 三个普通字段是这四个显示态
// 的私有支撑（取消令牌 + 高亮目标定位），只被本簇四个方法读写，划进同一簇
// 管理。
//
// 【命名：@Trace 去掉 flash 前缀，普通字段保留】
// 类名 JumpFlashState 已经表达了"这是 flash 状态"，四个 @Trace 显示态改名
// top/height/alpha/shown，与原 ChatPage.@Local flashTop/flashHeight/
// flashAlpha/flashShown（原 1735-1738 行）一一对应，只是去掉了在类名里已经
// 说过一遍的前缀。三个普通私有字段 flashSeq/flashTargetIdx/flashTargetId
// （原 1739/1743/1744 行）原名照抄，不改。
//
// 【为什么 scroller/groups/effectDuration 不搬、不缓存】
// scroller 是页面独有（不变量：scroller 属于页面），groups 是共享滚动真源
// （控制器只能经宿主取值器只读访问，不能拿到会被页面重新赋值的字段本身）。
// effectDuration 读的是 powerSaving/reduceAnimations/autoplayVideo 三个
// @Param，页面自己算，本类只经宿主取值器拿结果。三者都是"调用时现取"，本类
// 不缓存——尤其 groups：syncFlashRect 随每次滚动回调触发，缓存的引用会立刻
// 过期。宿主取值器返回的必须是引用本身，不能拷贝（groupIndexOf 内部只按下标
// 遍历读 memberIds，不需要、也不应该拷一份数组）。
//
// 【为什么 logW 不走宿主】
// flashAtIndex 里那行 `[Jump80]` 日志用的是全局工具函数 logW（原
// import { logE, logI, logW } from '../../util/log'），不依赖任何页面状态，
// 直接在本文件里 import，不必绕宿主接口——与 ChatOverlayState 直接 import
// logE 是同一个道理。
//
// 【flashSeq："比较后不执行"，不是 clearTimeout】
// flashAtIndex 每次调用先 `const seq = ++this.flashSeq;` 领一枚新令牌；
// cancelFlash 只做 `this.flashSeq++`。三处 setTimeout/递归回调（150ms 那次、
// runBlink 入口、runBlink 内嵌的 340ms 那次）在执行时都先比一次
// `seq !== this.flashSeq`，不等就静默 return，不做任何清理。全程没有一处把
// setTimeout 的返回值存起来，因此也没有、也不应该新增 clearTimeout——取消
// 完全靠这套令牌比较实现，逐字照原样搬。
//
// 【dispose() 为什么留空】
// 侦察报告 (D) 核对过 aboutToDisappear 全链路（disposeInitialStageAndTgs /
// disposePlaybackAndSlots / persistDraftAndViewport / disposeTimersAndSeqGuards /
// stopVoicePlaybackKeepingMusic / disposeSubscriptionsInOrder / closeStores），
// 没有一处触碰 flashSeq/flashShown/flashTop/flashHeight/flashAlpha/
// flashTargetIdx/flashTargetId 或 cancelFlash/syncFlashRect/runBlink/
// flashAtIndex 字样——原代码在这一簇上就是**没有清理**，页面销毁后裸露的
// setTimeout 句柄仍会触发，只是回调里的 this 已经悬空。按铁律"原代码没有
// 清理就不新增"，dispose() 如实留空，不补 flashSeq++/clearTimeout/复位
// shown-alpha。这是本批唯一一处"证实为空就留空"的方法，不要误当成遗漏。
//
// 【与 ChatOverlayState/LiveTopCardController 同款约定】
// per-ChatPage 字段初始化器 new，绝非模块级单例；宿主接口全是箭头函数取
// 值器，现取不缓存；类中不声明 @Monitor（解注册依赖 GC，销毁时机不可靠）。
//
// 【animateTo 包 @Trace 翻转，而且是跨对象边界的，尚未上机验证】
// runBlink 用 animateTo 包住 `this.alpha` 的翻转。搬之前它包的是 ChatPage
// 自己的 @Local flashAlpha——写法等价，但这里比 SelectionSession（本仓第一个
// 这么用的先例，见 SelectionSession.ets 同名段落）**又多跨了一层**：alpha 的
// 渲染读点已经不在本对象、也不在 ChatPage，而在另一个组件
// ChatTimelineHost.build() 的 `.opacity(this.flash.alpha)` 上。animateTo 对
// @ObservedV2 的 @Trace 翻转能不能像对 @Local 那样给出过渡，本仓没有真机
// 结论；跨到另一个组件去读，更没有。理论上 V2 的响应式更新走同一条 UI 刷新
// 管线，但这条链路本仓是头一次这么用。
// 真机验收请专门看：引用/置顶/链接跳转落地后，目标行的高亮是**呼吸两拍**
// （渐显渐隐各两次），还是**一闪一灭的跳变**。判断标准就一句：它还动不动。
// 若是跳变，把 animateTo 挪回 ChatPage、由页面包住对 `this.flash` 的调用。
// 单测钉不住这条：JumpFlashState.test.ets 文件头已声明「凡是经由 animateTo
// 才会翻转的字段一律不断言」，所以这条只能靠真机。

import { AlbumGroup, groupIndexOf } from '../../util/collapseAlbums';
import { KEY_POWER_EFFECT_REPLY } from '../../store/AppSettings';
import { logW } from '../../util/log';

// 宿主（ChatPage）暴露给控制器的那一小片接口，全是箭头函数字段——取值器读
// 页面当下的真值，本类不缓存。仿 ChatOverlayStateHost/LiveTopCardControllerHost。
export interface JumpFlashStateHost {
  // 页面独有的 Scroller 实例。flashAtIndex/syncFlashRect 都要用它取目标行的
  // 布局矩形（getItemRect），本类只借用，不持有。
  scroller: () => Scroller;
  // 页面当前的分组列表——共享滚动真源，只能经这里只读访问。必须返回**引用
  // 本身**，不能拷贝：syncFlashRect 随每次滚动回调触发，是高频调用点；
  // groupIndexOf 内部本来就只按下标遍历读 memberIds，不需要拷贝。
  groups: () => AlbumGroup[];
  // 原 this.chatEffectDuration(key, ms)——读 powerSaving/reduceAnimations/
  // autoplayVideo 三个 @Param 算出的特效时长，页面自己算，本类只经这个取
  // 值器拿结果，不把那三个 @Param 的依赖搬进来。
  effectDuration: (key: string, ms: number) => number;
}

@ObservedV2
export class JumpFlashState {
  // ——— 显示态：ChatTimelineHost 直接读这四个 @Trace ———
  // 对应原 ChatPage.@Local flashTop/flashHeight/flashAlpha/flashShown（原
  // 1735-1738 行）。下面那两行是原注释，按 HEAD 的原折行照抄，未改一字。
  //
  // Jump-target highlight: a translucent overlay over the target row that
  // gently blinks twice after a reply/pinned/link jump lands.
  @Trace top: number = 0;
  @Trace height: number = 0;
  @Trace alpha: number = 0;
  @Trace shown: boolean = false;

  // ——— 内部机件：一律**不加 @Trace** ———

  // 取消令牌。cancelFlash() 和下一次 flashAtIndex() 都会让它自增，从而使
  // 所有捕获了旧值的 setTimeout/递归回调在比较时判定自己已过期、静默 return。
  private flashSeq: number = 0;
  // 高亮当前钉着的行。高亮层是按视口坐标定位的，行高一变（链接预览、缩略图、
  // 翻译状态异步到货把上面的行撑开）它就和句子错开——用户看到的是「高亮在
  // 句子上方」（issue #80）。闪烁期间每一拍都按这两个重新对一次位置。
  private flashTargetIdx: number = -1;
  private flashTargetId: number = 0;

  // 未 bind 时的空宿主：字段类型非空，且控制器在 aboutToAppear 之前就已经
  // 被构造出来（页面的字段初始化器 new）。取值器返回的都是「什么都还没有」
  // 的值。
  private host: JumpFlashStateHost = {
    scroller: (): Scroller => new Scroller(),
    groups: (): AlbumGroup[] => [],
    effectDuration: (_key: string, ms: number): number => ms
  };

  // ChatPage.aboutToAppear 里调一次。
  bind(host: JumpFlashStateHost): void {
    this.host = host;
  }

  // Gently blink the row at gidx twice — visual confirmation of where a
  // reply/pinned/link jump landed. Waits a beat for the scroll to settle so
  // getItemRect sees the laid-out row.
  //
  // targetId：这一跳要照亮的那条消息。下标是**现在**算出来的，而矩形要等
  // 150ms 布局稳了才取——这中间往上补进一页历史，同一个下标就指向别人了
  // （issue #80 的视频里，高亮框落在目标上方五行的另一条上）。给了 id 就在
  // 取矩形前重新解析一次下标；没有 id（置顶跳转那种只有下标的调用）沿用旧行为。
  flashAtIndex(gidx: number, targetId: number = 0): void {
    const seq = ++this.flashSeq;
    setTimeout(() => {
      if (seq !== this.flashSeq) {
        return;
      }
      let idx = gidx;
      if (targetId > 0) {
        const re: number = groupIndexOf(this.host.groups(), targetId);
        if (re < 0) {
          return;
        }
        idx = re;
      }
      let top = 0;
      let height = 0;
      try {
        const rect = this.host.scroller().getItemRect(idx);
        top = rect.y;
        height = rect.height;
      } catch (e) {
        return; // row not laid out (jump superseded) — skip the highlight
      }
      if (height <= 0) {
        return;
      }
      logW(`[Jump80] flash idx=${idx} target=${targetId} top=${Math.round(top)} h=${Math.round(height)} rows=${this.host.groups().length}`);
      this.flashTargetIdx = idx;
      this.flashTargetId = targetId;
      this.top = top;
      this.height = height;
      this.shown = true;
      this.alpha = 0;
      this.runBlink(seq, 2);
    }, 150);
  }

  // 把高亮层重新对到目标行上。行还在就跟着它走；找不到（被滚出窗口、数据换了）
  // 就收掉，别留一条悬空的色带。有 id 就按 id 重解下标——prepend 会让下标漂移。
  syncFlashRect(): void {
    if (!this.shown) {
      return;
    }
    let idx: number = this.flashTargetIdx;
    if (this.flashTargetId > 0) {
      idx = groupIndexOf(this.host.groups(), this.flashTargetId);
    }
    if (idx < 0) {
      this.cancelFlash();
      return;
    }
    let top: number = 0;
    let height: number = 0;
    try {
      const rect = this.host.scroller().getItemRect(idx);
      top = rect.y;
      height = rect.height;
    } catch (e) {
      this.cancelFlash();
      return;
    }
    if (height <= 0) {
      return;
    }
    if (Math.abs(top - this.top) > 0.5 || Math.abs(height - this.height) > 0.5) {
      this.top = top;
      this.height = height;
    }
  }

  private runBlink(seq: number, remaining: number): void {
    if (seq !== this.flashSeq) {
      return;
    }
    if (remaining <= 0) {
      this.shown = false;
      this.alpha = 0;
      return;
    }
    // 每一拍开始前先对一次位置（issue #80）。
    this.syncFlashRect();
    animateTo({
      duration: this.host.effectDuration(KEY_POWER_EFFECT_REPLY, 320), curve: Curve.EaseInOut
    }, () => { this.alpha = 1; });
    setTimeout(() => {
      if (seq !== this.flashSeq) {
        return;
      }
      this.syncFlashRect();
      animateTo({
        duration: this.host.effectDuration(KEY_POWER_EFFECT_REPLY, 320), curve: Curve.EaseInOut
      }, () => { this.alpha = 0; });
      setTimeout(() => { this.runBlink(seq, remaining - 1); }, 340);
    }, 340);
  }

  // Any new touch cancels the highlight: it is viewport-anchored, and while a
  // programmatic shift is re-synced by syncFlashRect, a user drag moves faster
  // than the blink cadence and the band would visibly lag the row.
  cancelFlash(): void {
    this.flashSeq++;
    this.shown = false;
    this.alpha = 0;
  }

  // aboutToDisappear 全链路清理：侦察报告 (D) 核实过，原代码在 flash 簇上
  // 没有任何清理动作——setTimeout 句柄从未存储，页面销毁后靠 flashSeq
  // 比较判据自然失效（此后不会再有新的 flashAtIndex/cancelFlash 调用把
  // this.flashSeq 往前推，但已经排队的回调本身也不会再被主动清理），不是靠
  // 这里主动清理。本方法按铁律"原代码没有清理就不新增"如实留空，不补
  // flashSeq++、不 clearTimeout（本来也没有句柄可清）、不复位
  // shown/top/height/alpha——如需加固请在后续批次单独提出并标注为新增行为。
  dispose(): void {
    // 有意留空：见上方注释与本文件顶部"dispose() 为什么留空"一节。
  }
}
