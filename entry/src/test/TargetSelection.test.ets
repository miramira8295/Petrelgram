import { describe, expect, it } from '@ohos/hypium';
import {
  selectionCount, targetSelected, toggleTarget, trimSelection
} from '../main/ets/util/targetSelection';

// 转发/分享面板里「选了哪几个会话」的集合运算。
//
// 和 util/messageSelection 的区别：那边选中的单位是"行"（一条相册消息整行
// 选中），这边就是单纯的 chatId 集合，不存在半选。但两条不变量一样：
// 不可变（永远返回新数组）、不重复（chatId 不能进两次）。
export default function targetSelectionTest() {
  describe('targetSelection', () => {
    it('空集合里什么都没选中', 0, () => {
      expect(targetSelected([], 5)).assertFalse();
      expect(selectionCount([])).assertEqual(0);
    });

    it('切换：不在就加、在就去', 0, () => {
      const once: number[] = toggleTarget([], 5);
      expect(once.length).assertEqual(1);
      expect(targetSelected(once, 5)).assertTrue();
      const twice: number[] = toggleTarget(once, 5);
      expect(twice.length).assertEqual(0);
      expect(targetSelected(twice, 5)).assertFalse();
    });

    // chat id 只有私聊是正数，群是负数、超级群和频道是 -100… 开头的负数。
    // 用正数做判据会把所有群都排除掉（ForwardSheet.applyChats 踩过这个坑）。
    it('负数 chatId 一样能选', 0, () => {
      const ids: number[] = toggleTarget([], -1002169944671);
      expect(targetSelected(ids, -1002169944671)).assertTrue();
      expect(selectionCount(ids)).assertEqual(1);
    });

    it('不可变：传进去的数组不被改写', 0, () => {
      const original: number[] = [1, 2];
      const next: number[] = toggleTarget(original, 3);
      expect(original.length).assertEqual(2);
      expect(next.length).assertEqual(3);
      const removed: number[] = toggleTarget(original, 1);
      expect(original.length).assertEqual(2);
      expect(removed.length).assertEqual(1);
    });

    it('同一个 id 不会进两次', 0, () => {
      let ids: number[] = toggleTarget([], 7);
      ids = toggleTarget(ids, 8);
      // 已经在里面了，再"加"一次的语义是去掉，不是重复追加。
      ids = toggleTarget(ids, 7);
      expect(selectionCount(ids)).assertEqual(1);
      expect(targetSelected(ids, 8)).assertTrue();
      expect(targetSelected(ids, 7)).assertFalse();
    });

    // 会话列表会翻页/换文件夹页签，选中的会话可能已经不在当前列表里——
    // 但**不能**因此把它从选中集合里剔掉（用户在"全部"里选了，切到某个
    // 文件夹页签就丢选中，是明显的错）。trimSelection 只在会话真的消失
    // （被删除/退群）时用，判据由调用方给。
    it('trimSelection 只去掉调用方点名的那些', 0, () => {
      const ids: number[] = [1, 2, 3];
      expect(trimSelection(ids, [1, 2, 3]).length).assertEqual(3);
      expect(trimSelection(ids, [1, 3]).length).assertEqual(2);
      expect(trimSelection(ids, []).length).assertEqual(0);
      // 不可变
      expect(ids.length).assertEqual(3);
    });
  });
}
