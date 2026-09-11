// 锚点复位簇（第二轮第 2 项，R2-B）：向上前插一页、向下追加一页、以及从后台
// 恢复时的落位，三条路径共用的"把那一行按回它原来的 y"。从 ChatPage 整体搬出。
//
// 【搬了什么，没搬什么】
// 搬：prependRestoreSeq 代次守卫、anchorCaptureOffset 诊断读数、
//     captureAnchorOffset / currentAnchorOffset、restorePrependAnchor /
//     restoreAppendAnchor / restoreScrollAnchor / attemptAnchorRestore。
//     方法体与注释**逐字**搬迁，只把跨边界的 `this.x` 换成 `this.host.x()`；
//     注释一行未改（生成时按行判定，`//` 开头的行不参与替换）。
// 没搬：采样侧（capturePrependAnchorSample / captureAppendAnchorSample）、
//     restoreCapturedAnchors、appendAnchorGateProbe / scrollStateProbe、
//     anchorItemY / anchorIndexFresh / headerChromeHeight 全部留在页面。
//     这样不变量 4 点名的那对**镜像判据**（"不是重复代码，不合并"）整段不受
//     影响，B4 的五阶段流水线形状不变，探针也仍然集中在页面里——将来按
//     方案 §8 清探针时只动一个文件。
//
// 【为什么这里不是 @ObservedV2】
// 整簇只有两个字段（prependRestoreSeq、anchorCaptureOffset），都是无装饰器的
// 普通 number，**ChatPage.build() 对它们的读点是 0 处**。没有 @Local → @Trace
// 的转换可做，没有宿主 @Param 面可收，也没有任何子组件消费本簇的状态——它是
// 纯副作用簇，产出是对 Scroller 发指令，不是渲染。所以本类是**普通类**，
// 与 AttachActions（B12）、MediaSaveState（B15）同一个判断：字段不加 @Trace，
// 类里不声明 @Monitor。加 @ObservedV2 只是给一个零渲染状态的类套响应式外壳。
//
// 【因此本批没有 perf 项】
// 重渲染半径的收窄是**可证明的 0**。收益只有两条：ChatPage 少约 215 行；
// 执行层从"没有任何本地手段"变成"四个分支有单测"。第二条才是这批的正当性
// 来源——见 entry/src/test/ScrollAnchorController.test.ets。
//
// 【方法名保持原样，没有改短】
// 评审建议把三个入口改叫 restorePrepend / restoreAppend / captureOffset。这里
// 没有采纳：ChatPage.ets:2974 等处的注释、以及这一簇十个 commit 的历史都按原名
// 索引（556c5fa → 351dab9 → 720a485(revert) → 0b62293 → ca5bde9 → ecce2fd →
// 32064be → 63ccaf0 → da6f52f → 90f75ad）。`anchor.restorePrependAnchor(...)`
// 读起来重复一点，换来的是注释不漂移、grep 不断链。
//
// 【顺带修好一处注释粘连】
// 原文件里 anchorItemY 的文档注释（"锚点采样：第 index 行相对 List 顶的 y"）
// 和 anchorCaptureOffset 的注释是**连在一起**的，中间还夹着 anchorCaptureOffset
// 的字段声明，读起来像在讲同一件事。这次按真实归属切开：前半留在页面跟着
// anchorItemY，后半随字段搬到这里。两段文字本身都没有改动。

import { AlbumGroup, groupIndexOf } from '../../util/collapseAlbums';
import { logE, logW } from '../../util/log';
import { LengthMetrics } from '@kit.ArkUI';
import {
  ANCHOR_RESTORE_DELTA, ANCHOR_RESTORE_RETRY_MS, AnchorRectSnapshot, AnchorRestorePlan,
  anchorYAfterUserScroll, canApplyAnchorRestore, shouldRetryAnchorRestore,
  INVALID_ANCHOR_RECT, planAnchorRestore
} from '../../util/anchorRestore';

