import { describe, it, expect } from '@ohos/hypium';
import {
  planPrependSplice, patchIndicesAfterPrepend, planEdgeSplice, planEdgeSpliceRows,
  MAX_SPLICE_INSERT
} from '../main/ets/util/splicePublish';

class Row {
  k: string;
  constructor(k: string) { this.k = k; }
}

export default function splicePublishTest() {
  describe('splicePublish', () => {
    it('纯前插：新序列 = 新行 + 原序列原样', 0, (): void => {
      const plan = planPrependSplice(['a', 'b', 'c'], ['x', 'y', 'a', 'b', 'c']);
      expect(plan !== null).assertTrue();
      expect((plan!).head).assertEqual(2);
    });
    it('不是纯前插的一律 null：追加 / 删除 / 空 / 中间变动 / 跳转落地', 0, (): void => {
      expect(planPrependSplice(['a', 'b'], ['a', 'b', 'c']) === null).assertTrue();   // 追加
      expect(planPrependSplice(['a', 'b', 'c'], ['a', 'c']) === null).assertTrue();   // 删除
      expect(planPrependSplice([], ['a']) === null).assertTrue();                     // 首屏
      expect(planPrependSplice(['a', 'b'], ['x', 'a', 'q']) === null).assertTrue();   // 后缀不一致
      expect(planPrependSplice(['a', 'b'], ['p', 'q', 'r']) === null).assertTrue();   // 整窗换掉
      expect(planPrependSplice(['a'], ['a']) === null).assertTrue();                  // 无变化
    });
    it('补丁只列出前插后对象换了的旧行下标（reuseUnchangedRows 保证未变行同对象）', 0, (): void => {
      const a: Row = new Row('a'); const b: Row = new Row('b');
      const b2: Row = new Row('b'); const x: Row = new Row('x');
      // 前插 1 行；b 内容变了（新对象 b2），a 没变（同对象）
      const patches = patchIndicesAfterPrepend([a, b], [x, a, b2], 1);
      expect(patches.length).assertEqual(1);
      expect(patches[0]).assertEqual(2);
    });

    it('边缘 splice：前插 / 砍头 / 砍尾 三种形状各自识别，其余 null', 0, (): void => {
      const pre = planEdgeSplice(['a', 'b'], ['x', 'a', 'b']);
      expect(pre !== null && pre.kind === 'prepend' && pre.count === 1).assertTrue();
      const dh = planEdgeSplice(['a', 'b', 'c', 'd'], ['c', 'd']);       // 裁剪砍老端
      expect(dh !== null && dh.kind === 'dropHead' && dh.count === 2).assertTrue();
      const dt = planEdgeSplice(['a', 'b', 'c', 'd'], ['a', 'b']);       // 裁剪砍新端
      expect(dt !== null && dt.kind === 'dropTail' && dt.count === 2).assertTrue();
      expect(planEdgeSplice(['a', 'b', 'c'], ['a', 'c']) === null).assertTrue();   // 中间删除：不是边缘
      expect(planEdgeSplice(['a', 'b'], []) === null).assertTrue();               // 清空：整份替换
    });

    // 首屏分帧揭示的真实形状：stageInitialMessageGroups 返回**等长**数组，占位行
    // 与真行的 rowIdentity 逐字节相同。旧代码在这里返回 null → 整份换数组 →
    // ChatPage.build() 每揭示一行重跑一次。
    it('等长同身份 = patch：只换对象不换数组引用', 0, (): void => {
      const p1 = planEdgeSplice(['a', 'b', 'c'], ['a', 'b', 'c']);
      expect(p1 !== null && p1.kind === 'patch' && p1.count === 0).assertTrue();
      // 等长但身份变了（跳转落地换了一整窗）：不是 patch
      expect(planEdgeSplice(['a', 'b'], ['x', 'y']) === null).assertTrue();
      expect(planEdgeSplice(['a', 'b'], ['a', 'x']) === null).assertTrue();
    });

    it('尾部追加 = append：新消息到达不再换数组引用', 0, (): void => {
      const ap = planEdgeSplice(['a', 'b'], ['a', 'b', 'c']);
      expect(ap !== null && ap.kind === 'append' && ap.count === 1).assertTrue();
      const ap2 = planEdgeSplice(['a'], ['a', 'b', 'c']);
      expect(ap2 !== null && ap2.kind === 'append' && ap2.count === 2).assertTrue();
      // 前缀不一致的增长两头都不占：整份替换
      expect(planEdgeSplice(['a', 'b'], ['a', 'x', 'c']) === null).assertTrue();
    });

    it('首屏（prev 为空）仍走整份替换，不当成 append', 0, (): void => {
      expect(planEdgeSplice([], ['a', 'b']) === null).assertTrue();
      expect(planEdgeSplice([], []) === null).assertTrue();
    });

    // 热路径用的是对象优先版：对象相同就不算身份。这条钉住"只对不同对象取身份"
    // 这个前提——未变行必须被判成同一行，且判定结果与身份数组版一致。
    it('对象优先版：相同对象不取身份，不同对象才比身份', 0, (): void => {
      const a: Row = new Row('a'); const b: Row = new Row('b');
      const b2: Row = new Row('b'); const x: Row = new Row('x');
      let asked: number = 0;
      const idOf = (row: Object): string => { asked++; return (row as Row).k; };
      // 等长、只有一行换了对象但身份相同 = patch；只该为那一行取两次身份。
      const p1 = planEdgeSpliceRows([a, b], [a, b2], idOf);
      expect(p1 !== null && p1.kind === 'patch').assertTrue();
      expect(asked).assertEqual(2);
      // 前插
      const p2 = planEdgeSpliceRows([a, b], [x, a, b], idOf);
      expect(p2 !== null && p2.kind === 'prepend' && p2.count === 1).assertTrue();
      // 追加
      const p3 = planEdgeSpliceRows([a, b], [a, b, x], idOf);
      expect(p3 !== null && p3.kind === 'append' && p3.count === 1).assertTrue();
      // 砍头 / 砍尾
      const p4 = planEdgeSpliceRows([a, b, x], [x], idOf);
      expect(p4 !== null && p4.kind === 'dropHead' && p4.count === 2).assertTrue();
      const p5 = planEdgeSpliceRows([a, b, x], [a], idOf);
      expect(p5 !== null && p5.kind === 'dropTail' && p5.count === 2).assertTrue();
      // 等长但身份变了
      expect(planEdgeSpliceRows([a, b], [a, x], idOf) === null).assertTrue();
    });

    it('插入行数超过上限就退回整份替换（splice 展开实参会撑爆调用栈）', 0, (): void => {
      const tail: string[] = [];
      for (let i = 0; i < 3; i++) { tail.push(`t${i}`); }
      const big: string[] = [];
      for (let i = 0; i < MAX_SPLICE_INSERT + 1; i++) { big.push(`n${i}`); }
      expect(planEdgeSplice(tail, big.concat(tail)) === null).assertTrue();   // 前插超限
      expect(planEdgeSplice(tail, tail.concat(big)) === null).assertTrue();   // 追加超限
    });
  });
}
