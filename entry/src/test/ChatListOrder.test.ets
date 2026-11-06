import { describe, expect, it } from '@ohos/hypium';
import { ChatListOrder, PositionChange } from '../main/ets/store/chatListOrder';

// 位置索引的行为钉死在这里。ChatStore 现在只是委托方；任何一条规则反过来
// 也会让会话列表的排序、置顶分段、角标失效判据跟着变。
function allExist(_id: number): boolean {
  return true;
}

function idsOf(order: ChatListOrder, listKey: string): string {
  return order.orderedIds(listKey).join(',');
}

export default function chatListOrderTest() {
  describe('chatListOrder', () => {
    it('置顶在前，段内按 order 降序', 0, (): void => {
      const order = new ChatListOrder(allExist);
      order.apply('main', 1, '100', false);
      order.apply('main', 2, '300', false);
      order.apply('main', 3, '200', true);
      order.apply('main', 4, '400', true);
      // 置顶段：400 > 200；普通段：300 > 100
      expect(idsOf(order, 'main')).assertEqual('4,3,2,1');
    });

    it('order 为 0 表示移出列表，移出后不再出现在序列里', 0, (): void => {
      const order = new ChatListOrder(allExist);
      order.apply('main', 1, '100', false);
      order.apply('main', 2, '200', false);
      expect(idsOf(order, 'main')).assertEqual('2,1');
      order.apply('main', 2, '0', false);
      expect(idsOf(order, 'main')).assertEqual('1');
      expect(order.contains('main', 2)).assertFalse();
    });

    it('同一位置重复推入不会产生重复项', 0, (): void => {
      const order = new ChatListOrder(allExist);
      order.apply('main', 1, '100', false);
      order.apply('main', 2, '200', false);
      order.apply('main', 1, '100', false);
      expect(idsOf(order, 'main')).assertEqual('2,1');
      expect(order.sizeOf('main')).assertEqual(2);
    });

    it('位置变化就地维护序列，不必整表重排', 0, (): void => {
      const order = new ChatListOrder(allExist);
      order.apply('main', 1, '100', false);
      order.apply('main', 2, '200', false);
      expect(idsOf(order, 'main')).assertEqual('2,1');
      // 把 1 的 order 调到最高：不需要重新排序，二分插到最前。
      order.apply('main', 1, '900', false);
      expect(idsOf(order, 'main')).assertEqual('1,2');
      // 再降回来。
      order.apply('main', 1, '050', false);
      expect(idsOf(order, 'main')).assertEqual('2,1');
    });

    it('置顶位变化会推进 pinEpoch，移出置顶项同样推进', 0, (): void => {
      const order = new ChatListOrder(allExist);
      expect(order.pinEpoch('main')).assertEqual(0);
      order.apply('main', 1, '100', false);
      expect(order.pinEpoch('main')).assertEqual(0);
      const pinned: PositionChange = order.apply('main', 1, '100', true);
      expect(pinned.pinChanged).assertTrue();
      expect(order.pinEpoch('main')).assertEqual(1);
      // 顺序变化但不动置顶位：纪元不变。
      order.apply('main', 1, '900', true);
      expect(order.pinEpoch('main')).assertEqual(1);
      // 移出置顶项：纪元推进。
      order.apply('main', 1, '0', false);
      expect(order.pinEpoch('main')).assertEqual(2);
    });

    it('副作用清单：加入/移出/置顶位变化分别上报', 0, (): void => {
      const order = new ChatListOrder(allExist);
      const added: PositionChange = order.apply('main', 1, '100', false);
      expect(added.added).assertTrue();
      expect(added.removed).assertFalse();
      expect(added.pinChanged).assertFalse();
      const reordered: PositionChange = order.apply('main', 1, '200', false);
      expect(reordered.added).assertFalse();
      expect(reordered.removed).assertFalse();
      const pinned: PositionChange = order.apply('main', 1, '200', true);
      expect(pinned.pinChanged).assertTrue();
      const removed: PositionChange = order.apply('main', 1, '0', false);
      expect(removed.removed).assertTrue();
      expect(removed.pinChanged).assertTrue();
    });

    it('没有实体的 id 不进序列，但位置表里留着', 0, (): void => {
      const order = new ChatListOrder((id: number): boolean => id !== 3);
      order.apply('main', 1, '100', false);
      order.apply('main', 3, '300', false);
      order.apply('main', 2, '200', false);
      expect(idsOf(order, 'main')).assertEqual('2,1');
      expect(order.contains('main', 3)).assertTrue();
      expect(order.sizeOf('main')).assertEqual(3);
    });

    it('不同列表各排各的，置顶也是按列表算', 0, (): void => {
      const order = new ChatListOrder(allExist);
      order.apply('main', 1, '100', true);
      order.apply('main', 2, '200', false);
      order.apply('folder:7', 1, '100', false);
      order.apply('folder:7', 2, '200', true);
      expect(idsOf(order, 'main')).assertEqual('1,2');
      expect(idsOf(order, 'folder:7')).assertEqual('2,1');
      expect(order.isPinned('main', 1)).assertTrue();
      expect(order.isPinned('folder:7', 1)).assertFalse();
    });

    it('dropOrdered 之后下一次现排，内容不变', 0, (): void => {
      const order = new ChatListOrder(allExist);
      order.apply('main', 1, '100', false);
      order.apply('main', 2, '200', false);
      expect(idsOf(order, 'main')).assertEqual('2,1');
      order.dropOrdered('main');
      expect(idsOf(order, 'main')).assertEqual('2,1');
    });

    it('空 listKey 的更新被忽略', 0, (): void => {
      const order = new ChatListOrder(allExist);
      const change: PositionChange = order.apply('', 1, '100', false);
      expect(change.added).assertFalse();
      expect(order.keys().length).assertEqual(0);
    });
  });
}
