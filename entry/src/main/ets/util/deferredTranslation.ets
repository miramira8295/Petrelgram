import { TdObject } from '../tdkit/TdTypes';
// 滑动期间攒下来的译文，等列表停稳再落。纯函数式的小队列，无 IO。
//
// 【为什么要攒】译文让气泡变高，也就是**改布局**。手指还在滑或者列表还在惯性
// 里的时候改，用户看到的就是"边滑边跳"（用户 2026-09-09 实测）。译文不是实时
// 数据，晚半秒落地毫无损失，而滑动中的跳动是实打实的观感损伤。
//
// 【为什么按消息 id 覆盖而不是排队】同一条消息可能先命中缓存、后又被网络结果
// 覆盖（换目标语言时）。队列里只该留**最后一份**，否则停稳的那一刻会连着改
// 两次布局。

export interface PendingTranslation {
  messageId: number;
  lang: string;
  text: string;
  // 译文自己的实体，和 text 同来同去（见 MessageEntry.translatedEntities）。
  entities: TdObject[];
}

// 加入/覆盖一条。不可变——返回新表。
export function queueTranslation(current: PendingTranslation[],
  next: PendingTranslation): PendingTranslation[] {
  const out: PendingTranslation[] = current.filter(
    (p: PendingTranslation): boolean => p.messageId !== next.messageId);
  out.push(next);
  return out;
}

// 攒太多也不好：一次全落照样是一次大重排。上限之内按先进先出丢最旧的
// ——最旧的那条多半已经滑出视野。
export const PENDING_TRANSLATION_MAX: number = 60;

export function trimPendingTranslations(
  current: PendingTranslation[], cap: number = PENDING_TRANSLATION_MAX
): PendingTranslation[] {
  if (cap <= 0) {
    return [];
  }
  return current.length <= cap ? current : current.slice(current.length - cap);
}

// --- 落地的节奏 ---------------------------------------------------------
//
// 【为什么不能一次全落】第一版 flushPending 是一个循环里把整批都落掉，于是
// **所有气泡在同一帧一起变高**，N 个 animateTo 同时起跑。用户实测：「不是一个
// 一个拉长气泡，反而是一堆气泡一起动画拉长了，和闪气泡没啥区别」——加了过渡
// 但没改变"整屏同时抽搐一下"这件事。
//
// 所以按序错开，读起来是依次长出来。

// 相邻两条之间隔多久。太短仍然像一起动，太长会让人等。
export const TRANSLATION_STAGGER_MS: number = 70;

// 整批错开的总时长上限。滑过一长段之后队列可能有几十条，逐条错开会拖到几秒；
// 超过这个上限的那些一起落——它们几乎必然在视野之外，看不见。
export const TRANSLATION_STAGGER_CAP_MS: number = 630;

// 第 index 条该延迟多久落。纯函数，方便钉住"前几条错开、其余归并"这条规则。
export function translationLandDelay(index: number,
  stagger: number = TRANSLATION_STAGGER_MS,
  cap: number = TRANSLATION_STAGGER_CAP_MS): number {
  if (index <= 0) {
    return 0;
  }
  const wanted: number = index * stagger;
  return wanted > cap ? cap : wanted;
}

// --- 换字时的淡入淡出 ---------------------------------------------------
//
// 【为什么高度补间不够】替换模式（译文顶掉原文）下气泡高度往往几乎不变，
// 只有字变了——只补高度的话用户看到的还是硬切
// （用户 2026-09-09：「原文翻译替换好像看不太出来动画呢」）。

// 淡到多低。0 会让那一行整个消失一下，反而像闪；留一点底更像"字在换"。
export const TRANSLATION_FADE_LOW: number = 0.35;
export const TRANSLATION_FADE_OUT_MS: number = 110;
// 淡入比淡出长：新内容要和高度补间同拍，一起走完。
export const TRANSLATION_FADE_IN_MS: number = 260;
