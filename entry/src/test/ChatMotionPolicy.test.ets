import { describe, expect, it } from '@ohos/hypium';
import { chatMotionAllowed, chatTimelineSuspended } from '../main/ets/util/chatMotionPolicy';
import { AnimationGate } from '../main/ets/util/animationGate';

export default function chatMotionPolicyTest() {
  describe('chatMotionPolicy', () => {
    it('可见前台聊天允许运行，隐藏或后台均暂停', 0, () => {
      expect(chatMotionAllowed(true, true, false)).assertTrue();
      expect(chatMotionAllowed(false, true, false)).assertFalse();
      expect(chatMotionAllowed(true, false, false)).assertFalse();
    });

    it('覆盖只作用于所属聊天列，分栏中未覆盖区域仍可运行', 0, () => {
      expect(chatMotionAllowed(true, true, true)).assertFalse();
      expect(chatMotionAllowed(true, true, false)).assertTrue();
    });

    it('后台关闭查看器仍暂停，回前台后才恢复', 0, () => {
      expect(chatMotionAllowed(true, false, true)).assertFalse();
      expect(chatMotionAllowed(true, false, false)).assertFalse();
      expect(chatMotionAllowed(true, true, false)).assertTrue();
    });

    it('查看器未关时返回前台或滚动结束不能恢复', 0, () => {
      const allowed: boolean = chatMotionAllowed(true, true, true);
      expect(chatTimelineSuspended(allowed, false, false, false)).assertTrue();
    });

    it('恢复可见后仍保留首屏、滚动和等待稳定三道暂停条件', 0, () => {
      expect(chatTimelineSuspended(true, true, false, false)).assertTrue();
      expect(chatTimelineSuspended(true, false, true, false)).assertTrue();
      expect(chatTimelineSuspended(true, false, false, true)).assertTrue();
      expect(chatTimelineSuspended(true, false, false, false)).assertFalse();
    });

    it('覆盖到恢复的状态实际驱动已挂载与覆盖中新挂载的订阅者', 0, () => {
      const gate: AnimationGate = new AnimationGate(0);
      const first: boolean[] = [];
      const late: boolean[] = [];
      gate.subscribe((paused: boolean): void => { first.push(paused); });
      gate.setSuspended(chatTimelineSuspended(chatMotionAllowed(true, true, true), false, false, false));
      gate.subscribe((paused: boolean): void => { late.push(paused); });
      gate.setSuspended(chatTimelineSuspended(chatMotionAllowed(true, false, false), false, false, false));
      expect(first.join(',')).assertEqual('false,true');
      expect(late.join(',')).assertEqual('true');
      gate.setSuspended(chatTimelineSuspended(chatMotionAllowed(true, true, false), false, false, false));
      expect(first.join(',')).assertEqual('false,true,false');
      expect(late.join(',')).assertEqual('true,false');
    });
  });
  // backdropPhaseClock（背景氛围光斑的相位时钟）随光斑一起在 2026-10-30 删除，
  // 这里原先那三条用例一并去掉。
}
