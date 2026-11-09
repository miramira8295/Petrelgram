// 同时在动的名额池：满了排队，让出的名额直接转给**最后排进来的**那一格。
//
// 贴纸面板往哪边滑，最新挂上的格子就在哪边刚进屏幕；先排队的多半已经被滑走，
// 滑走的格子会撤销排队，不会白占。
//
// 起初只给 WebM 帧序列用（名额满了不退回 ijkplayer，见 AlphaWebmStickerView 文件头那段
// 「不再退回 ijkplayer」的注释）；同日起 TGS 与 WebM 共用，按区域分池，见 util/stickerAnimationBudget。
export class AnimationSlotPool {
  private readonly capacity: number;
  private live: number = 0;
  private readonly waiters: Array<() => void> = [];

  constructor(capacity: number) {
    this.capacity = Math.max(0, Math.floor(capacity));
  }

  liveCount(): number {
    return this.live;
  }

  waitingCount(): number {
    return this.waiters.length;
  }

  tryAcquire(): boolean {
    if (this.live >= this.capacity) {
      return false;
    }
    this.live++;
    return true;
  }

  // 只在 tryAcquire 失败之后调用。onGranted 被叫到时名额已经记在调用方名下，
  // 里面不要再 tryAcquire。返回的函数撤销排队；已经被叫到之后再调是空操作。
  wait(onGranted: () => void): () => void {
    const entry: () => void = (): void => {
      onGranted();
    };
    this.waiters.push(entry);
    return (): void => {
      const at: number = this.waiters.indexOf(entry);
      if (at >= 0) {
        this.waiters.splice(at, 1);
      }
    };
  }

  // 让出一格但**不转给排队的人**：自己是因为别的资源（内存）不够才让的，排队的人
  // 此刻同样拿不到，转过去只会让它们互相转手、在微任务里空转。
  releaseQuietly(): void {
    if (this.live > 0) {
      this.live--;
    }
  }

  // 让出一格：有人排队就原样转过去（占用数不变），没人才真的空出来。
  release(): void {
    if (this.live <= 0) {
      return;
    }
    const next: (() => void) | undefined = this.waiters.pop();
    if (next === undefined) {
      this.live--;
      return;
    }
    next();
  }
}
