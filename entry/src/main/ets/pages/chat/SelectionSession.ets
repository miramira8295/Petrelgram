// 消息多选（长按菜单的"选择"）状态机。
// 从 ChatPage 整体搬出（B7 批）。
//
// 【为什么要搬】
// 长按进多选、逐行点选、被撤回时被动摘除——这几步共享的其实只有两个字段：
// 是否在多选态、选中了哪些 id。搬之前 selecting/selectedIds 是 ChatPage 的
// @Local，任何一次点选都要重跑一遍页面的 chatTitleBar/bottomDock/timelineRow
// 三个闭包。搬进 @ObservedV2 之后，这三个闭包仍在页面里、仍然直读
// `this.selection.active/ids`（依赖粒度不变——本批不像 B5 的 TopBanners 那样
// 把宿主也一起改成直读控制器，SelectionHeader/timelineRow 仍是 ChatPage 自己
// 的 @Builder，收益只是把状态和判定收进一个能单测的对象）。
//
// 【为什么"一行要么整体选中、要么整体不选"不在本类里重新实现】
// 这条不变量由 util/messageSelection 的纯函数（rowSelected/toggleRow/
// pruneSelection/rowSelectable）保证；本类的 isRowSelected/toggleRow/reconcile
// 都是薄包装，只管把 this.ids 喂给它们、把结果写回去。
//
// 【为什么 reconcileMessageActionTargets 只搬了一半】
// 原方法同时清两件不相关的事：多选集合里的幽灵 id（本簇），和反应面板的目标
// 消息是否还存在（不相关的 reactionSheet 子系统）。本类的 reconcile(list) 只做
// 前一半；ChatPage.reconcileMessageActionTargets 改为先调
// `this.selection.reconcile(list)`，再自己跑 reactionSheet 那几行——两个状态
// 域的清理时机（同一次 publishSnapshotAndChrome）不变，只是分成了两次调用。
// resetMessageActionSession 是同样的裁决：本类的 reset() 只覆盖
// active/ids，reactionSheet 那几个字段仍由页面在同一个调用点自己清。
//
// 【为什么是 per-ChatPage 实例，不是模块级单例】
// 平板分栏、导航栈多层时同时活着多个 ChatPage，各自的多选态互不相干。做成
// 单例会让两页互相清对方选中的消息。页面用字段初始化器 new 一个：首帧前就
// 已存在、引用全生命周期稳定、类型非空。
//
// 【为什么没有 …Seq / 定时器】
// 本簇的每一次变更都是同步的用户点击或同步的列表快照回调，不存在"发出去的
// 请求晚于后来的操作回来"这种竞态，因此没有序号守卫要守；也没有定时器。
// dispose() 仍然提供，只是为了和其余控制器统一的 bind/dispose 生命周期——
// ChatPage.aboutToDisappear 可以对每个控制器无差别地调一遍 dispose()。
//
// 【不在本类里声明 @Monitor】
// 官方规则：类中 @Monitor 的解注册依赖 GC，销毁时机不可靠。本簇的所有联动都
// 用显式方法调用表达。
//
// 【animateTo 包 @Trace 翻转，尚未上机验证】
// animateSelection 用 animateTo 包住 active/ids 的翻转，和搬之前包 @Local 翻转
// 在写法上等价，但本仓从没有在真机上验证过 animateTo 对 @ObservedV2 的
// @Trace 字段翻转是否与对 @Local 翻转给出同样的过渡效果——理论上状态管理 V2
// 的响应式更新走的是同一条 UI 刷新管线，但这条链路本仓是头一次这么用。
// 真机验收请专门看多选工具栏（SelectionHeader）和消息行底色两处的淡入淡出，
// 若观察到跳变而不是过渡，把 animateTo 挪回页面、包住对
// `this.selection.enter()/exit()` 的调用。

import { AlbumGroup } from '../../util/collapseAlbums';
import { MessageEntry } from '../../store/MessageEntry';
import {
  pruneSelection, rowSelectable, rowSelected, toggleRow
} from '../../util/messageSelection';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';

// 宿主（ChatPage）暴露给控制器的那一小片接口，全是箭头函数字段——取值器读
// 页面当下的真值，动作回调把副作用交回页面执行。仿
// LiveTopCardController.ets 的 LiveTopCardHost。
//
// 两条纪律（与其余控制器一致）：
// 1. 这里只放**取值器**，不放页面的 @Local 引用。控制器不缓存页面的值。
// 2. 与本簇无关的页面子系统（反应面板、表情/贴纸抽屉）只经这里的动作回调
//    触达，不在本类里直接实现。
export interface SelectionSessionHost {
  // animateSelection 的时长依据：与 GIF/TGS 密集滑动同一时间线时要把过渡砍成
  // 0（搬之前是 `this.chatTgsScrollActive` 这个页面字段，与本簇无关，只读）。
  chatTgsScrollActive: () => boolean;
  // enter() 的两个副作用，伸到多选簇之外的页面子系统：关掉正在弹的反应
  // 面板、收起底部表情/贴纸抽屉。
  closeReactionSheet: () => void;
  setEmojiPanel: (show: boolean) => void;
  onActiveChange: (active: boolean) => void;
}

