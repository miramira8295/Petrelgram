import { describe, expect, it } from '@ohos/hypium';
import {
  RememberedChatViewport, forgetChatPosition, isResumeFragment, openAtMessageId,
  rememberChatPosition, rememberedChatPosition, rememberedChatViewport,
  resetChatPositions, resumeKeyOf
} from '../main/ets/util/chatResume';

export default function chatResumeTest() {
  describe('chatResume', () => {
    it('记住与取回，按会话和话题分开', 0, (): void => {
      resetChatPositions();
      rememberChatPosition(-100, 0, 555, false);
      rememberChatPosition(-100, 7, 777, false);
      expect(rememberedChatPosition(-100, 0)).assertEqual(555);
      expect(rememberedChatPosition(-100, 7)).assertEqual(777);
      expect(rememberedChatPosition(-200, 0)).assertEqual(0);
      expect(resumeKeyOf(-100, 7)).assertEqual('-100_7');
    });
    it('在底部或无效 id 就不记，并清掉旧的', 0, (): void => {
      resetChatPositions();
      rememberChatPosition(1, 0, 42, false);
      rememberChatPosition(1, 0, 99, true);
      expect(rememberedChatPosition(1, 0)).assertEqual(0);
      rememberChatPosition(1, 0, 0, false);
      expect(rememberedChatPosition(1, 0)).assertEqual(0);
    });
    it('同时保留首行在视口内的精确偏移', 0, (): void => {
      resetChatPositions();
      rememberChatPosition(8, 3, 120, false, -27.5);
      const viewport: RememberedChatViewport = rememberedChatViewport(8, 3);
      expect(viewport.messageId).assertEqual(120);
      expect(viewport.itemY).assertEqual(-27.5);
      // 取回的是副本，调用方不能改坏模块级缓存。
      viewport.itemY = 99;
      expect(rememberedChatViewport(8, 3).itemY).assertEqual(-27.5);
    });
    it('忘记单条与整表清空', 0, (): void => {
      resetChatPositions();
      rememberChatPosition(2, 0, 10, false);
      forgetChatPosition(2, 0);
      expect(rememberedChatPosition(2, 0)).assertEqual(0);
      rememberChatPosition(3, 0, 11, false);
      resetChatPositions();
      expect(rememberedChatPosition(3, 0)).assertEqual(0);
    });
    it('落点优先级：跳转 > 未读 > 记住的位置', 0, (): void => {
      expect(openAtMessageId(900, true, 500)).assertEqual(900);
      expect(openAtMessageId(0, true, 500)).assertEqual(0);
      expect(openAtMessageId(0, false, 500)).assertEqual(500);
      expect(openAtMessageId(0, false, 0)).assertEqual(0);
    });
    it('超过上限淘汰最旧的', 0, (): void => {
      resetChatPositions();
      for (let i = 1; i <= 70; i++) {
        rememberChatPosition(i, 0, i * 10, false);
      }
      expect(rememberedChatPosition(1, 0)).assertEqual(0);
      expect(rememberedChatPosition(70, 0)).assertEqual(700);
    });
  });

  // ── 缓存页 resume 时那一份快照是不是碎片（原 applyRouteParams 里的
  //    `list.length * 2 < this.groups.length`）───────────────────────────
  describe('isResumeFragment', () => {
    it('2:1 是分界线：判的是数量级坍缩', 0, (): void => {
      // 屏上 100 行、新快照 49 条 → 是碎片，扣住旧视口先不发布。
      expect(isResumeFragment(100, 49)).assertTrue();
      // 50 条就不是了。这个比例是业务 hack，不是可调参数：挪动它就等于挪动
      // "后台删了几行"与"首个 getChatHistory 只回了一小段"的分界线。
      expect(isResumeFragment(100, 50)).assertFalse();
      expect(isResumeFragment(100, 51)).assertFalse();
    });

    it('判的不是非空：一条压掉 34 行的真机案例必须命中', 0, (): void => {
      // openChat 会让 TDLib 立刻推最新一条，而首个 getChatHistory 回包可以
      // 合法地少于请求条数，onHistory 一落地就把 store 标成 ready。退化成
      // `nextRows === 0` 会把这个案例重新放进来——就是"从后台切回来消息乱了"。
      expect(isResumeFragment(34, 1)).assertTrue();
      expect(isResumeFragment(30, 0)).assertTrue();
    });

    it('屏上没东西时永远不是碎片：没什么可保的', 0, (): void => {
      expect(isResumeFragment(0, 0)).assertFalse();
      expect(isResumeFragment(0, 5)).assertFalse();
    });

    it('后台删掉几行不算碎片', 0, (): void => {
      // 只有被删掉一半以上才会误判，而下一次快照就会解除。
      expect(isResumeFragment(40, 37)).assertFalse();
      expect(isResumeFragment(40, 20)).assertFalse();
      expect(isResumeFragment(40, 19)).assertTrue();
    });
  });
}
