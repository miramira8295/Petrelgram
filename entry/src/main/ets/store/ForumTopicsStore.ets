import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { formatPreview } from '../util/formatPreview';
import {
  ForumTopicRow, applyTopicInfoUpdate, applyTopicUpdate, parseForumTopic, sortTopicRows
} from '../util/forumTopicModel';
import { str } from '../util/strings';
import { logE } from '../util/log';

// 一个论坛群的话题列表（2026-09-16）。
//
// 【为什么要有它】话题原来只有一个消费者——话题列表页，数据和订阅都长在页面里。
// 现在聊天详情页顶栏也要一条话题横条，两个页面互不相干（列表页是独立
// NavDestination，横条在 ChatPage 里），不能再把数据留在某一个页面里。
//
// 【为什么不做成进程级共用实例】本仓没有"按 id 取 store"的先例：Globals 里全是无参
// 单例，而 ChatProfileStore 这类按会话的 store 一律**谁用谁 new、谁 close**，没有引用
// 计数。共用实例会凭空引入"谁负责关"的新问题，所以这里照惯例走。两处真正需要共用的
// 是**排序与解析**，那已经在 util/forumTopicModel 里（纯函数、有单测），共用实例并非必需。
// 代价只是同时开着两个页面时各发一次 getForumTopics，与 ChatProfileStore 现状一致。
//
// 【chatId 为什么不进构造器】顶栏的 titleBar builder 有一条硬约束：**绝不能在里面现场
// new 对象**，否则引用每帧都变、子组件白刷（ChatPage.chatTitleBarBottom 的注释记着这笔
// 帧 trace 的账）。所以 ChatPage 必须在字段初始化器里 new 一次、引用恒定；而它的 chatId
// 要到 applyRouteParams 才确定。于是构造器只收 client，会话由 open(chatId) 交代，
// 换会话时内部先退订再重订。

export type ForumTopicsListener = () => void;

export class ForumTopicsStore {
  private client: TdClient;
  private chatId: number = 0;
  private rows: ForumTopicRow[] = [];
  // loading | ready | error —— 与话题列表页原来的 loadState 取值一致。
  private state: string = 'loading';
  private listeners: ForumTopicsListener[] = [];
  private unsubs: Array<() => void> = [];
  // 作废在途请求：换会话或关闭之后回来的那一发不能再写进 rows。
  private loadSeq: number = 0;

  constructor(client: TdClient) {
    this.client = client;
  }

  getRows(): ForumTopicRow[] {
    return this.rows;
  }

  getState(): string {
    return this.state;
  }

  getChatId(): number {
    return this.chatId;
  }

  subscribe(listener: ForumTopicsListener): () => void {
    this.listeners.push(listener);
    return (): void => {
      this.listeners = this.listeners.filter(
        (l: ForumTopicsListener): boolean => l !== listener);
    };
  }

  // 接上一个会话。**幂等**：同一个 chatId 重复调只会重新拉一次列表，不会把订阅叠两份
  // （话题列表页原来就是靠一个 paramsApplied 守卫防这件事的）。
  open(chatId: number): void {
    if (chatId === this.chatId && this.unsubs.length > 0) {
      this.reload();
      return;
    }
    this.unsubscribe();
    this.chatId = chatId;
    this.rows = [];
    this.state = 'loading';
    if (chatId === 0) {
      this.state = 'error';
      this.notify();
      return;
    }
    // 实时刷新：名称/关闭状态（updateForumTopicInfo）与置顶（updateForumTopic）。
    // 判据与就地改行都在 util/forumTopicModel，两个消费者共用同一套。
    this.unsubs.push(this.client.onUpdate('updateForumTopicInfo', (u: TdObject): void => {
      this.applyUpdate(applyTopicInfoUpdate(this.rows, this.chatId, u));
    }));
    this.unsubs.push(this.client.onUpdate('updateForumTopic', (u: TdObject): void => {
      this.applyUpdate(applyTopicUpdate(this.rows, this.chatId, u));
    }));
    this.notify();
    this.reload();
  }

  // 从话题内返回时刷新未读数/最后一条（话题列表页 handleShown 的语义）。
  reload(): void {
    if (this.chatId === 0) {
      return;
    }
    const seq: number = ++this.loadSeq;
    const chatId: number = this.chatId;
    const req: TdRequest = { '@type': 'getForumTopics' };
    req['chat_id'] = chatId;
    req['query'] = '';
    req['offset_date'] = 0;
    req['offset_message_id'] = 0;
    req['offset_forum_topic_id'] = 0;
    req['limit'] = 100;
    this.client.send(req).then((res: TdObject): void => {
      if (seq !== this.loadSeq || chatId !== this.chatId) {
        return;
      }
      const topics: TdObject[] = (res['topics'] as TdObject[] | undefined) ?? [];
      this.rows = sortTopicRows(topics
        .map((topic: TdObject): ForumTopicRow => this.parse(topic))
        .filter((row: ForumTopicRow): boolean => row.threadId > 0));
      this.state = 'ready';
      this.notify();
    }).catch((e: TdError): void => {
      if (seq !== this.loadSeq || chatId !== this.chatId) {
        return;
      }
      logE(`ForumTopicsStore.getForumTopics failed: ${e.message}`);
      this.state = 'error';
      this.notify();
    });
  }

  close(): void {
    this.loadSeq++;
    this.unsubscribe();
    this.listeners = [];
    this.rows = [];
    this.chatId = 0;
  }

  private parse(topic: TdObject): ForumTopicRow {
    const last = topic['last_message'] as TdObject | undefined;
    return parseForumTopic(topic, str('ft_topics'), formatPreview(last ?? null));
  }

  // 不是本会话的更新，应用器会原样把同一个数组还回来——据此跳过一次无谓的发布。
  private applyUpdate(next: ForumTopicRow[]): void {
    if (next === this.rows) {
      return;
    }
    this.rows = next;
    this.notify();
  }

  private unsubscribe(): void {
    for (const un of this.unsubs) {
      un();
    }
    this.unsubs = [];
  }

  private notify(): void {
    for (const l of this.listeners) {
      l();
    }
  }
}
