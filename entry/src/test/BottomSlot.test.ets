import { describe, expect, it } from '@ohos/hypium';
import {
  SLOT_ATTACH, SLOT_EMOJI, SLOT_NONE, SLOT_REPLY_KB,
  claimIfFree, closeAllSlots, closeSlot, openSlot, slotIsDrawer, slotOccupied, toggleSlot
} from '../main/ets/util/bottomSlot';

// 一块高度只有一个主人：任何一个打开，另外两个自动让位。
export default function bottomSlotTest() {
  describe('bottomSlot', () => {
    it('打开一个就顶掉另一个', 0, () => {
      expect(openSlot(SLOT_EMOJI, SLOT_ATTACH)).assertEqual(SLOT_ATTACH);
      expect(openSlot(SLOT_ATTACH, SLOT_EMOJI)).assertEqual(SLOT_EMOJI);
      // 这一条是此前缺的：开附件也该收起机器人键盘。
      expect(openSlot(SLOT_REPLY_KB, SLOT_ATTACH)).assertEqual(SLOT_ATTACH);
      expect(openSlot(SLOT_EMOJI, SLOT_REPLY_KB)).assertEqual(SLOT_REPLY_KB);
    });

    it('异步到达只在空位时入座，不顶掉用户开着的抽屉', 0, () => {
      expect(claimIfFree(SLOT_NONE, SLOT_REPLY_KB)).assertEqual(SLOT_REPLY_KB);
      expect(claimIfFree(SLOT_ATTACH, SLOT_REPLY_KB)).assertEqual(SLOT_ATTACH);
      expect(claimIfFree(SLOT_EMOJI, SLOT_REPLY_KB)).assertEqual(SLOT_EMOJI);
    });

    it('点同一个入口第二次是收起', 0, () => {
      expect(toggleSlot(SLOT_ATTACH, SLOT_ATTACH)).assertEqual(SLOT_NONE);
      expect(toggleSlot(SLOT_NONE, SLOT_ATTACH)).assertEqual(SLOT_ATTACH);
      expect(toggleSlot(SLOT_EMOJI, SLOT_ATTACH)).assertEqual(SLOT_ATTACH);
    });

    it('关闭只对当前占位者生效', 0, () => {
      expect(closeSlot(SLOT_EMOJI, SLOT_EMOJI)).assertEqual(SLOT_NONE);
      // 表情占着的时候关附件，不该把表情也关掉。
      expect(closeSlot(SLOT_EMOJI, SLOT_ATTACH)).assertEqual(SLOT_EMOJI);
      expect(closeAllSlots()).assertEqual(SLOT_NONE);
    });

    it('是否占位', 0, () => {
      expect(slotOccupied(SLOT_NONE)).assertFalse();
      expect(slotOccupied(SLOT_REPLY_KB)).assertTrue();
    });

    it('只有抽屉需要让出系统键盘的高度', 0, () => {
      expect(slotIsDrawer(SLOT_ATTACH)).assertTrue();
      expect(slotIsDrawer(SLOT_EMOJI)).assertTrue();
      // 机器人键盘是随消息来的一排按钮，和系统键盘可以并存。
      expect(slotIsDrawer(SLOT_REPLY_KB)).assertFalse();
      expect(slotIsDrawer(SLOT_NONE)).assertFalse();
    });
  });
}
