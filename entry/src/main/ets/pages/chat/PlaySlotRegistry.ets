import {
  PlaySlotCandidate, pickPlaySlot, slotKey, PLAY_SLOT_ENTER_RATIO, PLAY_SLOT_KEEP_RATIO
} from './playSlot';

// 候选表 + 「视觉驻留才判定」的闸门。
//
// 判定主体是单个候选，不是整个列表：某条视频在视野里自己稳住了就该起播，
// 与列表是否仍在滚动无关——视觉停留不是滑动停留。每个候选各自维护一个
// stableSince：从它首次达到入选线（PLAY_SLOT_ENTER_RATIO）的那一刻起计时，
// 一旦某次上报的 ratio 掉到入选线以下，这个候选的 stableSince 清零重来。
// 只有连续达标满 PLAY_SLOT_DWELL_MS 的候选才有资格参与竞选新任——现任的
// 迟滞连任（见 pickPlaySlot）不受驻留门槛约束，否则在播的那条每次 ratio
// 抖动都要重新攒 400ms。
//
// 400ms 的由来：气泡用 onVisibleAreaApproximateChange({ expectedUpdateInterval:
// 200 }) 限频上报可见比例，两个上报周期才算「真的稳住了」，一次性的抖动
// 不算。慢速滑动时某条稳稳占了大半屏数百毫秒 → 起播；快速滑过时某条短暂
// 全屏可见 → 连续驻留凑不满 400ms → 不起播。「滑动中不乱播」是驻留判据的
// 自然结果，不需要额外的滚动闸门。
//
// 释放不等任何计时：已在播的那条一旦 ratio < PLAY_SLOT_KEEP_RATIO 或从候选
// 表消失，立刻释放，见 releaseIfGone()。
//
// 时间由外部注入（report(..., now) / tick(now)），不在内部读时钟，这样整套
// 时序都能单测。
export const PLAY_SLOT_DWELL_MS: number = 400;

// 手动锁定（pin）的有效期。pin 让一条视频绕过驻留门槛立即当选，这是为
// 「刚从全屏查看器退回来的那条应该接着播」准备的短期特权，不是永久的：
// 没有时效的话，用户看完全屏退出、把列表滑到别处、十分钟后再快速滑回来，
// 那条会在刚跨过保持线的瞬间零驻留起播 —— 正是驻留判据要防的抖动。
// 超时后 pin 自动失效，该条回到正常的驻留规则。
export const PLAY_SLOT_PIN_TTL_MS: number = 30000;

export type PlaySlotListener = (key: string) => void;

export class PlaySlotRegistry {
  private candidates: Map<string, PlaySlotCandidate> = new Map();
  // 候选 key -> 它连续满足入选线的起始时刻；不在这个表里的候选要么从未达标，
  // 要么上一次上报已经跌破入选线（见 report()）。
  private stableSince: Map<string, number> = new Map();
  private listeners: PlaySlotListener[] = [];
  private slot: string = '';
  private pinned: string = '';
  // pin 落下的时刻，用于 PLAY_SLOT_PIN_TTL_MS 过期判定（时间外部注入）。
  private pinnedAt: number = 0;
  private viewportCenterY: number = 0;
  // suspend() 与 resume() 之间为 true：候选表仍在，但不选任何播放位。
  private suspended: boolean = false;

  subscribe(listener: PlaySlotListener): () => void {
    this.listeners.push(listener);
    return (): void => {
      const at = this.listeners.indexOf(listener);
      if (at >= 0) {
        this.listeners.splice(at, 1);
      }
    };
  }

  current(): string {
    return this.slot;
  }

  setViewportCenter(centerY: number): void {
    this.viewportCenterY = centerY;
  }

  report(messageId: number, albumIndex: number, ratio: number, centerY: number, now: number): void {
    const key = slotKey(messageId, albumIndex);
    this.candidates.set(key, { key, messageId, albumIndex, ratio, centerY });
    if (ratio >= PLAY_SLOT_ENTER_RATIO) {
      // 只在首次达标时落下计时起点；已经在计时的不重置，否则永远攒不满。
      if (!this.stableSince.has(key)) {
        this.stableSince.set(key, now);
      }
    } else {
      this.stableSince.delete(key);
    }
    this.releaseIfGone();
    this.elect(now);
  }

  drop(messageId: number, albumIndex: number): void {
    const key = slotKey(messageId, albumIndex);
    this.candidates.delete(key);
    this.stableSince.delete(key);
    this.releaseIfGone();
  }

  isPinned(messageId: number, albumIndex: number): boolean {
    return this.pinned !== '' && this.pinned === slotKey(messageId, albumIndex);
  }

  pin(messageId: number, albumIndex: number, now: number): void {
    this.pinned = slotKey(messageId, albumIndex);
    this.pinnedAt = now;
  }

  // 播完 / 播放失败：这一条主动退位，把播放位让出去重新竞选。
  //
  // 不会自我循环：退位时把它的 stableSince 抹掉，list() 就会把它的 ratio 封
  // 到入选线以下，紧接着这一次 elect 里它必然出局；而 stableSince 只在
  // report() 里重新落下，一条稳稳停着的视频不会再有新的可见区回调（
  // onVisibleAreaApproximateChange 只在跨阈值时触发），所以在用户真的滑动
  // 它之前，它不可能重新当选。同屏其它候选的驻留计时不受影响，会立刻接位。
  retire(messageId: number, albumIndex: number, now: number): void {
    const key = slotKey(messageId, albumIndex);
    if (this.slot !== key) {
      return;
    }
    if (this.pinned === key) {
      this.pinned = '';
    }
    this.stableSince.delete(key);
    this.setSlot('');
    this.elect(now);
  }

