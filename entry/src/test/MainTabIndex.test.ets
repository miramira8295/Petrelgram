import { describe, it, expect } from '@ohos/hypium';
import {
  logicalTabIndex, physicalTabIndex, TAB_CHATS, TAB_CONTACTS, TAB_PROFILE, TAB_SETTINGS,
  visibleTabCount
} from '../main/ets/util/mainTabIndex';

export default function mainTabIndexTest() {
  describe('mainTabIndex', () => {
    it('联系人开着时是恒等映射', 0, (): void => {
      for (let i = 0; i < 4; i++) {
        expect(physicalTabIndex(i, true)).assertEqual(i);
        expect(logicalTabIndex(i, true)).assertEqual(i);
      }
      expect(visibleTabCount(true)).assertEqual(4);
    });

    // 关掉联系人：物理槽位只剩三个，设置和我的各前移一位。
    it('关掉联系人后设置/我的各前移一位', 0, (): void => {
      expect(physicalTabIndex(TAB_CHATS, false)).assertEqual(0);
      expect(physicalTabIndex(TAB_SETTINGS, false)).assertEqual(1);
      expect(physicalTabIndex(TAB_PROFILE, false)).assertEqual(2);
      expect(visibleTabCount(false)).assertEqual(3);
    });

    it('往返换算必须自洽，否则点一下会跳到别的页签', 0, (): void => {
      for (const logical of [TAB_CHATS, TAB_SETTINGS, TAB_PROFILE]) {
        expect(logicalTabIndex(physicalTabIndex(logical, false), false)).assertEqual(logical);
      }
    });

    // 联系人被关掉的那一刻可能正停在它上面：没有物理槽位，退回会话。
    it('停在被关掉的联系人上时落回会话', 0, (): void => {
      expect(physicalTabIndex(TAB_CONTACTS, false)).assertEqual(TAB_CHATS);
    });
  });
}
