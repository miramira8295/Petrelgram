import { describe, it, expect } from '@ohos/hypium';
import { PinUpdate, updateBoundedPins } from '../main/ets/util/boundedPins';

// 「有上限的钉」的顺序逻辑。头像被大图挤出 LRU 会闪（issue #137），钉住能治；
// 但无上限地钉会随发送者数量一路涨，所以只保最近 N 张。

function order(u: PinUpdate): string {
  return u.next.join(',');
}

export default function boundedPinsTest() {
  describe('boundedPins', () => {

    it('新 key 追加到末尾', 0, (): void => {
      expect(order(updateBoundedPins(['a', 'b'], 'c', 5))).assertEqual('a,b,c');
    });

    it('已钉住的 key 挪到末尾——刷新它的最近使用', 0, (): void => {
      expect(order(updateBoundedPins(['a', 'b', 'c'], 'a', 5))).assertEqual('b,c,a');
    });

    it('重复钉同一个 key 不会长出第二份', 0, (): void => {
      const u: PinUpdate = updateBoundedPins(['a'], 'a', 5);
      expect(u.next.length).assertEqual(1);
      expect(u.released.length).assertEqual(0);
    });

    it('超出上限时松开最旧的', 0, (): void => {
      const u: PinUpdate = updateBoundedPins(['a', 'b'], 'c', 2);
      expect(order(u)).assertEqual('b,c');
      expect(u.released.join(',')).assertEqual('a');
    });

    it('一次超出多个时按从旧到新松开', 0, (): void => {
      const u: PinUpdate = updateBoundedPins(['a', 'b', 'c', 'd'], 'e', 2);
      expect(order(u)).assertEqual('d,e');
      expect(u.released.join(',')).assertEqual('a,b,c');
    });

    it('刷新最近使用不会误伤——被挪走的那个不算松开', 0, (): void => {
      const u: PinUpdate = updateBoundedPins(['a', 'b'], 'a', 2);
      expect(order(u)).assertEqual('b,a');
      expect(u.released.length).assertEqual(0);
    });

    it('上限为 0 时什么都不钉', 0, (): void => {
      const u: PinUpdate = updateBoundedPins(['a'], 'b', 0);
      expect(order(u)).assertEqual('a');
      expect(u.released.length).assertEqual(0);
    });

    it('空 key 忽略', 0, (): void => {
      expect(order(updateBoundedPins(['a'], '', 5))).assertEqual('a');
    });

    it('不修改入参数组', 0, (): void => {
      const before: string[] = ['a', 'b'];
      updateBoundedPins(before, 'c', 2);
      expect(before.join(',')).assertEqual('a,b');
    });
  });
}
