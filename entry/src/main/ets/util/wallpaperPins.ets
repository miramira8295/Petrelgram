import { PixelHandle, pinPixelMap, unpinPixelMap } from './pixelCache';
// 壁纸整屏光栅的像素 pin 生命周期管理。
//
// 背景：聊天背景 / APP 背景用的是一张整屏 JPEG 光栅（1316×2832 ≈ 14.22MiB）。
// 它必须被 pin 住——否则会被相册、头像的解码按 LRU 挤掉，每次进会话要重付
// 解码时间，并且首帧会回落到分层实时绘制（实测 85ms）。但旧的 `spec.pin === true`
// 是进程级永久 pin：`unpinPixelMap` 从未被调用，页面退出也不松开，于是「换壁纸 /
// 切深浅色 / 改窗口尺寸 / 连开多个会话」各留一张，只增不减。
//
// 第一版实现按「槽位」记单张图 + 单个定时器，源码审计发现三个真实缺陷：
//   ① 单 timer 串行：pin A → pin B（park A）→ pin C（cancel 掉 A 的 park，只补 park B）
//      → A 永久 pinned；
//   ② 单 handle 且无 owner 计数：同槽位两个实例（如 MainScreen 与 ProfilePage 的
//      AppBackdrop 同时存在）时，一个退出会把另一个仍在显示的图松钉；
//   ③ 跨槽位同句柄：`pinPixelMap` 按句柄幂等，两槽同图时只加了一个 pin 引用，
//      任一槽 unpin 就把它整张松掉。
//
// 现在改成**以句柄为键、以 owner 集合记账**：
//   · pin 的身份是 PixelHandle（不是槽位）——同图跨页共享天然正确；
//   · owner 是组件实例的唯一 id（`bd#3`），退出只删自己那一份；
//   · 最后一个 owner 离开才排 2 秒延迟释放；期间有 owner 回来就取消；
//   · entry 级 gen + 组件级 pinGen 双代次，旧定时器/旧异步不会动到新一轮引用；
//   · 处于等待释放（owners 为空）的 entry 有上限，超出按排队时间最旧立即松钉，
//     避免快速换壁纸/拖滑杆时无限累积。
const RELEASE_GRACE_MS: number = 300000;
// 处于「等宽限期」状态的 entry 上限（按张数与字节双限）。
// 整屏 RGBA 壁纸约 14.22MiB，32MiB 可同时容下 APP 背景与聊天背景共 2 张常驻命中。
const MAX_PARKED: number = 2;
const PARKED_BYTES_CAP: number = 32 * 1024 * 1024;

class PinEntry {
  handle: PixelHandle;
  // 当前持有该图的组件实例 id 集合；为空表示只剩宽限期。
  owners: Set<string> = new Set<string>();
  // 每次 owner 变化 +1；定时器回调比对快照，旧代次不动手。
  gen: number = 0;
  // 待执行的释放定时器 id（-1 表示没有）。
  timer: number = -1;
  // 进入「等宽限期」状态的时间戳，用于超限时按最旧优先松钉。
  parkedAt: number = 0;

  constructor(handle: PixelHandle) {
    this.handle = handle;
  }
}

const pins: Map<PixelHandle, PinEntry> = new Map<PixelHandle, PinEntry>();

function cancelTimer(entry: PinEntry): void {
  if (entry.timer !== -1) {
    clearTimeout(entry.timer);
    entry.timer = -1;
  }
}

// 松钉并移除记录。调用方必须保证这是最后一次引用。
function unpinEntry(entry: PinEntry): void {
  cancelTimer(entry);
  if (pins.get(entry.handle) === entry) {
    pins.delete(entry.handle);
  }
  unpinPixelMap(entry.handle);
}

// 让 owners 为空的 entry 在宽限期后松钉；执行时三重校验，旧任务不动新引用。
function parkEntry(entry: PinEntry): void {
  cancelTimer(entry);
  entry.parkedAt = Date.now();
  const parkedGen: number = entry.gen;
  entry.timer = setTimeout((): void => {
    entry.timer = -1;
    if (pins.get(entry.handle) !== entry) {
      // 这条记录已经被新一轮替换掉了。
      return;
    }
    if (entry.owners.size > 0 || entry.gen !== parkedGen) {
      // 宽限期内又被重新持有，放弃释放。
      return;
    }
    unpinEntry(entry);
  }, RELEASE_GRACE_MS);
  enforceParkedCap(entry);
}

