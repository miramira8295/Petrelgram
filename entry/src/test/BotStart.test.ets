import { describe, expect, it } from '@ohos/hypium';
import {
  BotStartInput, MEMBERSHIP_BOT_START, composerSlotState, shouldOfferBotStart
} from '../main/ets/util/botStart';

function input(
  isBot: boolean, membershipState: string, loadState: string,
  visibleGroupCount: number, threadRootId: number
): BotStartInput {
  return { isBot, membershipState, loadState, visibleGroupCount, threadRootId };
}

export default function botStartTest() {
  describe('botStart', () => {
    it('空的机器人会话让位给开始按钮', 0, () => {
      expect(shouldOfferBotStart(input(true, 'writable', 'ready', 0, 0))).assertTrue();
    });

    it('不是机器人就不给', 0, () => {
      expect(shouldOfferBotStart(input(false, 'writable', 'ready', 0, 0))).assertFalse();
    });

    it('已经有消息就不给', 0, () => {
      // /start 发出去之后第一条消息落库，按钮就该消失——不需要另一套状态。
      expect(shouldOfferBotStart(input(true, 'writable', 'ready', 1, 0))).assertFalse();
    });

    it('还在加载时不给，避免闪一下', 0, () => {
      expect(shouldOfferBotStart(input(true, 'writable', 'loading', 0, 0))).assertFalse();
      expect(shouldOfferBotStart(input(true, 'writable', 'error', 0, 0))).assertFalse();
    });

    it('话题视图里不给', 0, () => {
      expect(shouldOfferBotStart(input(true, 'writable', 'ready', 0, 42))).assertFalse();
    });

    it('没有发言权时那块位置归成员状态', 0, () => {
      // 这几种下面本来就要显示加入/无法加入/只读，开始按钮不能抢位置。
      const states: string[] = ['joinable', 'blocked', 'readonly', 'checking'];
      for (const st of states) {
        expect(shouldOfferBotStart(input(true, st, 'ready', 0, 0))).assertFalse();
        expect(composerSlotState(input(true, st, 'ready', 0, 0))).assertEqual(st);
      }
    });

    it('composerSlotState 只在该让位时改写', 0, () => {
      expect(composerSlotState(input(true, 'writable', 'ready', 0, 0)))
        .assertEqual(MEMBERSHIP_BOT_START);
      expect(composerSlotState(input(true, 'writable', 'ready', 3, 0)))
        .assertEqual('writable');
      expect(composerSlotState(input(false, 'writable', 'ready', 0, 0)))
        .assertEqual('writable');
    });
  });
}
