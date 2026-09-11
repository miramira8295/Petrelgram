// 播放位竞选簇（第二轮第 7 项，R2-C）：滚动停下后选出唯一播放/下载的视频
// 气泡，并在气泡与全屏查看器之间交接播放进度。从 ChatPage 搬出**机件与时序
// 契约**，不搬状态。
//
// 【这一批搬的是什么，为什么不是"算法"】
// 算法早就搬完了：PlaySlotRegistry.ets（246 行，24 条单测钉着）、
// playSlot.ets（98 行）、util/messageBubblePrepare.ets 都已经是独立文件。
// ChatPage 里剩下的一百多行**全部是闸门、定时器与顺序契约**——正是最容易在
// "看起来等价"的改写里悄悄坏掉、又最没有本地手段能发现的那一类。所以本批的
// 目标不是行数，是把三条契约结构性地封死：
//   1. 起播位置必须在 playSlotKey 之前落下（applySlot 做成**一个动作**）；
//   2. 取进度必须在 suspend() 之前（handoffToViewer 内部化）；
//   3. clearSlotTick 与 suspend/reset 的先后（收进 clearTick/suspend/dispose）。
//
// 【重渲染半径：0 变化，两个 @Local 原地不动】
// playSlotKey / playSlotStartMs 的读点在 albumReuseShape() 与 rowPlaySlotKey()，
// 经 prepareMessageBubble() 落到 build() 的行 builder 里。不变量 1 冻结了
// prepareMessageBubble 及其 cacheKey，只允许 this.x → this.ctrl.x 的等价替换，
// 依赖粒度不变——就算把两个 @Local 变成本类的 @Trace，读点还在同一个节点，
// ArkUI V2 在同一处登记依赖，半径一模一样。而且有反向代价：
// messageBubblePrepare.ets 文件头写明那两个包装"每行每帧各调一次，是消息行
// 的热路径"，换成跨对象属性访问是在热路径上加一跳，只有坏处。
// **所以两个 @Local 留在页面**，本类不持有任何响应式字段，是普通类，
// 不加 @ObservedV2（与 AttachActions / MediaSaveState / ScrollAnchorController 一致）。
//
// 【这一簇是 MediaViewer 那批的前置，不是它的并列项】
// bubblePositionMs 与 playSlots.pin() 这两个真源今天被 MediaViewer 簇跨域直写。
// 先搬播放位，MediaViewer 的 3 条跨域写通道就能少 1 条。反过来先搬 MediaViewer
// 是错的。
//
// 【[PlaySlot] 打点是本批的前置条件，不是附带品】
// 这一簇在此前的 hilog 黄金样本里**一个标签都没有**——改坏了没有任何自动
// 手段能发现。所以 applySlot 落位、两处查看器交接、suspend/resume/reset 三个
// 分支都各打一条，capture-hilog-golden.sh 的 TAGS 同步加了 PlaySlot。
// 没有这些打点，下面所有搬迁的验收答案都是"没有"。

import { PlaySlotRegistry } from './PlaySlotRegistry';
import { slotKeyMessageId } from './playSlot';
import { logW } from '../../util/log';

// 宿主（ChatPage）暴露给本类的接口。**四个成员，其中只有一个是写通道**——
// 这是第二轮至今最小的一份（锚点复位 7、MediaSaveState 6、MediaViewer 13–15、
// 发送链 23–27）。
export interface PlaySlotHost {
  // 全屏查看器当前展示的消息 id，0 表示没开。armSettle 与 reportMedia 的闸门
  // 都读它。它是页面的 @Local 且被 @Monitor('viewerMsgId') 监听，只能留页面。
  viewerMsgId: () => number;
  // 页面自身是否可见（普通私有字段，不是 @Local）。
  pageVisible: () => boolean;
  // 播放位竞选的总闸门。**故意不把 powerSaving/reduceAnimations/autoplayVideo
  // 三个 @Param 搬进来**：页面自己调 shouldCompete(...) 算好交出结果，仿
  // JumpFlashStateHost 的 effectDuration 先例（它同样把这三个 @Param 挡在
  // 控制器外面）。这一条同时满足不变量 9「控制器不缓存 @Param」。
  competeEnabled: () => boolean;
  // **唯一的跨域写通道**：写页面的 @Local playSlotStartMs 与 @Local playSlotKey。
  //
  // 做成**一个动作**而不是两个 setter，是为了把"起播位置必须在 playSlotKey
  // 之前落下"这条顺序契约，结构性地封死在页面那一侧的一个函数体里。原注释：
  // 「气泡是靠 playSlotKey 的变化才挂载 VideoBubbleSurface 的，晚一步这条
  // 播放器就已经从 0 开始了」。拆回两个 setter，或者把顺序写反，故障是静默的
  // ——不崩不报，只是每次从全屏查看器退回来的那条视频都从头播。
  applySlot: (key: string, startMs: number) => void;
}

