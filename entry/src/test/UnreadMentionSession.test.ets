import { describe, expect, it } from '@ohos/hypium';
import { TdObject, TdRequest } from '../main/ets/tdkit/TdTypes';
import { UnreadMentionSession, UnreadMentionPort, UnreadMentionScope } from '../main/ets/pages/chat/UnreadMentionSession';

class PendingMentionSearch {
  resolve: (result: TdObject) => void = (_result: TdObject): void => {};
  reject: (error: Error) => void = (_error: Error): void => {};
  promise: Promise<TdObject> = new Promise<TdObject>((resolve, reject): void => {
    this.resolve = resolve; this.reject = reject;
  });
}

class MentionPort implements UnreadMentionPort {
  requests: TdRequest[] = [];
  pending: PendingMentionSearch[] = [];
  jumps: number[] = [];
  errors: number = 0;
  visible: boolean = true;
  initialCount: number = 3;
  notify: (count: number) => void = (_count: number): void => {};
  updates: Map<string, (update: TdObject) => void> = new Map();
  send: (request: TdRequest) => Promise<TdObject> = (request: TdRequest): Promise<TdObject> => {
    this.requests.push(request);
    const pending = new PendingMentionSearch(); this.pending.push(pending); return pending.promise;
  };
  subscribeCount: (listener: (count: number) => void) => () => void = (listener: (count: number) => void): (() => void) => {
    this.notify = listener; listener(this.initialCount);
    return (): void => { this.notify = (_count: number): void => {}; };
  };
  onUpdate: (type: string, listener: (update: TdObject) => void) => () => void =
    (type: string, listener: (update: TdObject) => void): (() => void) => {
      this.updates.set(type, listener); return (): void => { this.updates.delete(type); };
    };
  active: () => boolean = (): boolean => this.visible;
  jump: (id: number) => void = (id: number): void => { this.jumps.push(id); };
  failed: () => void = (): void => { this.errors++; };
}

function scope(forum: number = 0, thread: number = 0): UnreadMentionScope {
  return { chatId: 7, threadRootId: thread, forumTopicId: forum, directMessagesTopicId: 0 };
}
function result(ids: number[], forum: number = 0, chat: number = 7): TdObject {
  return { '@type': 'foundChatMessages', 'total_count': ids.length,
    'messages': ids.map((id: number): TdObject => ({ '@type': 'message', 'id': id, 'chat_id': chat,
      'topic_id': { '@type': 'messageTopicForum', 'forum_topic_id': forum } as TdObject })) };
}
function session(port: MentionPort): UnreadMentionSession {
  const s = new UnreadMentionSession(); s.open(scope(), port); return s;
}