// 宿主（ChatPage）暴露给控制器的那一小片接口，全是箭头函数字段——取值器读页面
// 当下的真值，本类不缓存。仿 MediaSaveStateHost / AttachActionsHost。
//
// **七个成员，全部只读，零动作回调。** 本控制器对页面状态零写入：它只借
// scroller 发滚动指令，只读四个共享滚动真源。这符合不变量 10 的"控制器只经
// host 的箭头函数 getter 只读访问"。对照现有控制器：JumpFlashStateHost 3、
// MediaSaveStateHost 6、MembershipSessionHost 9——7 落在既有区间里，且是唯一
// 一个一个动作回调都没有的。
export interface ScrollAnchorHost {
  // 时间线 List 的 Scroller。getItemRect / scrollBy / scrollToIndex /
  // currentOffset 四个调用都经它。
  scroller: () => Scroller;
  // onDidScroll 累计的真实手势位移。**每次触发时现取**，不是 bind 时快照——
  // restoreScrollAnchor 里那句三元（userOffsetAtCapture 为 NaN 时取当下值）
  // 和 attemptAnchorRestore 里的 userDelta 都依赖这一点。
  userScrollOffsetTotal: () => number;
  // 用户此刻是否正在拖动/惯性滚动。canApplyAnchorRestore 的第一个入参。
  timelineScrollActive: () => boolean;
  // 手指是否仍按在时间线上。onScrollStop 可能先于 TouchType.Up 到达；仅看
  // timelineScrollActive 会让 fallback 在这段空窗里发 scrollToIndex。
  touchActive: () => boolean;
  // 更强的定位意图：有待处理的跳转目标。非 0 时本簇让路（早退）。
  pendingJumpId: () => number;
  // 更强的定位意图：有待处理的"回到底部"。true 时本簇让路（早退）。
  //
  // 与 pendingJumpId 刻意**保持两个成员**，没有按 shouldHoldAppendAnchor 的
  // 先例合成一个 scrollIntentPending()。合了接口数字好看（6 个），但那是语义
  // 折叠，违背逐字搬迁纪律；早退那一行的判据也就不再和原文一一对应了。
  pendingScrollBottom: () => boolean;
  // 顶部 chrome 让出的留白高度（.contentStartOffset 用的同一个值）。
  // reposition 分支的 extraOffset 要实时值，不能取常数——依据是 2026-08-30
  // 真机日志里 residual 153/153/153/770 那组数（见 attemptAnchorRestore）。
  headerChromeHeight: () => number;
  // 时间线视口的高度。canApplyAnchorRestore 用它给"滑动中允许多大的修正"定尺：
  // 一屏以内的残差补回去看不出接缝，多屏的会把惯性打断成整页跳。
  //
  // **走 host 而不是直接读 AppStorage**：读全局会让本类的单测依赖执行顺序
  // （别的用例先跑过才有 screenHeightVp），拿不到就退化成"滑动中一律不修"，
  // 那等于悄悄回到旧行为还测不出来。
  viewportHeight: () => number;
  // 对应页面的 appendAnchorGateProbe(groups)。**让探针连同它自己那 10 处读点
  // 整体留在页面**，是这份接口能停在 7 个的关键：不这么切的话
  // viewerMsgId / imeTailPinned / curStartIdx / curEndIdx / indexGroupsLen /
  // atBottom / listTouchActive / listUserScrollActive / newerGate / store
  // 十个共享滚动真源全要开取值器，接口直接变 17 个。
  appendGateProbe: (groups: AlbumGroup[]) => string;
}

export class ScrollAnchorController {
  // 一次分页最多修正一次；跳转/贴底这类更强的定位意图会作废它（invalidate）。
  private prependRestoreSeq: number = 0;

  // 锚点采样那一刻的滚动偏移。**只用于诊断，不参与 dy 的计算**。
  //
  // 为什么不直接拿它做修正项：anchorRestore 的 dy = rect.y - itemY 里确实缺一个
  // 「采样到测量之间用户自己滑了多少」的项（翻页本来就是滑动触发的，这段时间列表
  // 在动），补上它才不会把用户的位移反向抵消。但 currentOffset() 在**前插**场景
  // 下不可信：官方对未提供 childrenMainSize 的懒加载 List 明确注明总偏移量
  // 是估算值，前插一页会把新行的估算高度混进 yOffset。这里刻意不把动态媒体
  // 高度绑定回 List（见 ChatTimelineHost），所以锚点恢复沿用 onDidScroll 累计的
  // 真实手势位移：它天然排除了数据发布造成的位置变化，语义更窄。
  //
  // 所以这一版只把两次读数打进 [AnchorRestore]：真机上先看 dOff 与 dy 的关系，
  // 再决定修正项该怎么取（或者改用 onDidScroll 累计位移）。行为一个字没改。
  private anchorCaptureOffset: number = Number.NaN;

  captureAnchorOffset(): void {
    try {
      this.anchorCaptureOffset = this.host.scroller().currentOffset().yOffset;
    } catch (e) {
      this.anchorCaptureOffset = Number.NaN;
    }
  }