export class PlaySlotDriver {
  // 候选表与当选逻辑（算法本体在 PlaySlotRegistry.ets，已有 24 条单测）。
  private playSlots: PlaySlotRegistry = new PlaySlotRegistry();
  private slotTickTimer: number = -1;
  // 气泡播放位的播放进度，按 messageId 记录。onPlaySlotPositionChanged 是
  // 350ms 一次的高频回调，故意用普通 Map 而不是 @Local/AppStorage——
  // 写状态会让消息列表每 350ms 重建一次。打开全屏查看器时读它作为
  // startPositionMs，关闭查看器时把最终进度写回。整个会话关闭时清空
  // （见 dispose），避免无界增长。
  private bubblePositionMs: Map<number, number> = new Map<number, number>();

  private host: PlaySlotHost = {
    viewerMsgId: (): number => 0,
    pageVisible: (): boolean => false,
    competeEnabled: (): boolean => false,
    applySlot: (_key: string, _startMs: number): void => {}
  };

  // ChatPage.aboutToAppear 里调一次，必须在 subscribe() 之前。
  bind(host: PlaySlotHost): void {
    this.host = host;
  }

  // 订阅换届通知。返回退订函数，由页面存进它自己的 subscriptions 注册表
  // （键仍是 'playSlot'，clearInOrder 的三组顺序不动——不变量 6）。
  subscribe(): () => void {
    return this.playSlots.subscribe((key: string): void => {
      const startMs: number = key === ''
        ? 0 : (this.bubblePositionMs.get(slotKeyMessageId(key)) ?? 0);
      // 一个动作，顺序封在页面那一侧的实现里。见 PlaySlotHost.applySlot。
      this.host.applySlot(key, startMs);
    });
  }

  // ——— 气泡侧的四个上报口 ———

  // 守卫：查看器开着、或页面不可见、或总闸门关着，一律不喂。List/气泡全程
  // 挂载，这两种状态下即便候选表被后台悄悄填回来，也绝不能真的选出播放位去
  // 挂播放器/拉下载（分别是 Critical-2 和 Important-3 的核心不变量）。
  // 三重闸门缺一不可：少一项，查看器打开期间气泡播放器仍在跑，同一个文件
  // 两个播放器互抢下载分片。
  reportMedia(messageId: number, albumIndex: number, ratio: number, centerY: number): void {
    if (this.host.viewerMsgId() !== 0 || !this.host.pageVisible() || !this.host.competeEnabled()) {
      return;
    }
    const now: number = Date.now();
    this.playSlots.report(messageId, albumIndex, ratio, centerY, now);
    this.maybeScheduleNextSlotCheck(now);
  }

  dropMedia(messageId: number, albumIndex: number): void {
    this.playSlots.drop(messageId, albumIndex);
  }

  recordPosition(messageId: number, positionMs: number): void {
    this.bubblePositionMs.set(messageId, positionMs);
  }

  retire(messageId: number, albumIndex: number): void {
    const now: number = Date.now();
    this.playSlots.retire(messageId, albumIndex, now);
    this.maybeScheduleNextSlotCheck(now);
  }

  setViewportCenter(centerY: number): void {
    this.playSlots.setViewportCenter(centerY);
  }

  // ——— 定时器闭环 ———

  // 驻留判定是逐候选的，onVisibleAreaApproximateChange 只在跨阈值时触发——
  // 一条视频稳稳停着反而不再有任何回调，所以判定不能只靠回调推动。这里用
  // PlaySlotRegistry.nextCheckDelay() 查询"还有候选没攒满 PLAY_SLOT_DWELL_MS"，
  // 有就排一个一次性定时器，到点再 tick() 一次；没有就什么也不做。
  // scheduleSlotTick 只留一个在途定时器，重复调用安全。
  private scheduleSlotTick(delayMs: number): void {
    this.clearTick();
    this.slotTickTimer = setTimeout((): void => {
      this.slotTickTimer = -1;
      const now = Date.now();
      this.playSlots.tick(now);
      this.maybeScheduleNextSlotCheck(now);
    }, delayMs + 10);
  }

  clearTick(): void {
    if (this.slotTickTimer !== -1) {
      clearTimeout(this.slotTickTimer);
      this.slotTickTimer = -1;
    }
  }

  // nextCheckDelay() < 0 表示没有候选正在攒驻留（要么无候选达标，要么都已
  // 达标或已经是现任/被 pin），此时什么也不用排。
  private maybeScheduleNextSlotCheck(now: number): void {
    const delay = this.playSlots.nextCheckDelay(now);
    if (delay >= 0) {
      this.scheduleSlotTick(delay);
    }
  }

