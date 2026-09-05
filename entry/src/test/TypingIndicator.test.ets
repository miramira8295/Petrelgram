import { beforeEach, describe, expect, it } from '@ohos/hypium';
import { resetStrings } from '../main/ets/util/strings';
import {
  TYPING_ACTION_TTL_MS, applyTypingUpdate, pruneExpiredTyping, typingLabelOf
} from '../main/ets/util/typingIndicator';
import { TdObject } from '../main/ets/tdkit/TdTypes';

// 一条 updateChatAction。sender 默认是用户，action 由参数给。
function chatAction(chatId: number, uid: number, actionType: string): TdObject {
  const sender: TdObject = { '@type': 'messageSenderUser' };
  sender['user_id'] = uid;
  const action: TdObject = { '@type': actionType };
  const update: TdObject = { '@type': 'updateChatAction' };
  update['chat_id'] = chatId;
  update['sender_id'] = sender;
  update['action'] = action;
  return update;
}

function withForumTopic(update: TdObject, topicId: number): TdObject {
  const topic: TdObject = { '@type': 'messageTopicForum' };
  topic['forum_topic_id'] = topicId;
  update['topic_id'] = topic;
  return update;
}

function withDirectTopic(update: TdObject, topicId: number): TdObject {
  const topic: TdObject = { '@type': 'messageTopicDirectMessages' };
  topic['direct_messages_chat_topic_id'] = topicId;
  update['topic_id'] = topic;
  return update;
}

const NOW: number = 1700000000000;