  private currentAnchorOffset(): number {
    try {
      return this.host.scroller().currentOffset().yOffset;
    } catch (e) {
      return Number.NaN;
    }
  }
  // 未 bind 时的空宿主：字段类型非空，且控制器在 aboutToAppear 之前就已经被
  // 构造出来（页面的字段初始化器 new）。这里的占位值只在"页面还没 bind 就有人
  // 调进来"时才会被读到，而本簇的入口全部由消息快照/恢复落位触发，严格晚于
  // bind()。scroller 用一个新建的未绑定 Scroller 占位——它的方法在未绑定组件时
  // 会抛，正好落进各处已有的 try/catch。
  private host: ScrollAnchorHost = {
    scroller: (): Scroller => new Scroller(),
    userScrollOffsetTotal: (): number => 0,
    timelineScrollActive: (): boolean => false,
    touchActive: (): boolean => false,
    pendingJumpId: (): number => 0,
    pendingScrollBottom: (): boolean => false,
    // 0 = 量不到，canApplyAnchorRestore 因此在滑动中一律不修（最保守）。
    viewportHeight: (): number => 0,
    headerChromeHeight: (): number => 0,
    appendGateProbe: (_groups: AlbumGroup[]): string => ''
  };

  // ChatPage.aboutToAppear 里调一次。
  bind(host: ScrollAnchorHost): void {
    this.host = host;
  }

  // 作废当前这一轮复位。对应原来页面里那两处裸的 `this.prependRestoreSeq++;`
  // （resetScrollSession 与 disposeTimersAndSeqGuards），两处都原位替换、各调
  // 一次，**没有合并成一次 dispose()**——它们各自夹在 jumpLayoutSeq++ 与下一行
  // 之间，位置就是不变量 6 说的"原字段清理位置"。
  //
  // **不做 clearTimeout。** 现行实现故意不持定时器句柄：已排队的回调仍会触发，
  // 靠 attemptAnchorRestore 开头那句 seq 比对空转返回。invalidate() 只做 ++。
  invalidate(): void {
    this.prependRestoreSeq++;
  }

  // A history page is inserted before the current window. Keep the exact
  // message and its partial row offset under the user's finger; the newly
  // loaded rows should only appear as they continue scrolling upward.
  restorePrependAnchor(
    groups: AlbumGroup[], messageId: number, itemY: number,
    userOffsetAtCapture: number = Number.NaN, primeBeforeLayout: boolean = false
  ): void {
    const targetIndex: number = groupIndexOf(groups, messageId);
    if (targetIndex < 0) {
      return;
    }
    this.restoreScrollAnchor(targetIndex, itemY, userOffsetAtCapture, primeBeforeLayout);
  }

  // A newer page is appended after the current window. The list is
  // end-anchored (stackFromEnd), so the append alone pushes the visible content
  // upward; put the same message back under the user's finger.
  restoreAppendAnchor(
    groups: AlbumGroup[], messageId: number, itemY: number,
    userOffsetAtCapture: number = Number.NaN
  ): void {
    const targetIndex: number = groupIndexOf(groups, messageId);
    if (targetIndex < 0) {
      return;
    }
    this.restoreScrollAnchor(targetIndex, itemY, userOffsetAtCapture);
  }
  // 把锚点行按回 itemY。两级，判据是纯函数 util/anchorRestore.planAnchorRestore：
  //
  //   · 行还在显示区（getItemRect 给得出有效矩形）→ 只补一次 scrollBy(0, dy)，
  //     dy = 新量到的 y - 记下的 y。**不调 scrollToIndex**：那一句会让 List 从
  //     给定下标起全量重测，真机 Frame trace 里 ScrollToIndex(index=9) 对应的
  //     正是录制中最大的那几个尖峰。
  //   · 取不到有效矩形（行已滑出显示区）→ 重试三次后用一次带 extraOffset 的
  //     scrollToIndex(START) 定位，避免旧路径两步滚动造成可见闪动。
  //
  // 时机沿用原来的 setTimeout(0)：数据已发布、框架也已经跑完一次布局，此时
  // getItemRect 量到的才是新快照下的位置。prependRestoreSeq 代次守卫不动——一
  // 次分页最多修正一次，跳转/贴底这类更强的定位意图仍然作废它。
  //
  // **量不到时别急着兜底。** 真机上往上翻历史，setTimeout(0) 那一刻新快照还没排版，
  // getItemRect 拿到全 0，每次都走了 scrollToIndex+scrollBy 兜底；它按 List 顶端对齐，
  // 没算 contentStartOffset 那段顶栏留白，把视口往下推了一截（用户：18:00 → 18:05）。
  // 而框架（maintainVisibleContentPosition / stackFromEnd）其实已经把位置保住了。
  // 现在量到就补差值，量不到就下一帧再量（最多三次），用尽仍量不到再做一次
  // 不依赖测量的定位——依据见 attemptAnchorRestore 里那段真机 A/B 数据。
  restoreScrollAnchor(
    targetIndex: number, itemY: number,
    userOffsetAtCapture: number = Number.NaN, primeBeforeLayout: boolean = false
  ): void {
    const capturedUserOffset: number = Number.isNaN(userOffsetAtCapture)
      ? this.host.userScrollOffsetTotal() : userOffsetAtCapture;
    const seq: number = ++this.prependRestoreSeq;
    if (primeBeforeLayout) {
      const extra: number = -itemY + this.host.headerChromeHeight();
      try {
        this.host.scroller().scrollToIndex(targetIndex, false, ScrollAlign.START,
          { extraOffset: LengthMetrics.vp(extra) });
      } catch (e) {
        logE(`ChatPage.primeAnchor failed: ${e}`);
      }
    }
    this.attemptAnchorRestore(seq, targetIndex, itemY, capturedUserOffset, 0);
  }

