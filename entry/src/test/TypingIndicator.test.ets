import { beforeEach, describe, expect, it } from '@ohos/hypium';
import { resetStrings } from '../main/ets/util/strings';
import {
  TypingAction, TYPING_ACTION_TTL_MS, applyTypingUpdate, pruneExpiredTyping, typingLabelOf, chatActionLabelOf, typingActionKind,
  headerTypingTextOf, clearTypingOnNewMessage, headerKindForChatKind
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
      const senders: Map<number, TypingAction> = new Map();
      expect(applyTypingUpdate(senders, chatAction(7, 42, 'chatActionTyping'), NOW, 7, 0, 0, 0))
        .assertEqual(42);
      expect(senders.get(42)?.expiresAt).assertEqual(NOW + 6000);
    });

    it('别的会话的 chatAction 一律忽略', 0, (): void => {
      const senders: Map<number, TypingAction> = new Map();
      expect(applyTypingUpdate(senders, chatAction(8, 42, 'chatActionTyping'), NOW, 7, 0, 0, 0))
        .assertEqual(0);
      expect(senders.size).assertEqual(0);
    });

    it('非用户发送方与非法 uid 都忽略', 0, (): void => {
      const senders: Map<number, TypingAction> = new Map();
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

    it('取消只删除对应用户，录音和上传分别保留', 0, (): void => {
      const senders: Map<number, TypingAction> = new Map();
      // 支持的动作分别保存类型。
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
      const senders: Map<number, TypingAction> = new Map();
      applyTypingUpdate(senders, chatAction(7, 42, 'chatActionTyping'), NOW, 7, 0, 0, 0);
      applyTypingUpdate(senders, chatAction(7, 42, 'chatActionTyping'), NOW + 2000, 7, 0, 0, 0);
      expect(senders.size).assertEqual(1);
      expect(senders.get(42)?.expiresAt).assertEqual(NOW + 2000 + TYPING_ACTION_TTL_MS);
    });

    it('论坛话题：话题对不上的忽略，对得上的照收', 0, (): void => {
      const senders: Map<number, TypingAction> = new Map();
      const other = withForumTopic(chatAction(7, 42, 'chatActionTyping'), 9);
      expect(applyTypingUpdate(senders, other, NOW, 7, 0, 5, 0)).assertEqual(0);
      const mine = withForumTopic(chatAction(7, 42, 'chatActionTyping'), 5);
      expect(applyTypingUpdate(senders, mine, NOW, 7, 0, 5, 0)).assertEqual(42);
      // 没带 topic_id 的在话题视图里也算「不属于本话题」。
      const bare = chatAction(7, 43, 'chatActionTyping');
      expect(applyTypingUpdate(senders, bare, NOW, 7, 0, 5, 0)).assertEqual(0);
    });

    it('私密消息话题同理', 0, (): void => {
      const senders: Map<number, TypingAction> = new Map();
      expect(applyTypingUpdate(senders, withDirectTopic(chatAction(7, 42, 'chatActionTyping'), 9),
        NOW, 7, 0, 0, 5)).assertEqual(0);
      expect(applyTypingUpdate(senders, withDirectTopic(chatAction(7, 42, 'chatActionTyping'), 5),
        NOW, 7, 0, 0, 5)).assertEqual(42);
    });

    it('评论线程按 topic_id.message_thread_id 隔离', 0, (): void => {
      const senders: Map<number, TypingAction> = new Map();
      const update = chatAction(7, 42, 'chatActionTyping');
      expect(applyTypingUpdate(senders, update, NOW, 7, 5, 0, 0)).assertEqual(0);
      const topic: TdObject = { '@type': 'messageTopicThread' };
      topic['message_thread_id'] = 5;
      update['topic_id'] = topic;
      expect(applyTypingUpdate(senders, update, NOW, 7, 5, 0, 0)).assertEqual(42);
      expect(applyTypingUpdate(senders, update, NOW, 7, 6, 0, 0)).assertEqual(0);
    });

    it('正好到期即清除，尚未到期的保留', 0, (): void => {
      const senders: Map<number, TypingAction> = new Map();
      senders.set(1, { kind: 'typing', expiresAt: NOW - 1 });
      senders.set(2, { kind: 'typing', expiresAt: NOW });
      senders.set(3, { kind: 'typing', expiresAt: NOW + 1 });
      expect(pruneExpiredTyping(senders, NOW)).assertTrue();
      expect(senders.has(1)).assertFalse();
      expect(senders.has(2)).assertFalse();
      expect(senders.has(3)).assertTrue();
    });

    it('没东西可丢时返回 false（页面据此不重建文案）', 0, (): void => {
      const senders: Map<number, TypingAction> = new Map();
      expect(pruneExpiredTyping(senders, NOW)).assertFalse();
      senders.set(1, { kind: 'typing', expiresAt: NOW + 6000 });
      expect(pruneExpiredTyping(senders, NOW)).assertFalse();
      expect(senders.size).assertEqual(1);
    });

    it('全过期后清空，页面这时才停掉轮询', 0, (): void => {
      const senders: Map<number, TypingAction> = new Map();
      senders.set(1, { kind: 'typing', expiresAt: NOW });
      senders.set(2, { kind: 'typing', expiresAt: NOW });
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
    // 接收与清理使用同一到期边界。
    it('一条输入正好活满 TTL 才被裁掉', 0, (): void => {
      const senders: Map<number, TypingAction> = new Map();
      applyTypingUpdate(senders, chatAction(7, 42, 'chatActionTyping'), NOW, 7, 0, 0, 0);
      expect(pruneExpiredTyping(senders, NOW + TYPING_ACTION_TTL_MS - 1)).assertFalse();
      expect(senders.size).assertEqual(1);
      expect(pruneExpiredTyping(senders, NOW + TYPING_ACTION_TTL_MS)).assertTrue();
      expect(senders.size).assertEqual(0);
    });

    it('缺 action 字段不创建虚假的输入状态', 0, (): void => {
      const senders: Map<number, TypingAction> = new Map();
      const noAction: TdObject = { '@type': 'updateChatAction' };
      noAction['chat_id'] = 7;
      const sender: TdObject = { '@type': 'messageSenderUser' };
      sender['user_id'] = 42;
      noAction['sender_id'] = sender;
      expect(applyTypingUpdate(senders, noAction, NOW, 7, 0, 0, 0)).assertEqual(0);
      expect(senders.size).assertEqual(0);
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

    it('未知动作既不伪造输入也不续期已有状态', 0, (): void => {
      const senders: Map<number, TypingAction> = new Map();
      applyTypingUpdate(senders, chatAction(7, 42, 'chatActionRecordingVoiceNote'), NOW, 7, 0, 0, 0);
      expect(applyTypingUpdate(senders, chatAction(7, 42, 'futureAction'), NOW + 1000, 7, 0, 0, 0)).assertEqual(0);
      expect(senders.get(42)?.expiresAt).assertEqual(NOW + 6000);
      expect(senders.get(42)?.kind).assertEqual('record_voice');
    });
    it('同一用户从输入变录音，替换状态而非增加人数', 0, (): void => {
      const senders: Map<number, TypingAction> = new Map();
      applyTypingUpdate(senders, chatAction(7, 42, 'chatActionTyping'), NOW, 7, 0, 0, 0);
      applyTypingUpdate(senders, chatAction(7, 42, 'chatActionRecordingVoiceNote'), NOW + 1000, 7, 0, 0, 0);
      expect(senders.size).assertEqual(1);
      expect(chatActionLabelOf('private', senders, (): string => '')).assertEqual('cp_action_record_voice');
    });
    it('普通会话不接收其他话题的操作或取消', 0, (): void => {
      const senders: Map<number, TypingAction> = new Map();
      applyTypingUpdate(senders, chatAction(7, 42, 'chatActionTyping'), NOW, 7, 0, 0, 0);
      expect(applyTypingUpdate(senders, withForumTopic(chatAction(7, 42, 'chatActionCancel'), 5), NOW, 7, 0, 0, 0)).assertEqual(0);
      expect(senders.size).assertEqual(1);
    });
    it('话题数字相同但类型不同不能串入', 0, (): void => {
      const senders: Map<number, TypingAction> = new Map();
      const update = withForumTopic(chatAction(7, 42, 'chatActionTyping'), 5);
      const topic = update['topic_id'] as TdObject;
      topic['@type'] = 'messageTopicThread';
      expect(applyTypingUpdate(senders, update, NOW, 7, 0, 5, 0)).assertEqual(0);
    });
    it('多人同时发送图片显示人数与图片动作', 0, (): void => {
      const senders: Map<number, TypingAction> = new Map();
      applyTypingUpdate(senders, chatAction(7, 1, 'chatActionUploadingPhoto'), NOW, 7, 0, 0, 0);
      applyTypingUpdate(senders, chatAction(7, 2, 'chatActionUploadingPhoto'), NOW, 7, 0, 0, 0);
      expect(chatActionLabelOf('group', senders, (): string => '')).assertEqual('cp_action_members(2,cp_action_upload_photo)');
    });
    it('多人混合操作不谎报都在输入，取消后恢复具体动作', 0, (): void => {
      const senders: Map<number, TypingAction> = new Map();
      applyTypingUpdate(senders, chatAction(7, 1, 'chatActionTyping'), NOW, 7, 0, 0, 0);
      applyTypingUpdate(senders, chatAction(7, 2, 'chatActionUploadingPhoto'), NOW, 7, 0, 0, 0);
      expect(chatActionLabelOf('group', senders, (): string => 'Ann Lee')).assertEqual('cp_action_members(2,cp_action_mixed)');
      applyTypingUpdate(senders, chatAction(7, 1, 'chatActionCancel'), NOW, 7, 0, 0, 0);
      expect(chatActionLabelOf('group', senders, (): string => 'Ann Lee')).assertEqual('cp_action_member(Ann,cp_action_upload_photo)');
    });
    it('群里单人无姓名时采用某人，私聊不查姓名', 0, (): void => {
      const senders: Map<number, TypingAction> = new Map();
      applyTypingUpdate(senders, chatAction(7, 1, 'chatActionChoosingSticker'), NOW, 7, 0, 0, 0);
      let calls = 0;
      const name = (): string => { calls++; return ''; };
      expect(chatActionLabelOf('secret', senders, name)).assertEqual('cp_action_choose_sticker');
      expect(calls).assertEqual(0);
      expect(chatActionLabelOf('group', senders, name)).assertEqual('cp_action_member(cp_someone,cp_action_choose_sticker)');
    });
    it('录音与上传语音、视频与视频消息均保留区别', 0, (): void => {
      const types: string[] = ['RecordingVoiceNote', 'UploadingVoiceNote', 'RecordingVideo',
        'RecordingVideoNote', 'UploadingVideo', 'UploadingVideoNote', 'UploadingDocument'];
      const kinds: string[] = ['record_voice', 'upload_voice', 'record_video',
        'record_video_note', 'upload_video', 'upload_video_note', 'upload_document'];
      types.forEach((type: string, i: number): void => {
        expect(typingActionKind('chatAction' + type)).assertEqual(kinds[i]);
      });
    });
    it('选择联系人位置、游戏与动画不误报输入', 0, (): void => {
      expect(typingActionKind('chatActionChoosingContact')).assertEqual('choose_contact');
      expect(typingActionKind('chatActionChoosingLocation')).assertEqual('choose_location');
      expect(typingActionKind('chatActionStartPlayingGame')).assertEqual('play_game');
      expect(typingActionKind('chatActionWatchingAnimations')).assertEqual('watch_animation');
    });
    it('上传进度变化仅续期不改变动作标签', 0, (): void => {
      const senders: Map<number, TypingAction> = new Map();
      const update = chatAction(7, 1, 'chatActionUploadingPhoto');
      const action = update['action'] as TdObject;
      action['progress'] = 10;
      applyTypingUpdate(senders, update, NOW, 7, 0, 0, 0);
      const before = chatActionLabelOf('private', senders, (): string => '');
      action['progress'] = 90;
      applyTypingUpdate(senders, update, NOW + 500, 7, 0, 0, 0);
      expect(chatActionLabelOf('private', senders, (): string => '')).assertEqual(before);
      expect(senders.get(1)?.expiresAt).assertEqual(NOW + 6500);
    });
    it('顶栏输入文案自动剥除末尾省略号以配合三颗圆点展示', 0, (): void => {
      expect(headerTypingTextOf('')).assertEqual('');
      expect(headerTypingTextOf('正在输入…')).assertEqual('正在输入');
      expect(headerTypingTextOf('小鬼正在输入...')).assertEqual('小鬼正在输入');
      expect(headerTypingTextOf('正在录音')).assertEqual('正在录音');
    });
    it('收到该发送者的新消息时立即清除其正在输入状态，不影响其他输入者', 0, (): void => {
      const senders: Map<number, TypingAction> = new Map();
      applyTypingUpdate(senders, chatAction(7, 42, 'chatActionTyping'), NOW, 7, 0, 0, 0);
      applyTypingUpdate(senders, chatAction(7, 43, 'chatActionTyping'), NOW, 7, 0, 0, 0);
      expect(applyTypingUpdate(senders, chatAction(7, 99, 'chatActionTyping'), NOW, 7, 0, 0, 0, 99)).assertEqual(0);
      const msg: TdObject = {
        '@type': 'message',
        'chat_id': 7,
        'sender_id': { '@type': 'messageSenderUser', 'user_id': 42 } as TdObject
      };
      expect(clearTypingOnNewMessage(senders, msg, 7)).assertTrue();
      expect(senders.has(42)).assertFalse();
      expect(senders.has(43)).assertTrue();
      expect(headerKindForChatKind('private')).assertEqual('private');
      expect(headerKindForChatKind('supergroup')).assertEqual('group');
    });
  });
}