  // 外部定时器在「还有候选没攒满驻留」时调用；重新跑一次判定，不依赖任何
  // 新的可见区回调（onVisibleAreaApproximateChange 只在跨阈值时触发，一条
  // 视频稳稳停着反而不再有任何回调）。
  tick(now: number): void {
    this.elect(now);
  }

  // 下次值得再检查一次的延时（毫秒）；没有候选正在攒驻留时返回 -1。调用方
  // （ChatPage）据此安排一次性定时器，时间到了再调 tick(now)。
  nextCheckDelay(now: number): number {
    let earliest = -1;
    this.stableSince.forEach((since: number): void => {
      const remaining = PLAY_SLOT_DWELL_MS - (now - since);
      if (remaining > 0 && (earliest < 0 || remaining < earliest)) {
        earliest = remaining;
      }
    });
    return earliest;
  }

  // 暂停：清掉当前播放位与所有驻留计时，但**保留候选表**。用于全屏查看器
  // 打开、页面隐藏这类「气泡几何没变、迟早还要回来」的场景。
  //
  // 为什么不能用 reset()：候选表一旦清空，回来时气泡几何没有任何变化，
  // onVisibleAreaApproximateChange 不会重新上报，候选表就再也填不回来 ——
  // 用户不手动滑一下，播放位永远选不出来（列表「哑掉」）。
  suspend(): void {
    this.suspended = true;
    this.stableSince.clear();
    this.pinned = '';
    this.pinnedAt = 0;
    this.setSlot('');
  }

  // 恢复：候选还在，按 now 重新给「此刻已达入选线」的候选起算驻留 —— 回来
  // 之后照样要稳住 PLAY_SLOT_DWELL_MS 才起播，与首次进入完全一致。
  // 幂等：没暂停过就什么也不做，所以可以挂在 armPlaySlotSettle 这种会被反复
  // 调用的路径上而不会一直把驻留计时推后。
  resume(now: number): void {
    if (!this.suspended) {
      return;
    }
    this.suspended = false;
    this.candidates.forEach((c: PlaySlotCandidate): void => {
      if (c.ratio >= PLAY_SLOT_ENTER_RATIO) {
        this.stableSince.set(c.key, now);
      }
    });
  }

  // 全清（含候选表）。只用于真正离开聊天页，以及「自动播放视频」被关掉这类
  // 「这个会话内不该再有任何候选」的场景。
  reset(): void {
    this.candidates.clear();
    this.stableSince.clear();
    this.pinned = '';
    this.pinnedAt = 0;
    this.suspended = false;
    this.setSlot('');
  }

  // 喂给 pickPlaySlot 的候选表：现任与被 pin 的用真实 ratio（迟滞连任 / 手动
  // 点播都不需要重新攒驻留），其余没攒满 PLAY_SLOT_DWELL_MS 的候选把 ratio
  // 封顶在入选线以下——让它们在「挑新任」的那段循环里天然出局，但仍然留在
  // 候选表里（万一它们就是现任，不能凭空消失）。
  private list(now: number): PlaySlotCandidate[] {
    const out: PlaySlotCandidate[] = [];
    this.candidates.forEach((c: PlaySlotCandidate): void => {
      if (c.key === this.slot || c.key === this.pinned || this.hasDwelled(c.key, now)) {
        out.push(c);
        return;
      }
      const capped: PlaySlotCandidate = {
        key: c.key,
        messageId: c.messageId,
        albumIndex: c.albumIndex,
        ratio: Math.min(c.ratio, PLAY_SLOT_ENTER_RATIO - 0.0001),
        centerY: c.centerY
      };
      out.push(capped);
    });
    return out;
  }

  private hasDwelled(key: string, now: number): boolean {
    const since = this.stableSince.get(key);
    return since !== undefined && now - since >= PLAY_SLOT_DWELL_MS;
  }

  private elect(now: number): void {
    if (this.suspended) {
      return;
    }
    this.expirePin(now);
    this.setSlot(pickPlaySlot(this.list(now), this.viewportCenterY, this.slot, this.pinned));
  }

  // pin 的特权是有时效的（见 PLAY_SLOT_PIN_TTL_MS）：过期即回到普通候选，
  // 之后要跟别人一样攒满驻留才能当选。
  private expirePin(now: number): void {
    if (this.pinned !== '' && now - this.pinnedAt >= PLAY_SLOT_PIN_TTL_MS) {
      this.pinned = '';
      this.pinnedAt = 0;
    }
  }

  // 停播不等驻留：在播的那条划出保持线（或整个消失）就立刻释放。
  private releaseIfGone(): void {
    if (this.slot === '') {
      return;
    }
    const playing = this.candidates.get(this.slot);
    if (playing === undefined || playing.ratio < PLAY_SLOT_KEEP_RATIO) {
      if (this.pinned === this.slot) {
        this.pinned = '';
        this.pinnedAt = 0;
      }
      this.setSlot('');
    }
  }

  private setSlot(key: string): void {
    if (this.slot === key) {
      return;
    }
    this.slot = key;
    for (const listener of this.listeners) {
      listener(key);
    }
  }
}