  private attemptAnchorRestore(
    seq: number,
    targetIndex: number,
    itemY: number,
    userOffsetAtCapture: number,
    attempt: number
  ): void {
    setTimeout((): void => {
      if (seq !== this.prependRestoreSeq || this.host.pendingJumpId() !== 0 || this.host.pendingScrollBottom()) {
        return;
      }
      const userDelta: number = this.host.userScrollOffsetTotal() - userOffsetAtCapture;
      const targetY: number = anchorYAfterUserScroll(
        itemY, userOffsetAtCapture, this.host.userScrollOffsetTotal());
      // 非法下标返回全 0 矩形（faqs-arkui-572），异常按同样处理——两条都落到
      // planAnchorRestore 的 fallback 支。
      let rect: AnchorRectSnapshot = INVALID_ANCHOR_RECT;
      try {
        const measured = this.host.scroller().getItemRect(targetIndex);
        rect = { width: measured.width, height: measured.height, y: measured.y };
      } catch (e) {
        rect = INVALID_ANCHOR_RECT;
      }
      const plan: AnchorRestorePlan = planAnchorRestore(rect, targetY);
      // 量不到就下一帧再量，最多 ANCHOR_RESTORE_ATTEMPTS 次；用尽仍量不到才
      // 进入下面的一步式 scrollToIndex 定位。判据与完整推导见 util/anchorRestore
      // 的 shouldRetryAnchorRestore。
      //
      // 【这里曾经只量一次，是个回归】ecce2fd 依据一场会话「attempt=0 成功
      // 83/90、非零 dy 全在重试支」判定「能量到时没用、量不到时有害」，于是删掉
      // 重试。2026-08-29 的真机日志推翻了这个前提：那份日志跨了两个构建、分界
      // 干净，等于一次天然 A/B ——
      //   · 有重试的那半：60 次复位一次都没落空（量到 47 / 重试后量到 11 / 兜底 2）；
      //   · 只量一次的那半：31 次复位里**放弃 22，占 71%**，且 attempt=0 的成功率
      //     从 78% 掉到 29%。
      // 差别在场景轻重：媒体重的频道排版慢，setTimeout(0) 那一刻新快照还没排完
      // 版，getItemRect 必然全 0（ca5bde9 查明的现象）。用户在后半段报「刚点进新
      // 频道动一动就跳了好几下，进来看的消息也找不到了」——一次向上翻页连灌 6 页
      // 30 行，六次前插的补偿全部放弃。
      //
      // ca5bde9 证实旧的两步兜底没算 contentStartOffset，会把视口整体往下推；
      // 下面的一步式定位会同时补上实时的顶部留白。
      if (shouldRetryAnchorRestore(plan.mode, attempt)) {
        this.attemptAnchorRestore(seq, targetIndex, itemY, userOffsetAtCapture, attempt + 1);
        return;
      }
      // ── 能不能真的动 ────────────────────────────────────────────────
      //
      // **闸在这里，不在函数开头**：判据是"这次要修多少"，而修多少要等
      // planAnchorRestore 算完才知道。原来在开头按"用户在不在滑"拦，把采样侧
      // "即使用户仍在滑也要记锚点"的意图整个作废了（见 util/anchorRestore
      // 的 canApplyAnchorRestore 与真机证据）。
      //
      // fallback 支给 Infinity：它走的是 scrollToIndex 一步定位，惯性中就是硬跳，
      // 所以滑动时一律不做；静止时不受限制（canApplyAnchorRestore 里 !scrollActive
      // 直接放行）。
      const correction: number = plan.mode === ANCHOR_RESTORE_DELTA
        ? plan.dy : Number.POSITIVE_INFINITY;
      const viewportH: number = this.host.viewportHeight();
      if (plan.mode !== ANCHOR_RESTORE_DELTA && this.host.touchActive()) {
        return;
      }
      if (!canApplyAnchorRestore(
        this.host.timelineScrollActive(), userDelta, correction, viewportH)) {
        return;
      }
      if (plan.mode !== ANCHOR_RESTORE_DELTA) {
        // ── 量不到时**不能放弃**，改用不依赖测量的定位 ─────────────────────
        //
        // API 20 起 maintainVisibleContentPosition 已支持 Repeat.virtualScroll，
        // 普通区外前插由框架保位；能走到这里的是边界可见行因 key 改变而被替换的
        // 兜底。若期间用户开始拖动，targetY 已扣除捕获锚点后的真实用户滚动量，
        // 因此只修正数据刷新造成的位移，不会把手势或惯性滚动拉回去。
        //
        // 真机 [AnchorAudit] 也把这件事钉死了：五次 give-up 的 offDelta 分别是
        // 8/-2/41/0/126（用户没在滑），而 250ms 后锚点行**仍然不在屏上**——滚动
        // 偏移原地不动、内容却在它上面插进了 30 行。那就是用户看到的"乱跳"。
        //
        // 【为什么用 scrollToIndex + extraOffset】量不到恰恰是因为视口已经跑掉、
        // 那一行不在显示区里；再重试多少次也量不回来（三次尝试后依旧 w=0 h=0）。
        // 这个重载（API 12+）不需要先量：直接把第 idx 行按 START 对齐，再偏移
        // extraOffset。一次调用完成，不像旧兜底那样 scrollToIndex 再 scrollBy 分两步
        // 走（那一步之间是看得见的）。
        //
        // 【extraOffset 取 -targetY 的依据】旧兜底那两句是
        //   scrollToIndex(idx, false, START); scrollBy(0, -targetY);
        // START 之后行的 y 是 0，要把它挪回 targetY 正是 scrollBy(0, -targetY)。
        // targetY 已包含捕获后的用户滚动量，这里把两步合成一步。
        //
        // 【+ headerChromeHeight() 是量出来的，不是推的】ScrollAlign.START 按 List
        // 的顶端对齐，而顶部 chrome 是用 contentStartOffset 让出来的一段留白
        // （见 .contentStartOffset(this.headerChromeHeight())），START 不算它，行就
        // 落低了整整那一段——ca5bde9 当年"视口被往下推了一截"就是这个。
        //
        // 上一版故意没加这个修正，改由 [AnchorAudit] 的 residual 去量。2026-08-30
        // 的真机日志给出答案：四次 reposition 的 residual 是 153/153/153/770，
        // 前三次**精确等于**当时的顶栏高度（同份日志里 [Jump80] flash 的 top 也一直
        // 是 153），符号是"行落得偏低"，所以往回补正的量。第四次 770 是顶栏更高的
        // 状态（置顶条/通话条会把它撑高），所以这里取**实时值**而不是常数。
        const extra: number = -targetY + this.host.headerChromeHeight();
        // RepoProbe 的 net 指标已摘除（2026-09-11 被驳回，驳得对）：它拿
        // currentOffset() 的前后差做判据，而官方明说懒加载 List 未提供
        // childrenMainSize 时总偏移量是估算值，本文件 109 行的注释早就记着
        // 「currentOffset() 在前插场景下不可信」。后续判读用的是可见首行的
        // **消息身份轨迹**（临时探针，已删；结论见记忆 mvcp-splice-publish-root-cause）。
        try {
          this.host.scroller().scrollToIndex(targetIndex, false, ScrollAlign.START,
            { extraOffset: LengthMetrics.vp(extra) });
        } catch (e) {
          logE(`ChatPage.repositionAnchor failed: ${e}`);
        }
        return;
      }
      // capOff/nowOff/dOff 只是诊断：dOff 是采样到本次测量之间滚动偏移的变化。
      // 它同时混着「用户自己滑的」和「插入内容的估算高度」，**不参与 dy**，
      // 用途是回答「dy 里到底有多少是在抵消用户的滑动」。见 anchorCaptureOffset。
      const nowOff: number = this.currentAnchorOffset();
      const dOff: number = Number.isNaN(this.anchorCaptureOffset) || Number.isNaN(nowOff)
        ? Number.NaN : nowOff - this.anchorCaptureOffset;
      if (plan.dy !== 0) {
        this.host.scroller().scrollBy(0, plan.dy);
      }
    }, attempt === 0 ? 0 : ANCHOR_RESTORE_RETRY_MS);
  }
}
