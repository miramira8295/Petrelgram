import { TdError } from '../tdkit/TdTypes';

// 一次用户发送任务内按步骤记账。超时不能证明未发送，禁止原样盲重试。
export class SendProgress {
  private completed: Set<number> = new Set<number>();
  private uncertain: Set<number> = new Set<number>();

  async run(index: number, send: () => Promise<void>): Promise<void> {
    if (this.completed.has(index)) { return; }
    if (this.uncertain.has(index)) { throw new TdError(-1, 'send result unknown'); }
    try {
      await send();
      this.completed.add(index);
    } catch (error) {
      const e = error as TdError;
      if (e.code === -1) { this.uncertain.add(index); }
      throw error as Error;
    }
  }

  completedStep(index: number): boolean { return this.completed.has(index); }

  hasUncertain(): boolean { return this.uncertain.size > 0; }
}
