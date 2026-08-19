import { describe, expect, it } from '@ohos/hypium';
import {
  ReturnState, ReturnTarget, RETURN_JUMP, RETURN_LATEST, RETURN_NONE, RETURN_READ,
  advanceRead, emptyReturnState, nextReturnTarget, popJump, pushJump, reachedLatest
} from '../main/ets/util/readingReturn';

// 「↓」的三级优先级：引用返回 > 阅读进度 > 最新消息。
// 用例照着设计里那几个典型场景写，一条不落。
export default function readingReturnTest() {
  describe('readingReturn', () => {
    it('普通上翻：没有跳转也没有阅读进度，回最新', 0, () => {
      const t: ReturnTarget = nextReturnTarget(emptyReturnState(), 50, false);
      expect(t.kind).assertEqual(RETURN_LATEST);
    });

    it('已经在最新：按钮该隐藏', 0, () => {
      const t: ReturnTarget = nextReturnTarget(emptyReturnState(), 100, true);
      expect(t.kind).assertEqual(RETURN_NONE);
    });

    it('未读阅读：翻回更早处时回到阅读进度，而不是底部', 0, () => {
      const s: ReturnState = advanceRead(emptyReturnState(), 20);
      const t: ReturnTarget = nextReturnTarget(s, 5, false);
      expect(t.kind).assertEqual(RETURN_READ);
      expect(t.messageId).assertEqual(20);
    });

    it('阅读进度只前进不后退', 0, () => {
      let s: ReturnState = advanceRead(emptyReturnState(), 20);
      s = advanceRead(s, 5);
      expect(s.readAnchor).assertEqual(20);
      s = advanceRead(s, 23);
      expect(s.readAnchor).assertEqual(23);
    });

    it('站在阅读进度之后：不再提示回进度，退化为回最新', 0, () => {
      const s: ReturnState = advanceRead(emptyReturnState(), 20);
      const t: ReturnTarget = nextReturnTarget(s, 25, false);
      expect(t.kind).assertEqual(RETURN_LATEST);
    });

    it('引用链：后进先出，原路退回', 0, () => {
      let s: ReturnState = pushJump(emptyReturnState(), 100);
      s = pushJump(s, 40);
      let t: ReturnTarget = nextReturnTarget(s, 10, false);
      expect(t.kind).assertEqual(RETURN_JUMP);
      expect(t.messageId).assertEqual(40);
      s = popJump(s);
      t = nextReturnTarget(s, 40, false);
      expect(t.messageId).assertEqual(100);
      s = popJump(s);
      expect(s.jumpStack.length).assertEqual(0);
    });

    it('未读 + 引用：先退完引用链，再回阅读进度', 0, () => {
      let s: ReturnState = advanceRead(emptyReturnState(), 20);
      s = pushJump(s, 20);
      s = pushJump(s, 3);
      expect(nextReturnTarget(s, 1, false).messageId).assertEqual(3);
      s = popJump(s);
      expect(nextReturnTarget(s, 3, false).messageId).assertEqual(20);
      s = popJump(s);
      // 引用链退完，阅读进度还在——此时站在 20 上，已不算偏离。
      expect(nextReturnTarget(s, 20, false).kind).assertEqual(RETURN_LATEST);
    });

    it('在跳转落点附近手动上下翻，不丢返回位置', 0, () => {
      let s: ReturnState = pushJump(emptyReturnState(), 20);
      // 用户在 3 附近翻到 6，栈没被动过。
      const t: ReturnTarget = nextReturnTarget(s, 6, false);
      expect(t.kind).assertEqual(RETURN_JUMP);
      expect(t.messageId).assertEqual(20);
    });

    it('连点同一条引用不重复入栈', 0, () => {
      let s: ReturnState = pushJump(emptyReturnState(), 20);
      s = pushJump(s, 20);
      expect(s.jumpStack.length).assertEqual(1);
    });

    it('自己滚回最新：整套返回关系作废', 0, () => {
      let s: ReturnState = advanceRead(pushJump(emptyReturnState(), 20), 20);
      s = reachedLatest();
      expect(s.jumpStack.length).assertEqual(0);
      expect(s.readAnchor).assertEqual(0);
      expect(nextReturnTarget(s, 100, true).kind).assertEqual(RETURN_NONE);
    });

    it('还不知道看的是哪条时，不冒出指向自己的箭头', 0, () => {
      const s: ReturnState = advanceRead(emptyReturnState(), 20);
      expect(nextReturnTarget(s, 0, true).kind).assertEqual(RETURN_NONE);
    });
  });
}
