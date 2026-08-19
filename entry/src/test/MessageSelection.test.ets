import { describe, expect, it } from '@ohos/hypium';
import {
  forwardableIds, pruneSelection, rowSelectable, rowSelected, toggleRow
} from '../main/ets/util/messageSelection';

// 选中的单位是"行"不是消息：相册行整体选中或整体不选。
export default function messageSelectionTest() {
  describe('messageSelection', () => {
    it('系统消息和隐藏消息不能选', 0, () => {
      expect(rowSelectable('text')).assertTrue();
      expect(rowSelectable('photo')).assertTrue();
      expect(rowSelectable('system')).assertFalse();
      expect(rowSelectable('hidden')).assertFalse();
    });

    it('沾上一个 member 就算整行选中', 0, () => {
      expect(rowSelected([5], [4, 5, 6])).assertTrue();
      expect(rowSelected([9], [4, 5, 6])).assertFalse();
      expect(rowSelected([], [4, 5, 6])).assertFalse();
      // 空行（理论上不该出现）不该被判成选中。
      expect(rowSelected([5], [])).assertFalse();
    });

    it('点未选中的行：整行加入', 0, () => {
      expect(toggleRow([], [4, 5, 6])).assertDeepEquals([4, 5, 6]);
      expect(toggleRow([1], [4, 5])).assertDeepEquals([1, 4, 5]);
    });

    it('点已选中的行：整行移除，其它行不受影响', 0, () => {
      expect(toggleRow([1, 4, 5, 6, 9], [4, 5, 6])).assertDeepEquals([1, 9]);
    });

    it('半选的行再点一次是整行清空，不是补齐', 0, () => {
      // 相册在选中之后又收到一个新 member：集合里只有 4、5，行是 4、5、6。
      expect(toggleRow([4, 5], [4, 5, 6])).assertDeepEquals([]);
    });

    it('memberIds 自己重复时只加一次', 0, () => {
      // 相册的 member 列表由多次更新拼出来，出现过同一个 id 进来两次。
      // 直接展开会让计数虚高、转发带重复。
      expect(toggleRow([], [7, 7, 8])).assertDeepEquals([7, 8]);
      expect(toggleRow([1], [7, 8, 7])).assertDeepEquals([1, 7, 8]);
    });

    it('沾上任意一个 member 就走移除支，不会补齐', 0, () => {
      // 这一条钉住"半选不存在"：集合里只有 7，行是 7、8 —— 结果是整行清空。
      expect(toggleRow([7], [7, 8])).assertDeepEquals([]);
    });

    it('切换是可逆的：连点两次回到原样', 0, () => {
      const start: number[] = [1, 2];
      const once: number[] = toggleRow(start, [7, 8]);
      const twice: number[] = toggleRow(once, [7, 8]);
      expect(twice).assertDeepEquals(start);
    });

    it('消息被撤回后，选中集合里的幽灵 id 被摘掉', 0, () => {
      expect(pruneSelection([1, 2, 3], [1, 3])).assertDeepEquals([1, 3]);
      // 全部消失时返回空集，调用方据此退出多选。
      expect(pruneSelection([1, 2], [9]).length).assertEqual(0);
      expect(pruneSelection([], [1, 2]).length).assertEqual(0);
    });

    it('转发过滤：去掉不可转发的类型并去重，顺序不变', 0, () => {
      const types: Map<number, string> = new Map<number, string>();
      types.set(1, 'text');
      types.set(2, 'system');
      types.set(3, 'photo');
      types.set(4, 'hidden');
      const typeOf = (id: number): string => types.get(id) ?? 'text';
      expect(forwardableIds([3, 2, 1, 4], typeOf)).assertDeepEquals([3, 1]);
      // 重复 id 只留第一次。
      expect(forwardableIds([1, 1, 3], typeOf)).assertDeepEquals([1, 3]);
      // 全都不可转发时返回空集，调用方据此提示而不是发一个空请求。
      expect(forwardableIds([2, 4], typeOf).length).assertEqual(0);
    });

    it('未知 id 当作可转发，由上层去查真伪', 0, () => {
      expect(forwardableIds([42], (_id: number): string => 'text')).assertDeepEquals([42]);
    });
  });
}
