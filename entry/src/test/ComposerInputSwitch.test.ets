import { describe, expect, it } from '@ohos/hypium';
import { ComposerInputSwitch, ComposerInputSwitchHost, ComposerSwitchClock } from '../main/ets/pages/chat/ComposerInputSwitch';

class SwitchClock implements ComposerSwitchClock {
  jobs: Array<() => void> = [];
  schedule: (callback: () => void) => number = (callback: () => void): number => {
    this.jobs.push(callback); return this.jobs.length - 1;
  };
  // Deliberately retain canceled tasks to verify the generation guard as well.
  cancel: (id: number) => void = (_id: number): void => {};
  flush(): void { const jobs = this.jobs.slice(); this.jobs = []; for (const job of jobs) { job(); } }
}
class SwitchHost implements ComposerInputSwitchHost {
  allowed: boolean = true;
  chatId: number = 10;
  open: boolean = false;
  mounts: number = 0;
  focuses: number = 0;
  clock: SwitchClock = new SwitchClock();
  control: ComposerInputSwitch = new ComposerInputSwitch(this.clock);
  active: () => boolean = (): boolean => this.allowed;
  contextKey: () => number = (): number => this.chatId;
  emojiOpen: () => boolean = (): boolean => this.open;
  setEmoji: (value: boolean) => void = (value: boolean): void => { this.control.cancel(); this.open = value; };
  prepareEditor: () => void = (): void => { this.mounts++; };
  focusEditor: () => void = (): void => { this.focuses++; };
  constructor() { this.control.bind(this); }
}
export default function composerInputSwitchTest() {
  describe('ComposerInputSwitch', () => {
    it('打开表情不请求键盘焦点', 0, (): void => {
      const h = new SwitchHost(); h.control.toggleEmoji(); h.clock.flush();
      expect(h.open).assertTrue(); expect(h.focuses).assertEqual(0); expect(h.mounts).assertEqual(0);
    });
    it('从表情切回键盘先挂载编辑器再延后聚焦', 0, (): void => {
      const h = new SwitchHost(); h.open = true; h.control.toggleEmoji();
      expect(h.open).assertFalse(); expect(h.mounts).assertEqual(1); expect(h.focuses).assertEqual(0);
      h.clock.flush(); expect(h.focuses).assertEqual(1);
    });
    it('快速再次点击取消键盘请求并重开表情', 0, (): void => {
      const h = new SwitchHost(); h.open = true; h.control.toggleEmoji(); h.control.toggleEmoji(); h.clock.flush();
      expect(h.open).assertTrue(); expect(h.focuses).assertEqual(0);
    });
    it('表情壳延迟收起时第二次点击仍按用户意图重开', 0, (): void => {
      const h = new SwitchHost(); h.open = true; h.control.toggleEmoji(); h.open = true;
      h.control.toggleEmoji(); h.clock.flush(); expect(h.open).assertTrue(); expect(h.focuses).assertEqual(0);
    });
    it('关闭尚未完成时不强行聚焦抢占面板', 0, (): void => {
      const h = new SwitchHost(); h.open = true; h.control.toggleEmoji(); h.open = true; h.clock.flush();
      expect(h.focuses).assertEqual(0);
    });
    it('普通关闭面板不主动弹出键盘', 0, (): void => {
      const h = new SwitchHost(); h.open = true; h.setEmoji(false); h.clock.flush(); expect(h.focuses).assertEqual(0);
    });
    it('切后台或失去发言权限后不申请焦点', 0, (): void => {
      const h = new SwitchHost(); h.control.showKeyboard(); h.allowed = false; h.clock.flush(); expect(h.focuses).assertEqual(0);
    });
    it('隐藏时取消后即使重新显示也不执行旧焦点请求', 0, (): void => {
      const h = new SwitchHost(); h.control.showKeyboard(); h.control.cancel(); h.clock.flush(); expect(h.focuses).assertEqual(0);
    });
    it('切聊天后旧焦点请求失效', 0, (): void => {
      const h = new SwitchHost(); h.control.showKeyboard(); h.chatId = 20; h.clock.flush(); expect(h.focuses).assertEqual(0);
    });
    it('销毁后定时回调不能重新打开输入', 0, (): void => {
      const h = new SwitchHost(); h.control.showKeyboard(); h.control.dispose(); h.clock.flush();
      h.control.toggleEmoji(); expect(h.focuses).assertEqual(0); expect(h.open).assertFalse();
    });
    it('连点输入框只保留最后一个焦点请求', 0, (): void => {
      const h = new SwitchHost(); h.control.showKeyboard(); h.control.showKeyboard(); h.clock.flush(); expect(h.focuses).assertEqual(1);
    });
    it('不可交互页面不改变表情状态也不挂载输入框', 0, (): void => {
      const h = new SwitchHost(); h.allowed = false; h.control.toggleEmoji(); h.control.showKeyboard();
      expect(h.open).assertFalse(); expect(h.mounts).assertEqual(0); expect(h.clock.jobs.length).assertEqual(0);
    });
  });
}