// 等待释放的 entry 超限时，把排队最久的立即松钉（不让定时器无限堆着）。
function enforceParkedCap(keep: PinEntry): void {
  let parked: PinEntry[] = [];
  pins.forEach((entry: PinEntry): void => {
    if (entry.owners.size === 0) {
      parked.push(entry);
    }
  });
  if (parked.length <= MAX_PARKED) {
    let sum: number = 0;
    for (const entry of parked) {
      sum += entry.handle.bytes;
    }
    if (sum <= PARKED_BYTES_CAP) {
      return;
    }
  }
  parked.sort((a: PinEntry, b: PinEntry): number => a.parkedAt - b.parkedAt);
  let sum: number = 0;
  for (const entry of parked) {
    sum += entry.handle.bytes;
  }
  for (const entry of parked) {
    if (entry === keep) {
      continue;
    }
    if (parked.length <= MAX_PARKED && sum <= PARKED_BYTES_CAP) {
      break;
    }
    sum -= entry.handle.bytes;
    parked = parked.filter((it: PinEntry): boolean => it !== entry);
    unpinEntry(entry);
  }
}

// 组件拿到一张图、开始持有它。owner 用组件实例唯一 id。
export function retainWallpaperPin(handle: PixelHandle, owner: string): void {
  let entry = pins.get(handle);
  if (entry === undefined) {
    // 先钉住再记账：pinPixelMap 自身幂等，重复 retain 不会重复计数。
    pinPixelMap(handle);
    entry = new PinEntry(handle);
    pins.set(handle, entry);
  }
  if (entry.owners.has(owner)) {
    return;
  }
  entry.owners.add(owner);
  entry.gen++;
  cancelTimer(entry);
  entry.parkedAt = 0;
}

// 组件不再持有这张图。只删自己那一份；最后一个 owner 离开才排延迟释放。
export function releaseWallpaperPin(handle: PixelHandle | undefined, owner: string): void {
  if (handle === undefined) {
    return;
  }
  const entry = pins.get(handle);
  if (entry === undefined) {
    return;
  }
  if (!entry.owners.has(owner)) {
    // 重复释放 / 不是本 owner：直接忽略，保证计数不会为负。
    return;
  }
  entry.owners.delete(owner);
  entry.gen++;
  if (entry.owners.size > 0) {
    return;
  }
  parkEntry(entry);
}

// 兜底：把某个 owner 在所有 entry 上的引用都摘掉（页面销毁时调用）。
export function releaseAllWallpaperPins(owner: string): number {
  let released: number = 0;
  const affected: PinEntry[] = [];
  pins.forEach((entry: PinEntry): void => {
    if (entry.owners.has(owner)) {
      entry.owners.delete(owner);
      entry.gen++;
      released++;
      affected.push(entry);
    }
  });
  for (const entry of affected) {
    if (entry.owners.size === 0) {
      parkEntry(entry);
    }
  }
  return released;
}

// 立即松掉所有「已经没有 owner」的 entry（切后台、收尾时用，避免宽限期拖过后台回收）。
export function settleParkedWallpaperPins(): number {
  const idle: PinEntry[] = [];
  pins.forEach((entry: PinEntry): void => {
    if (entry.owners.size === 0) {
      idle.push(entry);
    }
  });
  for (const entry of idle) {
    unpinEntry(entry);
  }
  return idle.length;
}

// 诊断用：当前钉住的张数、owner 数与总字节，供真机日志确认「确实松开了」。
export function wallpaperPinReport(): string {
  let count: number = 0;
  let owners: number = 0;
  let bytes: number = 0;
  let parked: number = 0;
  pins.forEach((entry: PinEntry): void => {
    count++;
    owners += entry.owners.size;
    bytes += entry.handle.bytes;
    if (entry.owners.size === 0) {
      parked++;
    }
  });
  return `pins=${count} owners=${owners} parked=${parked} bytes=${bytes}`;
}
