import { describe, expect, it } from '@ohos/hypium';
import { ArchiveRevealGesture, archiveLogicalIndex } from '../main/ets/util/archiveReveal';

export default function archiveRevealTest() {
  describe('archiveReveal', () => {
    it('惯性与程序滚动停在首条会话，不露出归档', 0, () => {
      const g = new ArchiveRevealGesture();
      expect(g.filter(-100, 90, 72, false, true)).assertEqual(-18);
      expect(g.filter(-10, 72, 72, false, true)).assertEqual(0);
    });
    it('只有实际触摸拖动才能进入隐藏行', 0, () => {
      const g = new ArchiveRevealGesture();
      expect(g.filter(-20, 72, 72, true, true)).assertEqual(0);
      g.begin();
      expect(g.filter(-20, 72, 72, true, true)).assertEqual(-9);
      expect(g.filter(-20, 72, 72, true, false)).assertEqual(0);
    });
    it('长列表普通区域不增加阻尼', 0, () => {
      const g = new ArchiveRevealGesture(); g.begin();
      expect(g.filter(-20, 100, 72, true, true)).assertEqual(-20);
      expect(g.filter(40, 30, 72, true, true)).assertEqual(40);
    });
    it('进入归档才分段阻尼并限制过拉', 0, () => {
      const g = new ArchiveRevealGesture(); g.begin();
      expect(g.filter(-40, 90, 72, true, true)).assertEqual(-27.9);
      expect(g.filter(-1000, 10, 72, true, true)).assertEqual(-10);
    });
    it('深度足够但手势不足200ms仍收回', 0, () => {
      const g = new ArchiveRevealGesture(); g.begin(); g.observe(60, 72, 1000);
      expect(g.release(0, 72, 1199, true, false)).assertEqual(72);
      expect(g.revealed).assertFalse();
    });
    it('停留足够但没有露出85%仍收回', 0, () => {
      const g = new ArchiveRevealGesture(); g.begin(); g.observe(60, 72, 1000);
      expect(g.release(20, 72, 1500, true, false)).assertEqual(72);
    });
    it('达标松手吸附归档而不是进入归档页面', 0, () => {
      const g = new ArchiveRevealGesture(); g.begin(); g.observe(60, 72, 1000);
      expect(g.release(10, 72, 1200, true, false)).assertEqual(0);
      expect(g.revealed).assertTrue();
      expect(g.settling).assertTrue();
    });
    it('准备提示220ms出现，反向拖动立即撤销', 0, () => {
      const g = new ArchiveRevealGesture(); g.begin(); g.observe(60, 72, 1000);
      expect(g.ready(10, 72, 1219)).assertFalse();
      expect(g.ready(10, 72, 1220)).assertTrue();
      expect(g.ready(20, 72, 1300)).assertFalse();
    });
    it('整行滚出才隐藏，不再滚8vp就收回', 0, () => {
      const g = new ArchiveRevealGesture(); g.revealed = true;
      g.observe(10, 72, 1000); expect(g.revealed).assertTrue();
      g.observe(60, 72, 1100); expect(g.revealed).assertTrue();
      g.observe(70, 72, 1200); expect(g.revealed).assertFalse();
    });
    it('手势取消和归档消失均不能提交展开', 0, () => {
      const g = new ArchiveRevealGesture(); g.begin(); g.observe(60, 72, 1000);
      expect(g.release(0, 72, 1500, true, true)).assertEqual(72);
      g.begin(); g.observe(60, 72, 2000);
      expect(g.release(0, 72, 2500, false, false)).assertEqual(72);
    });
    it('普通滚动抬手不吸附，重新触摸中止旧吸附', 0, () => {
      const g = new ArchiveRevealGesture(); g.begin();
      expect(g.release(100, 72, 1500, true, false)).assertNull();
      g.settling = true; g.begin(); expect(g.settling).assertFalse();
      g.revealed = true;
      expect(g.release(20, 72, 2000, true, false)).assertNull();
    });
    it('会话记忆索引不包含归档，紧凑行也遵循比例阈值', 0, () => {
      expect(archiveLogicalIndex(0)).assertEqual(0);
      expect(archiveLogicalIndex(1)).assertEqual(0);
      expect(archiveLogicalIndex(7)).assertEqual(6);
      const g = new ArchiveRevealGesture(); g.begin(); g.observe(50, 60, 1000);
      expect(g.release(8, 60, 1250, true, false)).assertEqual(0);
    });
  });
}
