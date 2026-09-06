import { describe, expect, it } from '@ohos/hypium';
import {
  INITIAL_AROUND_LIMIT, INITIAL_AROUND_OFFSET, INITIAL_LATEST_LIMIT,
  InitialPageRoute, ROUTE_AROUND, ROUTE_LATEST,
  canPrefetchChat, initialPageRoute, sameRoute
} from '../main/ets/util/chatPrefetch';

export default function chatPrefetchTest() {
  describe('chatPrefetch', () => {
    // 这三条钉住"预取和 MessageStore 必须发同一发"。判据一旦漂，开出来的窗口
    // 和 store 以为的不是同一页，未读分界线就会落错位置。
    it('有未读且已读水位有效 → 以水位为锚居中开窗', 0, () => {
      const r: InitialPageRoute = initialPageRoute(3, 12269387776);
      expect(r.kind).assertEqual(ROUTE_AROUND);
      expect(r.fromMessageId).assertEqual(12269387776);
      expect(r.offset).assertEqual(INITIAL_AROUND_OFFSET);
      expect(r.limit).assertEqual(INITIAL_AROUND_LIMIT);
    });

    // 【issue #101 的另一半】cb0c5b8 让 getFirstUnreadId() 跳过自己发的消息，
    // 但它扫的是**已加载窗口**，而窗口在水位之上留几个位置由这个 offset 决定。
    // 原值 -7 意味着自己连发 ≥7 条之后收到的新消息落在窗口外，判定拿不到它，
    // 首屏退成"贴底"——贴的还是自己发的那条，分界线也不画。
    //
    // 这条钉的是**语义而不是数值**：水位之上要留够位置，覆盖一次连发。
    // 谁要把它调小，先回答"连发这么多条时分界线还找得到吗"。
    it('未读锚点在水位之上留够余量，覆盖一次连发（issue #101）', 0, () => {
      const r: InitialPageRoute = initialPageRoute(3, 12269387776);
      const headroom: number = -r.offset;
      // 至少要能容下一次十来条的连发，再加上那条真正的未读。
      expect(headroom >= 15).assertTrue();
      // 但不能吃掉整页——水位之下还得留下上下文，否则分界线上方是空的。
      expect(headroom <= r.limit / 2).assertTrue();
    });

    it('没有未读 → 取最新一页', 0, () => {
      const r: InitialPageRoute = initialPageRoute(0, 12269387776);
      expect(r.kind).assertEqual(ROUTE_LATEST);
      expect(r.fromMessageId).assertEqual(0);
      expect(r.offset).assertEqual(0);
      expect(r.limit).assertEqual(INITIAL_LATEST_LIMIT);
    });

    // 全已读、最新几条是自己发的会话，lastReadInboxId 会停在真实尾部之后
    // 很远；水位为 0 时同理无锚可用。两种都必须落到 latest。
    it('已读水位为 0 时即使有未读也走 latest', 0, () => {
      expect(initialPageRoute(5, 0).kind).assertEqual(ROUTE_LATEST);
    });

    it('路由比较是逐字段的', 0, () => {
      const a: InitialPageRoute = initialPageRoute(3, 100);
      expect(sameRoute(a, initialPageRoute(3, 100))).assertTrue();
      // 期间来了新消息 → 水位变了 → 不是同一发，必须重发。
      expect(sameRoute(a, initialPageRoute(3, 200))).assertFalse();
      expect(sameRoute(a, initialPageRoute(0, 100))).assertFalse();
    });

    // 话题/评论区/私聊话题的请求形状不同（getForumTopicHistory 等），
    // 猜错了比不预取更糟；带跳转锚点的进入由 loadAround 自己定位。
    it('只有最普通那一种才预取', 0, () => {
      expect(canPrefetchChat(-100, 0, 0, 0, false)).assertTrue();
      expect(canPrefetchChat(-100, 5, 0, 0, false)).assertFalse();
      expect(canPrefetchChat(-100, 0, 7, 0, false)).assertFalse();
      expect(canPrefetchChat(-100, 0, 0, 9, false)).assertFalse();
      expect(canPrefetchChat(-100, 0, 0, 0, true)).assertFalse();
      expect(canPrefetchChat(0, 0, 0, 0, false)).assertFalse();
    });
  });
}