@ObservedV2
export class SelectionSession {
  // ——— 显示态：ChatPage 的 chatTitleBar/bottomDock/timelineRow 直接读这两个
  // @Trace（原 selecting/selectedIds）———

  @Trace active: boolean = false;
  @Trace ids: number[] = [];

  // 未 bind 时的空宿主：字段类型非空，且控制器在 aboutToAppear 之前就已经被
  // 构造出来（页面的字段初始化器 new）。取值器返回的都是"什么都还没有"的值。
  private host: SelectionSessionHost = {
    chatTgsScrollActive: (): boolean => false,
    closeReactionSheet: (): void => {},
    setEmojiPanel: (_show: boolean): void => {},
    onActiveChange: (_active: boolean): void => {}
  };

  // ChatPage.aboutToAppear 里调一次。
  bind(host: SelectionSessionHost): void {
    this.host = host;
  }

  // ChatPage.aboutToDisappear 调用。本簇没有定时器/序号守卫要清，保留这个
  // 方法只是为了和其余控制器统一的 bind/dispose 生命周期——见文件头「为什么
  // 没有 …Seq / 定时器」。裸清一次 active/ids 是无害的幂等操作。
  dispose(): void {
    this.clearState();
  }

  // --- multi-select ---
  // 从消息菜单进多选：选中的是**整行**，不是被长按的那一条。
  //
  // messageSelection 开篇写明的不变量是"一行要么整体选中、要么整体不选"，而
  // 这里原来只放被长按消息的 id。相册行被长按时，那是相册的头一条：行在 UI 上
  // 显示为选中（rowSelected 是"沾上就算"），计数却是 1，接着转发也只发出这一
  // 张——九图相册转发成一张。
  //
  // 参数按原实现叫 memberIds（长按那一行全部成员的 id），不是单个 id：调用方
  // （长按菜单的 onSelectMessages）传的就是整行的 id 数组。
  enter(memberIds: number[]): void {
    ContextMenu.close();
    this.host.closeReactionSheet();
    this.host.setEmojiPanel(false);
    this.animateSelection((): void => {
      this.ids = toggleRow([], memberIds);
      this.setActive(true);
    });
  }

  // 行底色的 150ms 淡入淡出。原来是消息行上一条常驻的 .animation()，现在在
  // 改动发生的那一刻显式驱动一次——时长与曲线照搬，包括滑动中给 0 那一支。
  private animateSelection(apply: () => void): void {
    animateTo({
      duration: this.host.chatTgsScrollActive() ? 0 :
        powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 150),
      curve: Curve.EaseOut
    }, apply);
  }

  exit(): void {
    this.animateSelection((): void => { this.clearState(); });
  }

  // 不带动画的裸改，供已经在 animateSelection 闭包里的调用点用（原
  // clearSelectionState）。
  private clearState(): void {
    this.ids = [];
    this.setActive(false);
  }

  private setActive(active: boolean): void {
    if (this.active === active) {
      return;
    }
    this.active = active;
    this.host.onActiveChange(active);
  }

  // resetMessageActionSession 里 selecting/selectedIds 那半的搬迁落点（B7）。
  // 会话级重置（路由切换、新会话进入）原样不套动画：搬之前
  // resetMessageActionSession 是直接裸赋值，并不经过 exitSelect/
  // clearSelectionState 那条 animateTo 路径，这里保持同样的"不动画"语义。
  // reactionSheet 的另一半（showReactionSheet/reactionTargetId/
  // reactionPendingKey/paidMediaPendingIds/closeForwardSheet()）与本簇无关，
  // 仍由页面在同一个调用点自己清。
  reset(): void {
    this.clearState();
  }

  isRowSelected(g: AlbumGroup): boolean {
    return rowSelected(this.ids, g.memberIds);
  }

  // Toggle a whole display row (an album row selects all its members).
  toggleRow(g: AlbumGroup): void {
    if (!rowSelectable(g.head.contentType)) {
      return;
    }
    this.animateSelection((): void => {
      this.ids = toggleRow(this.ids, g.memberIds);
      if (this.ids.length === 0) {
        this.clearState();
      }
    });
  }

  // reconcileMessageActionTargets 的 active/ids 半边（B7）。原方法还有一半清
  // reactionSheet，与多选无关，留在页面——ChatPage 的调用点需要先调
  // `this.selection.reconcile(list)`，再自己跑 reactionSheet 那几行判定。
  reconcile(list: MessageEntry[]): void {
    if (this.active) {
      this.ids = pruneSelection(this.ids,
        list.map((m: MessageEntry): number => m.id));
      if (this.ids.length === 0) {
        this.exit();
      }
    }
  }

  count(): number {
    return this.ids.length;
  }
}