// 宿主单测里没装 StringSource，str() 原样返回 key（带参时是 `key(args)`），
// 所以下面断的是「选了哪条文案」而不是文案本身。
export default function typingIndicatorTest() {
  describe('typingIndicator', () => {
    beforeEach((): void => { resetStrings(); });

    it('到期时长就是 TDLib chatAction 的 6s 有效期', 0, (): void => {
      expect(TYPING_ACTION_TTL_MS).assertEqual(6000);
      const senders: Map<number, number> = new Map();
      expect(applyTypingUpdate(senders, chatAction(7, 42, 'chatActionTyping'), NOW, 7, 0, 0, 0))
        .assertEqual(42);
      expect(senders.get(42)).assertEqual(NOW + 6000);
    });

    it('别的会话的 chatAction 一律忽略', 0, (): void => {
      const senders: Map<number, number> = new Map();
      expect(applyTypingUpdate(senders, chatAction(8, 42, 'chatActionTyping'), NOW, 7, 0, 0, 0))
        .assertEqual(0);
      expect(senders.size).assertEqual(0);
    });

    it('非用户发送方与非法 uid 都忽略', 0, (): void => {
      const senders: Map<number, number> = new Map();
      // 频道/群作为发送方（messageSenderChat）：没有 user_id 可记。
      const chatSender: TdObject = { '@type': 'messageSenderChat' };
      chatSender['chat_id'] = -100;
      const typingAction: TdObject = { '@type': 'chatActionTyping' };
      const fromChat: TdObject = { '@type': 'updateChatAction' };
      fromChat['chat_id'] = 7;
      fromChat['sender_id'] = chatSender;
      fromChat['action'] = typingAction;
      expect(applyTypingUpdate(senders, fromChat, NOW, 7, 0, 0, 0)).assertEqual(0);
      // 整个 sender_id 缺失。
      const noSender: TdObject = { '@type': 'updateChatAction' };
      noSender['chat_id'] = 7;
      expect(applyTypingUpdate(senders, noSender, NOW, 7, 0, 0, 0)).assertEqual(0);
      // uid = 0。
      expect(applyTypingUpdate(senders, chatAction(7, 0, 'chatActionTyping'), NOW, 7, 0, 0, 0))
        .assertEqual(0);
      expect(senders.size).assertEqual(0);
    });

    it('chatActionCancel 删掉该 uid，其余动作都记一次输入', 0, (): void => {
      const senders: Map<number, number> = new Map();
      // 不只是 typing：录音、发图等一切非 cancel 的动作都算「正在忙活」。
      applyTypingUpdate(senders, chatAction(7, 42, 'chatActionRecordingVoiceNote'), NOW, 7, 0, 0, 0);
      applyTypingUpdate(senders, chatAction(7, 43, 'chatActionUploadingPhoto'), NOW, 7, 0, 0, 0);
      expect(senders.size).assertEqual(2);
      expect(applyTypingUpdate(senders, chatAction(7, 42, 'chatActionCancel'), NOW, 7, 0, 0, 0))
        .assertEqual(42);
      expect(senders.has(42)).assertFalse();
      expect(senders.has(43)).assertTrue();
      // 页面靠「调用后 map 里还有没有这个 uid」来决定要不要 getUserStore().ensure(uid)：
      // cancel 之后是 false，所以不会为一条取消去拉用户信息。
      expect(applyTypingUpdate(senders, chatAction(7, 99, 'chatActionCancel'), NOW, 7, 0, 0, 0))
        .assertEqual(99);
      expect(senders.has(99)).assertFalse();
    });

    it('同一个 uid 再来一条就续期，不会堆两份', 0, (): void => {
      const senders: Map<number, number> = new Map();
      applyTypingUpdate(senders, chatAction(7, 42, 'chatActionTyping'), NOW, 7, 0, 0, 0);
      applyTypingUpdate(senders, chatAction(7, 42, 'chatActionTyping'), NOW + 2000, 7, 0, 0, 0);
      expect(senders.size).assertEqual(1);
      expect(senders.get(42)).assertEqual(NOW + 2000 + TYPING_ACTION_TTL_MS);
    });

    it('论坛话题：话题对不上的忽略，对得上的照收', 0, (): void => {
      const senders: Map<number, number> = new Map();
      const other = withForumTopic(chatAction(7, 42, 'chatActionTyping'), 9);
      expect(applyTypingUpdate(senders, other, NOW, 7, 0, 5, 0)).assertEqual(0);
      const mine = withForumTopic(chatAction(7, 42, 'chatActionTyping'), 5);
      expect(applyTypingUpdate(senders, mine, NOW, 7, 0, 5, 0)).assertEqual(42);
      // 没带 topic_id 的在话题视图里也算「不属于本话题」。
      const bare = chatAction(7, 43, 'chatActionTyping');
      expect(applyTypingUpdate(senders, bare, NOW, 7, 0, 5, 0)).assertEqual(0);
    });

    it('私密消息话题同理', 0, (): void => {
      const senders: Map<number, number> = new Map();
      expect(applyTypingUpdate(senders, withDirectTopic(chatAction(7, 42, 'chatActionTyping'), 9),
        NOW, 7, 0, 0, 5)).assertEqual(0);
      expect(applyTypingUpdate(senders, withDirectTopic(chatAction(7, 42, 'chatActionTyping'), 5),
        NOW, 7, 0, 0, 5)).assertEqual(42);
    });

    // **回归闸**：话题过滤的外层条件只看 forumTopicId / directMessagesTopicId。
    // 评论区（thread）会话里 threadRootId > 0 但不做话题过滤——chatAction 上根本
    // 没有 message_thread_id，把 thread 加进去会把评论区的「正在输入…」整个过滤没。
    it('纯 thread 会话不做话题过滤', 0, (): void => {
      const senders: Map<number, number> = new Map();
      expect(applyTypingUpdate(senders, chatAction(7, 42, 'chatActionTyping'), NOW, 7, 5, 0, 0))
        .assertEqual(42);
      expect(senders.has(42)).assertTrue();
    });

    it('裁剪只丢严格早于 now 的项，正好到点的留到下一轮', 0, (): void => {
      const senders: Map<number, number> = new Map();
      senders.set(1, NOW - 1);
      senders.set(2, NOW);
      senders.set(3, NOW + 1);
      expect(pruneExpiredTyping(senders, NOW)).assertTrue();
      expect(senders.has(1)).assertFalse();
      expect(senders.has(2)).assertTrue();
      expect(senders.has(3)).assertTrue();
    });

    it('没东西可丢时返回 false（页面据此不重建文案）', 0, (): void => {
      const senders: Map<number, number> = new Map();
      expect(pruneExpiredTyping(senders, NOW)).assertFalse();
      senders.set(1, NOW + 6000);
      expect(pruneExpiredTyping(senders, NOW)).assertFalse();
      expect(senders.size).assertEqual(1);
    });

    it('全过期后清空，页面这时才停掉轮询', 0, (): void => {
      const senders: Map<number, number> = new Map();
      senders.set(1, NOW);
      senders.set(2, NOW);
      expect(pruneExpiredTyping(senders, NOW + TYPING_ACTION_TTL_MS)).assertTrue();
      expect(senders.size).assertEqual(0);
    });

    it('没人在输入时文案为空串', 0, (): void => {
      const name = (uid: number): string => 'Ann';
      expect(typingLabelOf('group', [], name)).assertEqual('');
      expect(typingLabelOf('private', [], name)).assertEqual('');
    });

    it('私聊/密聊只说「正在输入」，不报名字也不数人头', 0, (): void => {
      const name = (uid: number): string => 'Ann Lee';
      expect(typingLabelOf('private', [42], name)).assertEqual('cp_typing');
      expect(typingLabelOf('secret', [42], name)).assertEqual('cp_typing');
      // 私聊理论上不会有两个人在输入，但真有也不该翻成 plural。
      expect(typingLabelOf('secret', [42, 43], name)).assertEqual('cp_typing');
    });

    it('群里多人走 plural，count 同时是占位符值', 0, (): void => {
      const name = (uid: number): string => 'Ann';
      expect(typingLabelOf('group', [1, 2], name)).assertEqual('cp_n_typing(2,2)');
      expect(typingLabelOf('channel', [1, 2, 3], name)).assertEqual('cp_n_typing(3,3)');
    });

    it('群里一人报名字的第一段', 0, (): void => {
      const names: Map<number, string> = new Map();
      names.set(42, 'Ann Lee');
      const name = (uid: number): string => names.get(uid) ?? '';
      expect(typingLabelOf('group', [42], name)).assertEqual('cp_someone_typing(Ann)');
    });

    it('名字还没拉到时退到「某人」', 0, (): void => {
      const name = (uid: number): string => '';
      expect(typingLabelOf('group', [42], name)).assertEqual('cp_someone_typing(cp_someone)');
    });

    // 端到端把 applyTypingUpdate 写下的到期戳交给 pruneExpiredTyping：TTL 用完
    // 之前一条都不许丢（对端还在打字，占位符不能闪一下），到点之后必须清干净。
    // 两个函数各自改一边（比如把 TTL 挪到 prune 里、或把 `<` 改成 `<=`）都在
    // 这条上现形。
    it('一条输入正好活满 TTL 才被裁掉', 0, (): void => {
      const senders: Map<number, number> = new Map();
      applyTypingUpdate(senders, chatAction(7, 42, 'chatActionTyping'), NOW, 7, 0, 0, 0);
      expect(pruneExpiredTyping(senders, NOW + TYPING_ACTION_TTL_MS)).assertFalse();
      expect(senders.size).assertEqual(1);
      expect(pruneExpiredTyping(senders, NOW + TYPING_ACTION_TTL_MS + 1)).assertTrue();
      expect(senders.size).assertEqual(0);
    });

    // action 字段缺失（或类型认不出来）时 actionType 落到 ''，走的是**非 cancel**
    // 那一支。方向反了的话，任何一条认不出的 chatAction 都会把正在输入的人从
    // 表里删掉，「正在输入…」会一闪一闪。
    it('缺 action 字段按「在忙活」算，不当成取消', 0, (): void => {
      const senders: Map<number, number> = new Map();
      const sender: TdObject = { '@type': 'messageSenderUser' };
      sender['user_id'] = 42;
      const noAction: TdObject = { '@type': 'updateChatAction' };
      noAction['chat_id'] = 7;
      noAction['sender_id'] = sender;
      expect(applyTypingUpdate(senders, noAction, NOW, 7, 0, 0, 0)).assertEqual(42);
      expect(senders.has(42)).assertTrue();
      expect(senders.get(42)).assertEqual(NOW + TYPING_ACTION_TTL_MS);
    });

    // 只有「群里恰好一个人」那一档才需要名字。私聊档和多人档必须在问名字之前
    // 就返回——页面传进来的是 getUserStore().displayName，多问一次就是每 1.5s
    // 一轮轮询里多一次 store 查询。
    it('只有群里单人那一档才去问名字', 0, (): void => {
      let asked: number = 0;
      const name = (uid: number): string => {
        asked++;
        return 'Ann';
      };
      typingLabelOf('group', [1, 2, 3], name);
      typingLabelOf('private', [1], name);
      typingLabelOf('group', [], name);
      expect(asked).assertEqual(0);
      typingLabelOf('group', [42], name);
      expect(asked).assertEqual(1);
    });
  });
}
