import { describe, expect, it } from '@ohos/hypium';
import {
  RememberedChatViewport, forgetChatPosition, openAtMessageId, rememberChatPosition,
  rememberedChatPosition, rememberedChatViewport, resetChatPositions, resumeKeyOf
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
}
