import { describe, expect, it } from '@ohos/hypium';
import {
  CHAT_LIST_TOUCH_HOLD, CHAT_MENU_OPEN, ChatListFreeze
} from '../main/ets/pages/chatlist/ChatListFreeze';
import { ChatEntry } from '../main/ets/store/ChatEntry';

// 闸门只看「发布还是缓冲」，不看内容——空数组的身份就足够断言。
function snapshot(): ChatEntry[] {
  return [] as ChatEntry[];
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
}
