import { beforeEach, describe, expect, it } from '@ohos/hypium';
import { TypingIndicatorState, TypingIndicatorHost, TypingIndicatorDependencies } from '../main/ets/pages/chat/TypingIndicatorState';
import { TdObject } from '../main/ets/tdkit/TdTypes';
import { resetStrings } from '../main/ets/util/strings';

class FakeHost implements TypingIndicatorHost {
  chat: number = 7;
  thread: number = 0;
  kind: string = 'group';
  chatId = (): number => this.chat;
  threadRootId = (): number => this.thread;
  forumTopicId = (): number => 0;
  directMessagesTopicId = (): number => 0;
  currentKind = (): string => this.kind;
}
interface PendingExpiry {
  callback: () => void;
  at: number;
}
class FakeClock implements TypingIndicatorDependencies {
  time: number = 10000;
  next: number = 0;
  timers: Map<number, PendingExpiry> = new Map();
  names: Map<number, string> = new Map();
  ensured: number[] = [];
  now = (): number => this.time;
  ensureUser = (uid: number): void => { this.ensured.push(uid); };
  displayName = (uid: number): string => this.names.get(uid) ?? '';
  schedule = (callback: () => void, delay: number): number => {
    const id = ++this.next;
    this.timers.set(id, { callback: callback, at: this.time + delay });
    return id;
  };
  cancel = (id: number): void => { this.timers.delete(id); };
  advance(ms: number): void {
    this.time += ms;
    for (const id of Array.from(this.timers.keys())) {
      const task = this.timers.get(id);
      if (task !== undefined && task.at <= this.time) {
        this.timers.delete(id);
        task.callback();
      }
    }
  }
}
function chatAction(uid: number, type: string = 'chatActionTyping', chat: number = 7): TdObject {
  const sender: TdObject = { '@type': 'messageSenderUser' };
  sender['user_id'] = uid;
  const action: TdObject = { '@type': type };
  const update: TdObject = { '@type': 'updateChatAction' };
  update['chat_id'] = chat;
  update['sender_id'] = sender;
  update['action'] = action;
  return update;
}
function controllerOn(host: FakeHost, clock: FakeClock): TypingIndicatorState {
  const state = new TypingIndicatorState(clock);
  state.bind(host);
  return state;
}
export default function typingIndicatorStateTest() {
  describe('TypingIndicatorState', () => {
    beforeEach((): void => { resetStrings(); });

    it('单人变多人再取消一人，标签立即准确更新', 0, (): void => {
      const clock = new FakeClock();
      clock.names.set(1, 'Ann Lee');
      const state = controllerOn(new FakeHost(), clock);
      state.onChatAction(chatAction(1));
      expect(state.label).assertEqual('cp_someone_typing(Ann)');
      state.onChatAction(chatAction(2));
      expect(state.label).assertEqual('cp_n_typing(2,2)');
      state.onChatAction(chatAction(2, 'chatActionCancel'));
      expect(state.label).assertEqual('cp_someone_typing(Ann)');
      state.dispose();
    });
    it('聊天类型现取，不缓存初始身份', 0, (): void => {
      const clock = new FakeClock();
      const host = new FakeHost();
      host.kind = 'private';
      const state = controllerOn(host, clock);
      state.onChatAction(chatAction(1));
      state.onChatAction(chatAction(2));
      expect(state.label).assertEqual('cp_typing');
      host.kind = 'group';
      state.onChatAction(chatAction(2));
      expect(state.label).assertEqual('cp_n_typing(2,2)');
      state.dispose();
    });
    it('恰好6000ms到期清空并停止计时', 0, (): void => {
      const clock = new FakeClock();
      const state = controllerOn(new FakeHost(), clock);
      state.onChatAction(chatAction(1));
      clock.advance(5999);
      expect(state.label === '').assertFalse();
      clock.advance(1);
      expect(state.label).assertEqual('');
      expect(clock.timers.size).assertEqual(0);
    });
    it('到期后收到下一轮动作仍能正常计时清除', 0, (): void => {
      const clock = new FakeClock();
      const state = controllerOn(new FakeHost(), clock);
      state.onChatAction(chatAction(1));
      clock.advance(6000);
      state.onChatAction(chatAction(2, 'chatActionUploadingPhoto'));
      expect(state.label).assertEqual('cp_action_member(cp_someone,cp_action_upload_photo)');
      clock.advance(6000);
      expect(state.label).assertEqual('');
      expect(clock.timers.size).assertEqual(0);
    });
    it('销毁清理状态，排队的旧回调与后续更新均不能复活', 0, (): void => {
      const clock = new FakeClock();
      const state = controllerOn(new FakeHost(), clock);
      state.onChatAction(chatAction(1));
      const callback = Array.from(clock.timers.values())[0].callback;
      state.dispose();
      expect(state.label).assertEqual('');
      state.onChatAction(chatAction(2));
      callback();
      expect(state.label).assertEqual('');
      expect(clock.timers.size).assertEqual(0);
    });
    it('多页面实例独立，销毁一页不影响另一页', 0, (): void => {
      const clockA = new FakeClock();
      const clockB = new FakeClock();
      const hostB = new FakeHost();
      hostB.chat = 8;
      hostB.kind = 'private';
      const a = controllerOn(new FakeHost(), clockA);
      const b = controllerOn(hostB, clockB);
      a.onChatAction(chatAction(1));
      expect(b.label).assertEqual('');
      b.onChatAction(chatAction(2, 'chatActionRecordingVoiceNote', 8));
      a.dispose();
      expect(b.label).assertEqual('cp_action_record_voice');
      clockB.advance(6000);
      expect(b.label).assertEqual('');
    });
    it('取消最后一个人立即停表，不为取消查询资料', 0, (): void => {
      const clock = new FakeClock();
      const state = controllerOn(new FakeHost(), clock);
      state.onChatAction(chatAction(1));
      state.onChatAction(chatAction(1, 'chatActionCancel'));
      expect(state.label).assertEqual('');
      expect(clock.timers.size).assertEqual(0);
      expect(clock.ensured.length).assertEqual(1);
    });
    it('续期只保留一个计时器，旧回调不能提前清空新状态', 0, (): void => {
      const clock = new FakeClock();
      const state = controllerOn(new FakeHost(), clock);
      state.onChatAction(chatAction(1));
      const stale = Array.from(clock.timers.values())[0].callback;
      clock.advance(4000);
      state.onChatAction(chatAction(1, 'chatActionRecordingVoiceNote'));
      expect(clock.timers.size).assertEqual(1);
      clock.advance(2000);
      stale();
      expect(state.label).assertEqual('cp_action_member(cp_someone,cp_action_record_voice)');
      clock.advance(4000);
      expect(state.label).assertEqual('');
    });
    it('多人分别到期，先更新为剩余用户的具体动作', 0, (): void => {
      const clock = new FakeClock();
      const state = controllerOn(new FakeHost(), clock);
      state.onChatAction(chatAction(1));
      clock.advance(2000);
      state.onChatAction(chatAction(2, 'chatActionUploadingPhoto'));
      expect(state.label).assertEqual('cp_action_members(2,cp_action_mixed)');
      clock.advance(4000);
      expect(state.label).assertEqual('cp_action_member(cp_someone,cp_action_upload_photo)');
      expect(clock.timers.size).assertEqual(1);
      clock.advance(2000);
      expect(state.label).assertEqual('');
    });
    it('页面隐藏清理且忽略更新，恢复等待新动作不复活旧状态', 0, (): void => {
      const clock = new FakeClock();
      const state = controllerOn(new FakeHost(), clock);
      state.onChatAction(chatAction(1));
      state.setActive(false);
      state.onChatAction(chatAction(2));
      expect(state.label).assertEqual('');
      expect(clock.timers.size).assertEqual(0);
      state.setActive(true);
      expect(state.label).assertEqual('');
      state.onChatAction(chatAction(3));
      expect(state.label === '').assertFalse();
      state.dispose();
    });
    it('切换会话作用域不会混入上一会话发送者', 0, (): void => {
      const clock = new FakeClock();
      const host = new FakeHost();
      const state = controllerOn(host, clock);
      state.onChatAction(chatAction(1));
      host.chat = 8;
      state.onChatAction(chatAction(2, 'chatActionUploadingVideo', 8));
      expect(state.label).assertEqual('cp_action_member(cp_someone,cp_action_upload_video)');
      state.dispose();
    });
    it('重新绑定清除旧状态和计时器', 0, (): void => {
      const clock = new FakeClock();
      const state = controllerOn(new FakeHost(), clock);
      state.onChatAction(chatAction(1));
      state.bind(new FakeHost());
      expect(state.label).assertEqual('');
      expect(clock.timers.size).assertEqual(0);
    });
    it('资料返回后补齐名字，不续期操作状态', 0, (): void => {
      const clock = new FakeClock();
      const state = controllerOn(new FakeHost(), clock);
      state.onChatAction(chatAction(1, 'chatActionRecordingVoiceNote'));
      expect(state.label).assertEqual('cp_action_member(cp_someone,cp_action_record_voice)');
      clock.advance(4000);
      clock.names.set(1, 'Ann Lee');
      const user: TdObject = { '@type': 'user' };
      user['id'] = 1;
      const update: TdObject = { '@type': 'updateUser' };
      update['user'] = user;
      state.onUserUpdate(update);
      expect(state.label).assertEqual('cp_action_member(Ann,cp_action_record_voice)');
      clock.advance(2000);
      expect(state.label).assertEqual('');
    });
    it('没有有效动作时不创建计时器或查询用户', 0, (): void => {
      const clock = new FakeClock();
      const state = controllerOn(new FakeHost(), clock);
      state.onChatAction(chatAction(1, 'futureAction'));
      state.onChatAction(chatAction(2, 'chatActionTyping', 8));
      expect(clock.timers.size).assertEqual(0);
      expect(clock.ensured.length).assertEqual(0);
      expect(state.label).assertEqual('');
    });
  });
}
