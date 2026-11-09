import { describe, it, expect } from '@ohos/hypium';
import { ChangeDrainQueue } from '../main/ets/util/changeDrainQueue';

// 贴纸抽屉 CHANGE 分帧：每帧只放几个，可视范围内的先放，屏外按离可视范围的远近排（2026-09-15）。

export default function changeDrainQueueTest() {
  describe('changeDrainQueue', () => {
    it('可视范围内的先取，并受每批上限约束', 0, () => {
      const q = new ChangeDrainQueue();
      [40, 3, 12, 11, 10, 90].forEach((i: number): void => { q.add(i); });
      expect(q.takeBatch(10, 20, 2).join(',')).assertEqual('10,11');
      expect(q.size()).assertEqual(4);
    });

    it('可视范围内的取完再按距离取屏外的', 0, () => {
      const q = new ChangeDrainQueue();
      [40, 3, 12, 90, 22].forEach((i: number): void => { q.add(i); });
      expect(q.takeBatch(10, 20, 3).join(',')).assertEqual('12,22,3');
      expect(q.takeBatch(10, 20, 3).join(',')).assertEqual('40,90');
      expect(q.size()).assertEqual(0);
    });

    it('同一下标重复加入只算一次', 0, () => {
      const q = new ChangeDrainQueue();
      q.add(5);
      q.add(5);
      expect(q.size()).assertEqual(1);
      expect(q.takeBatch(0, 10, 4).join(',')).assertEqual('5');
    });

    it('清空之后什么都取不到', 0, () => {
      const q = new ChangeDrainQueue();
      q.add(1);
      q.add(2);
      q.clear();
      expect(q.takeBatch(0, 10, 4).length).assertEqual(0);
    });

    it('上限为 0 或负下标不入队', 0, () => {
      const q = new ChangeDrainQueue();
      q.add(-1);
      q.add(3);
      expect(q.size()).assertEqual(1);
      expect(q.takeBatch(0, 10, 0).length).assertEqual(0);
      expect(q.size()).assertEqual(1);
    });
  });
}