export default function unreadMentionSessionTest() {
  describe('UnreadMentionSession', () => {
    it('会话计数订阅无需搜索，也不会进页清空提醒', 0, () => {
      const p = new MentionPort(); const s = session(p);
      expect(s.count).assertEqual(3); expect(p.requests.length).assertEqual(0);
      p.notify(0); expect(s.count).assertEqual(0); s.dispose();
    });
    it('点击使用TDLib未读提及过滤器且只交回跳转目标', 0, async () => {
      const p = new MentionPort(); const s = session(p); const done = s.next();
      expect((p.requests[0]['filter'] as TdObject)['@type']).assertEqual('searchMessagesFilterUnreadMention');
      expect(p.requests[0]['query']).assertEqual('');
      p.pending[0].resolve(result([30, 20])); await done;
      expect(p.jumps.join(',')).assertEqual('30'); expect(s.count).assertEqual(3);
      expect(s.busy).assertFalse(); s.dispose();
    });
    it('连点只发一趟请求', 0, async () => {
      const p = new MentionPort(); const s = session(p); const done = s.next(); await s.next();
      expect(p.requests.length).assertEqual(1); p.pending[0].resolve(result([30])); await done; s.dispose();
    });
    it('再次点击越过上一条，避免语音提及未消失时卡住', 0, async () => {
      const p = new MentionPort(); const s = session(p);
      const first = s.next(); p.pending[0].resolve(result([30])); await first;
      const second = s.next(); expect(p.requests[1]['from_message_id']).assertEqual(30);
      p.pending[1].resolve(result([30, 20])); await second;
      expect(p.jumps.join(',')).assertEqual('30,20'); s.dispose();
    });
    it('走到末尾后回到最新未读提及', 0, async () => {
      const p = new MentionPort(); const s = session(p);
      const first = s.next(); p.pending[0].resolve(result([30])); await first;
      const second = s.next(); p.pending[1].resolve(result([])); await Promise.resolve();
      expect(p.requests[2]['from_message_id']).assertEqual(0);
      p.pending[2].resolve(result([50])); await second;
      expect(p.jumps.join(',')).assertEqual('30,50'); s.dispose();
    });
    it('退出会话后丢弃迟到响应并退订', 0, async () => {
      const p = new MentionPort(); const s = session(p); const done = s.next(); s.dispose();
      p.pending[0].resolve(result([30])); await done;
      expect(p.jumps.length).assertEqual(0); expect(p.updates.size).assertEqual(0);
      expect(s.busy).assertFalse();
    });
    it('后台和被覆盖时不跳转', 0, async () => {
      const p = new MentionPort(); const s = session(p); const done = s.next(); p.visible = false;
      p.pending[0].resolve(result([30])); await done; await s.next();
      expect(p.jumps.length).assertEqual(0); expect(p.requests.length).assertEqual(1); s.dispose();
    });
    it('失败后保留提醒并允许重试', 0, async () => {
      const p = new MentionPort(); const s = session(p); const done = s.next();
      p.pending[0].reject(new Error('offline')); await done;
      expect(p.errors).assertEqual(1); expect(s.count).assertEqual(3); expect(s.busy).assertFalse();
      const retry = s.next(); p.pending[1].resolve(result([30])); await retry;
      expect(p.jumps.join(',')).assertEqual('30'); s.dispose();
    });
    it('请求途中全部已读时不跳到过期目标', 0, async () => {
      const p = new MentionPort(); const s = session(p); const done = s.next(); p.notify(0);
      p.pending[0].resolve(result([30])); await done;
      expect(p.jumps.length).assertEqual(0); s.dispose();
    });
    it('话题计数和导航使用话题范围', 0, async () => {
      const p = new MentionPort(); const s = new UnreadMentionSession(); s.open(scope(9), p);
      expect((p.requests[0]['topic_id'] as TdObject)['forum_topic_id']).assertEqual(9);
      expect(s.count).assertEqual(0); p.pending[0].resolve(result([30], 9)); await Promise.resolve();
      expect(s.count).assertEqual(1);
      const done = s.next(); p.pending[1].resolve(result([30], 9)); await done;
      expect(p.jumps.join(',')).assertEqual('30'); s.dispose();
    });
    it('话题实时计数不被旧探测结果覆盖', 0, async () => {
      const p = new MentionPort(); const s = new UnreadMentionSession(); s.open(scope(9), p);
      p.updates.get('updateForumTopic')!({ '@type': 'updateForumTopic', 'chat_id': 7,
        'forum_topic_id': 9, 'unread_mention_count': 0 });
      p.pending[0].resolve(result([30], 9)); await Promise.resolve();
      expect(s.count).assertEqual(0); s.dispose();
    });
    it('错误会话或话题的结果不会串到当前页面', 0, async () => {
      const p = new MentionPort(); const s = new UnreadMentionSession(); s.open(scope(9), p);
      p.pending[0].resolve(result([30], 9)); await Promise.resolve();
      const done = s.next(); p.pending[1].resolve(result([30], 10, 8)); await done;
      expect(p.jumps.length).assertEqual(0); expect(p.errors).assertEqual(1); s.dispose();
    });
  });
}
