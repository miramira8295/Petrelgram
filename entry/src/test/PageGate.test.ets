import { describe, expect, it } from '@ohos/hypium';
import {
  armedPageGate, canFirePageGate, firedPageGate, PageGate, rearmPageGate
} from '../main/ets/util/pageGate';

export default function pageGateTest() {
  describe('pageGate', () => {
    it('初始态完全上膛', 0, () => {
      const gate: PageGate = armedPageGate();
      expect(gate.armed).assertTrue();
      expect(gate.firedAtEnd).assertEqual(-1);
      expect(canFirePageGate(gate, 0)).assertTrue();
    });

    it('打一发之后立刻下膛', 0, () => {
      const fired: PageGate = firedPageGate(armedPageGate(), 130);
      expect(fired.armed).assertFalse();
      expect(fired.firedAtEnd).assertEqual(130);
      expect(canFirePageGate(fired, 131)).assertFalse();
    });

    it('内容追加把视口推着往下走，不再放第二发', 0, () => {
      // 真机上的跑飞链条：每追加一页 30 行，stackFromEnd 把视口往下推，end
      // 就涨 ~28。弱闸（end > firedAtEnd）每次都放行，armed 必须挡住。
      let gate: PageGate = firedPageGate(armedPageGate(), 130);
      const ends: number[] = [158, 186, 214, 242, 270, 298, 326, 354];
      for (const end of ends) {
        expect(canFirePageGate(gate, end)).assertFalse();
        // 程序性位移不上膛。
        gate = rearmPageGate(gate, false);
      }
      expect(gate.armed).assertFalse();
      expect(gate.firedAtEnd).assertEqual(130);
    });

    it('只有用户驱动的输入才重新上膛', 0, () => {
      const fired: PageGate = firedPageGate(armedPageGate(), 130);
      expect(rearmPageGate(fired, false).armed).assertFalse();
      const rearmed: PageGate = rearmPageGate(fired, true);
      expect(rearmed.armed).assertTrue();
      expect(rearmed.firedAtEnd).assertEqual(-1);
      // 上膛之后同一个 end 也能再打——用户自己滚回底部就该照常翻页。
      expect(canFirePageGate(rearmed, 130)).assertTrue();
    });

    it('弱闸仍然挡住同一个 end 的重复敲门', 0, () => {
      // 上膛态下 end 没往下走（比如布局抖了一下又报同一批行号）不该重复取页。
      const fired: PageGate = firedPageGate(armedPageGate(), 130);
      const rearmed: PageGate = { armed: true, firedAtEnd: 130 };
      expect(canFirePageGate(rearmed, 130)).assertFalse();
      expect(canFirePageGate(rearmed, 131)).assertTrue();
      expect(fired.firedAtEnd).assertEqual(130);
    });

    it('已经完全上膛时原样返回，不多分配对象', 0, () => {
      const gate: PageGate = armedPageGate();
      expect(rearmPageGate(gate, true) === gate).assertTrue();
      expect(rearmPageGate(gate, false) === gate).assertTrue();
    });

    it('不改原对象', 0, () => {
      const gate: PageGate = armedPageGate();
      firedPageGate(gate, 42);
      expect(gate.armed).assertTrue();
      expect(gate.firedAtEnd).assertEqual(-1);
    });
  });
}
