import { TdObject } from '../tdkit/TdTypes';

// 频道消息「浏览数」的旁路通道（气泡右下角那只眼睛 + 5.2K）。
//
// 【为什么不进 MessageEntry、不走 store 的 patch】频道里浏览数几乎每秒都在涨，
// 每涨一次 TDLib 就推一条 updateMessageInteractionInfo。走 patch 就是每次都克隆
// 一行、复制一遍消息数组、再触发一轮列表 notify——全在 UI 线程上。而界面上
// 5231 → 5232 → 5299 显示的都是同一个「5.2K」，这些工作绝大多数是白干。
//
// 所以两层短路：
//   1. 通道里只记数字，**标签没变就不通知**——订阅的气泡一次都不会被叫醒；
//   2. store 那边只有评论/反应真的变了才 patch 行（util/interactionDelta），
//      纯浏览数推送只走这里。
//
// 与 sendStateChannel / translationChannel 同构。键是 (chatId, messageId)：
// 消息 id 只在会话内唯一。

type ViewListener = (label: string) => void;

// 上限只是防御：正常一个会话页看几百条就退出了。满了按插入顺序淘汰最旧的。
const VIEW_COUNT_CAP: number = 20000;

const counts: Map<string, number> = new Map();
const subs: Map<string, Set<ViewListener>> = new Map();

function keyOf(chatId: number, messageId: number): string {
  return `${chatId}:${messageId}`;
}

// 整数运算、一律向下取整：
//   2300/1000*10 在浮点里是 22.999…，直接 floor 会显示成 2.2K；
//   1999 四舍五入成 2.0K 等于把没到的数说成到了。
function compact(value: number, unit: number, suffix: string): string {
  const tenths: number = Math.floor(value * 10 / unit);
  if (tenths >= 100) {
    return `${Math.floor(tenths / 10)}${suffix}`;
  }
  const whole: number = Math.floor(tenths / 10);
  const frac: number = tenths % 10;
  return frac === 0 ? `${whole}${suffix}` : `${whole}.${frac}${suffix}`;
}

// 与官方客户端同一种缩写：999 / 5.2K / 52K / 1.2M / 45M。0 或非法返回 ''（不显示）。
export function formatViewCount(count: number): string {
  if (!(count > 0)) {
    return '';
  }
  const v: number = Math.floor(count);
  if (v < 1000) {
    return `${v}`;
  }
  if (v < 1000000) {
    return compact(v, 1000, 'K');
  }
  return compact(v, 1000000, 'M');
}

// TDLib 对没有互动信息的消息给的是 null（不是缺字段），两种都当 0。
export function viewCountOf(message: TdObject): number {
  const ii = message['interaction_info'] as TdObject | undefined | null;
  if (ii === undefined || ii === null) {
    return 0;
  }
  return (ii['view_count'] as number | undefined) ?? 0;
}

// 只增不减：翻页重新拉到的旧快照、乱序到达的推送都不能把数压回去。
export function publishViewCount(chatId: number, messageId: number, count: number): void {
  if (chatId === 0 || messageId <= 0 || !(count > 0)) {
    return;
  }
  const key: string = keyOf(chatId, messageId);
  const prev: number = counts.get(key) ?? 0;
  if (count <= prev) {
    return;
  }
  counts.set(key, count);
  if (counts.size > VIEW_COUNT_CAP) {
    const oldest: string | undefined = counts.keys().next().value;
    if (oldest !== undefined && oldest !== key) {
      counts.delete(oldest);
    }
  }
  const label: string = formatViewCount(count);
  if (label === formatViewCount(prev)) {
    return;
  }
  const listeners: Set<ViewListener> | undefined = subs.get(key);
  if (listeners !== undefined) {
    listeners.forEach((cb: ViewListener): void => cb(label));
  }
}

export function viewCountLabelFor(chatId: number, messageId: number): string {
  return formatViewCount(counts.get(keyOf(chatId, messageId)) ?? 0);
}

export function subscribeViewCount(chatId: number, messageId: number,
  cb: ViewListener): () => void {
  const key: string = keyOf(chatId, messageId);
  let listeners: Set<ViewListener> | undefined = subs.get(key);
  if (listeners === undefined) {
    listeners = new Set<ViewListener>();
    subs.set(key, listeners);
  }
  listeners.add(cb);
  return (): void => {
    const current: Set<ViewListener> | undefined = subs.get(key);
    if (current !== undefined) {
      current.delete(cb);
      if (current.size === 0) {
        subs.delete(key);
      }
    }
  };
}

// 正文末尾那段透明占位里，浏览数要占的一截（气泡 timeReserve 的前缀）。
// 与时间占位同一种写法：U+2004（1/3 em）。眼睛 11 + 间隙 2 + 与时间的间隙 4
// ≈ 17vp，按 14fp 的 1/3 em ≈ 4.7vp 取 4 个；标签原样跟在后面——占位的字号不小于
// 叠在上面的 11fp，只会略宽，不会压字。
const VIEWS_ICON_RESERVE: string = '    ';

export function viewsReserve(label: string): string {
  return label === '' ? '' : `${VIEWS_ICON_RESERVE}${label}`;
}