  // 幂等的"补一次判定"：可以随便重复调用，不需要一次性 flag 挡着。立即跑
  // 一次 tick（用于候选表在此刻已经攒够驻留、只是没有新的可见区回调触发
  // 判定的情况，比如 onPageShow/closeViewer 这类没有新 ratio 上报的恢复路
  // 径），再排一次后续检查。调用点见 driveVisibleWork()/onScrollIndex()/
  // onPageShow()/closeViewer()——任何一次因为候选表还没填满（消息还没到、
  // ratio 还没上报、被查看器盖住清空过）而选不出播放位，都会被下一次自然
  // 发生的调用或已排的定时器补上，不会永久卡死。
  //
  // 守卫：查看器开着，或页面本身不可见时，直接不喂——理由同 reportMedia。
  // closeViewer()/onPageShow() 这两条恢复路径都是先把状态改回"已关闭/
  // 可见"再调这个方法，守卫在它们那次调用里天然放行。
  armSettle(): void {
    if (this.host.viewerMsgId() !== 0 || !this.host.pageVisible() || !this.host.competeEnabled()) {
      return;
    }
    const now = Date.now();
    // 恢复路径（closeViewer / onPageShow）走到这里时候选表还在（suspend()
    // 保留了它），只是驻留计时被清了；resume() 按此刻重新起算，之后正常
    // 攒满 PLAY_SLOT_DWELL_MS 就能自然选出播放位，不需要用户手动滑一下。
    // 非恢复路径上 resume() 是空操作（见 PlaySlotRegistry.resume）。
    logW('[PlaySlot] resume');
    this.playSlots.resume(now);
    this.playSlots.tick(now);
    this.maybeScheduleNextSlotCheck(now);
  }

  // 总闸门关掉：立刻把正在播的那条停掉。reset() 会把播放位置空，订阅者把
  // playSlotKey 清成 ''，气泡的 VideoBubbleSurface 随之卸载 →
  // StreamingVideoPlayer.aboutToDisappear → release() → session.close()，
  // 播放和下载一起停。
  onPolicyDisabled(): void {
    logW('[PlaySlot] reset reason=policy-off');
    this.clearTick();
    this.playSlots.reset();
  }

  // 页面隐藏/将要隐藏：候选表要留着，只停计时与播放。用 suspend() 而不是
  // reset()，理由见 handoffToViewer。
  suspend(): void {
    logW('[PlaySlot] suspend');
    this.playSlots.suspend();
  }

  // ——— 与全屏查看器的两处交接 ———

  // 气泡 → 查看器。返回查看器应当从哪一毫秒起播。
  //
  // 三步的顺序被封在这里：**先取进度、再停计时、最后 suspend**。原注释：
  // 取进度必须在 playSlots.suspend() 让气泡播放器卸载之前完成——
  // bubblePositionMs 本身不受 suspend() 影响，但卸载之后气泡播放器不会再有
  // 新的 onPositionChanged，读早读晚不影响这一次的值；保险起见仍然按
  // "先取、后卸载"的顺序写。
  //
  // 全屏查看器是页内叠层，不是新页面，不会触发 onPageHide——List 和气泡照样
  // 挂着，onVisibleAreaApproximateChange 只算几何不算遮挡，ratio 不变就不会
  // 自己释放播放位。不在这里主动停掉，播放位气泡的播放器会和查看器自己的
  // 播放器同时跑、同一个文件还可能互抢下载分片。
  // 用 suspend() 而不是 reset()：候选表要留着，否则关闭查看器后几何没变、
  // 没有任何新的 ratio 上报，列表就再也选不出播放位（"哑掉"）。
  handoffToViewer(messageId: number): number {
    const startPositionMs: number = this.bubblePositionMs.get(messageId) ?? 0;
    this.clearTick();
    this.playSlots.suspend();
    return startPositionMs;
  }

  // 查看器 → 气泡。把查看器最终播放到的位置写回气泡进度表，并把这条 pin 成
  // 播放位——用户刚看完的这条回到列表后应当继续播。
  //
  // **调用点必须留在 closeViewer 里 animateTo 之前。** @Monitor('viewerMsgId')
  // onViewerTargetChanged 会在 viewerMsgId 归零的那一刻同步把 viewerPositionMs
  // 清成 0，顺序一错 bubblePositionMs 就永远记 0。这是本簇与 MediaViewer 簇
  // 之间唯一的隐式时序耦合。
  //
  // pin 是有时效的（PLAY_SLOT_PIN_TTL_MS）：只为「刚看完的这条回到列表后
  // 接着播」服务，过期后它跟别的候选一样要重新攒够驻留才能当选。
  handoffFromViewer(messageId: number, albumIndex: number, positionMs: number): void {
    this.bubblePositionMs.set(messageId, positionMs);
    this.playSlots.pin(messageId, albumIndex, Date.now());
  }

  // 会话退场。三句顺序照抄原 disposePlaybackAndSlots：停计时 → 清候选表 →
  // 清进度表。进度表只在这一次会话内有意义（交接回全屏查看器/回到播放位），
  // 会话结束就清空，避免长会话里随刷屏无界增长。
  dispose(): void {
    logW('[PlaySlot] reset reason=dispose');
    this.clearTick();
    this.playSlots.reset();
    this.bubblePositionMs.clear();
  }
}
