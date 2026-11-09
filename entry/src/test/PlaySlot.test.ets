import { describe, it, expect } from '@ohos/hypium';
import {
  pickPlaySlot, slotKey, slotKeyMessageId, shouldCompete, autoplaySizeAllowed, PlaySlotCandidate,
  PLAY_SLOT_ENTER_RATIO, PLAY_SLOT_KEEP_RATIO
} from '../main/ets/pages/chat/playSlot';

function cand(messageId: number, ratio: number, centerY: number,
  albumIndex: number = -1): PlaySlotCandidate {
  return {
    key: slotKey(messageId, albumIndex),
    messageId, albumIndex, ratio, centerY
  };
}

export default function playSlotTest() {
  describe('playSlot', () => {
    // #226：只自动播放小于设定大小的视频。
    it('自动播放大小上限：0 是不限，大小未知一律放行，超过才拦', 0, () => {
      const mb: number = 1024 * 1024;
      expect(autoplaySizeAllowed(500 * mb, 0)).assertTrue();
      expect(autoplaySizeAllowed(0, 10)).assertTrue();
      expect(autoplaySizeAllowed(10 * mb, 10)).assertTrue();
      expect(autoplaySizeAllowed(10 * mb + 1, 10)).assertFalse();
      expect(autoplaySizeAllowed(3 * mb, 10)).assertTrue();
    });

    it('阈值本身是有序的', 0, () => {
      expect(PLAY_SLOT_ENTER_RATIO > PLAY_SLOT_KEEP_RATIO).assertTrue();
    });

    it('相册成员与整条消息的 key 不会相撞', 0, () => {
      expect(slotKey(7, -1) === slotKey(7, 0)).assertFalse();
      expect(slotKey(7, 0) === slotKey(7, 1)).assertFalse();
      expect(slotKey(7, -1)).assertEqual(slotKey(7, -1));
    });

    it('没有候选就没有播放位', 0, () => {
      const none: PlaySlotCandidate[] = [];
      expect(pickPlaySlot(none, 500, '', '')).assertEqual('');
    });

    it('可见比例不到入选线的一律落选', 0, () => {
      const list: PlaySlotCandidate[] = [cand(1, 0.5, 500)];
      expect(pickPlaySlot(list, 500, '', '')).assertEqual('');
    });

    it('可见比例最高者当选', 0, () => {
      const list: PlaySlotCandidate[] = [cand(1, 0.7, 300), cand(2, 0.95, 800)];
      expect(pickPlaySlot(list, 500, '', '')).assertEqual(slotKey(2, -1));
    });

    it('比例相同则取离视口中心更近的', 0, () => {
      const list: PlaySlotCandidate[] = [cand(1, 0.8, 200), cand(2, 0.8, 520)];
      expect(pickPlaySlot(list, 500, '', '')).assertEqual(slotKey(2, -1));
    });

    it('迟滞：现任只要还在保持线上就不换届，哪怕对手更高', 0, () => {
      const list: PlaySlotCandidate[] = [cand(1, 0.45, 200), cand(2, 0.9, 520)];
      expect(pickPlaySlot(list, 500, slotKey(1, -1), '')).assertEqual(slotKey(1, -1));
    });

    it('现任跌破保持线就换届', 0, () => {
      const list: PlaySlotCandidate[] = [cand(1, 0.3, 200), cand(2, 0.9, 520)];
      expect(pickPlaySlot(list, 500, slotKey(1, -1), '')).assertEqual(slotKey(2, -1));
    });

    it('现任已经不在候选表里也要换届', 0, () => {
      const list: PlaySlotCandidate[] = [cand(2, 0.9, 520)];
      expect(pickPlaySlot(list, 500, slotKey(1, -1), '')).assertEqual(slotKey(2, -1));
    });

    it('用户手动点播的锁定项优先于比例最高者', 0, () => {
      const list: PlaySlotCandidate[] = [cand(1, 0.45, 200), cand(2, 0.99, 520)];
      expect(pickPlaySlot(list, 500, '', slotKey(1, -1))).assertEqual(slotKey(1, -1));
    });

    it('锁定项跌破保持线即释放，让位给比例最高者', 0, () => {
      const list: PlaySlotCandidate[] = [cand(1, 0.2, 200), cand(2, 0.99, 520)];
      expect(pickPlaySlot(list, 500, '', slotKey(1, -1))).assertEqual(slotKey(2, -1));
    });

    it('锁定项不在候选表里就当没锁定', 0, () => {
      const list: PlaySlotCandidate[] = [cand(2, 0.99, 520)];
      expect(pickPlaySlot(list, 500, '', slotKey(9, -1))).assertEqual(slotKey(2, -1));
    });

    it('相册里最多只有一格当选', 0, () => {
      const list: PlaySlotCandidate[] = [cand(5, 0.8, 480, 0), cand(5, 0.9, 520, 1)];
      const got = pickPlaySlot(list, 500, '', '');
      expect(got).assertEqual(slotKey(5, 1));
    });

    it('入选线是包含边界的', 0, () => {
      const list: PlaySlotCandidate[] = [cand(1, PLAY_SLOT_ENTER_RATIO, 500)];
      expect(pickPlaySlot(list, 500, '', '')).assertEqual(slotKey(1, -1));
    });

    it('比例与离视口中心距离都相同时保留先出现者', 0, () => {
      const list: PlaySlotCandidate[] = [cand(1, 0.8, 400), cand(2, 0.8, 600)];
      expect(pickPlaySlot(list, 500, '', '')).assertEqual(slotKey(1, -1));
    });

    it('slotKeyMessageId 取回消息 id', 0, () => {
      expect(slotKeyMessageId(slotKey(42, -1))).assertEqual(42);
      expect(slotKeyMessageId(slotKey(42, 3))).assertEqual(42);
      expect(slotKeyMessageId('')).assertEqual(0);
      expect(slotKeyMessageId('nope')).assertEqual(0);
    });

    // shouldCompete 全矩阵：三个开关 × 是否动图。只有「自动播放开 + 非省电 +
    // 非减少动效 + 不是动图」这一种组合才允许竞选，其余全部为 false。
    it('三个开关全部允许且不是动图时才参加竞选', 0, () => {
      expect(shouldCompete(true, false, false, false)).assertTrue();
    });

    it('关掉自动播放视频就不竞选', 0, () => {
      expect(shouldCompete(false, false, false, false)).assertFalse();
    });

    it('省电模式下不竞选', 0, () => {
      expect(shouldCompete(true, true, false, false)).assertFalse();
    });

    it('减少动效下不竞选', 0, () => {
      expect(shouldCompete(true, false, true, false)).assertFalse();
    });

    it('动图恒不参加竞选（开关全开也一样）', 0, () => {
      expect(shouldCompete(true, false, false, true)).assertFalse();
    });

    it('shouldCompete 全 16 种组合逐一核对', 0, () => {
      const flags: boolean[] = [false, true];
      for (const autoplay of flags) {
        for (const saving of flags) {
          for (const reduce of flags) {
            for (const animation of flags) {
              const want: boolean = autoplay && !saving && !reduce && !animation;
              const got: boolean = shouldCompete(autoplay, saving, reduce, animation);
              expect(got).assertEqual(want);
            }
          }
        }
      }
    });
  });
}
