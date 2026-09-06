import { describe, expect, it } from '@ohos/hypium';
import {
  CHAT_LIST_TOUCH_HOLD, CHAT_MENU_OPEN, ChatListFreeze, chatOrderUnchanged
} from '../main/ets/pages/chatlist/ChatListFreeze';
import { ChatEntry } from '../main/ets/store/ChatEntry';

// 闸门只看「发布还是缓冲」，不看内容——空数组的身份就足够断言。
function snapshot(): ChatEntry[] {
  return [] as ChatEntry[];
}

// chatOrderUnchanged 只读 id 和长度，其余字段给合法默认值即可。
function chat(id: number): ChatEntry {
  return {
    id, revision: 0, title: `c${id}`, isMuted: false, usesDefaultMute: true,
    unreadCount: 0, rawUnreadCount: 0, lastReadInboxId: 0,
    lastMessageText: '', lastMessageDate: 0, lastMessageId: 0, lastSenderName: '',
    photoFileId: 0, avatarPath: '', initials: '', autoDeleteTime: 0,
    kind: 'supergroup', isMarkedUnread: false,
    canDeleteOnlyForSelf: false, canDeleteForAllUsers: false,
    isSavedMessages: false, background: null, themeName: '',
    liveGroupCallId: 0, isLive: false, isRtmpLive: false
  };
}

function chats(ids: number[]): ChatEntry[] {
  return ids.map((id: number): ChatEntry => chat(id));
}

function openAllGates(): void {
  AppStorage.setOrCreate(CHAT_MENU_OPEN, false);
  AppStorage.setOrCreate(CHAT_LIST_TOUCH_HOLD, false);
}

export default function chatListFreezeTest() {
  describe('chatListFreeze', () => {
    it('闸全开时直通', 0, (): void => {
      openAllGates();
      const gate = new ChatListFreeze();
      const list = snapshot();
      expect(gate.accept(list, true) === list).assertTrue();
      // 直通后没有积压。
      expect(gate.flush() === null).assertTrue();
    });
    it('触摸按住时缓冲，flush 只吐最新一份', 0, (): void => {
      openAllGates();
      AppStorage.setOrCreate(CHAT_LIST_TOUCH_HOLD, true);
      const gate = new ChatListFreeze();
      const first = snapshot();
      const second = snapshot();
      expect(gate.accept(first, true) === null).assertTrue();
      expect(gate.accept(second, true) === null).assertTrue();
      AppStorage.setOrCreate(CHAT_LIST_TOUCH_HOLD, false);
      expect(gate.flush() === second).assertTrue();
      expect(gate.flush() === null).assertTrue();
    });
    it('菜单开着时同样缓冲（原有行为不回归）', 0, (): void => {
      openAllGates();
      AppStorage.setOrCreate(CHAT_MENU_OPEN, true);
      const gate = new ChatListFreeze();
      expect(gate.accept(snapshot(), true) === null).assertTrue();
      AppStorage.setOrCreate(CHAT_MENU_OPEN, false);
      expect(gate.flush() !== null).assertTrue();
    });
    it('开闸后的 accept 直通并清掉积压', 0, (): void => {
      openAllGates();
      AppStorage.setOrCreate(CHAT_LIST_TOUCH_HOLD, true);
      const gate = new ChatListFreeze();
      gate.accept(snapshot(), true);
      AppStorage.setOrCreate(CHAT_LIST_TOUCH_HOLD, false);
      const live = snapshot();
      expect(gate.accept(live, true) === live).assertTrue();
      expect(gate.flush() === null).assertTrue();
    });
    it('renderActive 为 false 时不受触摸闸影响照样缓冲', 0, (): void => {
      openAllGates();
      const gate = new ChatListFreeze();
      expect(gate.accept(snapshot(), false) === null).assertTrue();
      expect(gate.flush() !== null).assertTrue();
    });
  });

  // issue #159 的返回转场旁路要靠这个判断决定"能不能在闸关着时放行"：
  // 只有内容变了的快照可以直接发；顺序变了的必须等闸开，否则重排动画正好
  // 压在返回转场那 640ms 上——那就是这道闸当初存在的理由。
  describe('chatOrderUnchanged', () => {
    it('同一串 id 同一个顺序 ⇒ 只是内容变了', 0, (): void => {
      const before = chats([7, 8, 9]);
      const after = chats([7, 8, 9]);
      after[1].unreadCount = 12;
      after[1].lastMessageText = 'hi';
      // 内容随便怎么变都不影响判断：它只问身份顺序。
      expect(chatOrderUnchanged(before, after)).assertTrue();
    });
    it('置顶/新消息导致重排 ⇒ 顺序变了', 0, (): void => {
      expect(chatOrderUnchanged(chats([7, 8, 9]), chats([9, 7, 8]))).assertFalse();
    });
    it('长度不同 ⇒ 顺序变了（新会话进来 / 会话被删）', 0, (): void => {
      expect(chatOrderUnchanged(chats([7, 8]), chats([7, 8, 9]))).assertFalse();
      expect(chatOrderUnchanged(chats([7, 8, 9]), chats([7, 8]))).assertFalse();
    });
    it('两边都空 ⇒ 算没变（首帧空列表不该被当成重排）', 0, (): void => {
      expect(chatOrderUnchanged([], [])).assertTrue();
    });
    it('同一批 id 换了位置但长度相同 ⇒ 仍然算变了', 0, (): void => {
      // 只比长度会漏掉这一档，钉住逐项比较。
      expect(chatOrderUnchanged(chats([1, 2]), chats([2, 1]))).assertFalse();
    });
  });
}
