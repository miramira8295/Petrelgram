import { common, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { avSession } from '@kit.AVSessionKit';
import { str } from '../util/strings';
import { logE, logI } from '../util/log';

// 1对1 通话期间的后台保活：voip 长时任务让通话切后台后进程不被挂起、
// 音频路由不被冻结。串行化模式与 LiveStreamBackgroundTask 相同 ——
// start/stop 是异步系统调用，快速接挂切换不能留下孤儿任务。
class CallKeepAliveTask {
  private context: common.UIAbilityContext | null = null;
  private started: boolean = false;
  private wantsRunning: boolean = false;
  private operation: Promise<void> = Promise.resolve();
  // 系统要求 VoIP 通话持有已激活的 voice_call AVSession，否则切后台后
  // 通话音频会被静音（与直播的 audioPlayback 约束同源）。
  private session: avSession.AVSession | null = null;

  start(context: common.UIAbilityContext): void {
    this.context = context;
    this.wantsRunning = true;
    this.enqueue(async (): Promise<void> => {
      if (!this.wantsRunning || this.started || this.context === null) {
        return;
      }
      const current = this.context;
      const info: wantAgent.WantAgentInfo = {
        wants: [{
          bundleName: current.abilityInfo.bundleName,
          abilityName: current.abilityInfo.name
        }],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 8296,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      const agent = await wantAgent.getWantAgent(info);
      try {
        await backgroundTaskManager.startBackgroundRunning(current, ['voip'], agent);
        logI('[CallKeepAliveTask] started mode=voip');
      } catch (caught) {
        // 部分机型/版本对 voip 类型有额外校验；退化为 audioPlayback，
        // 保证通话音频在后台仍然存活。
        logE(`[CallKeepAliveTask] voip failed: ${(caught as Error).message}`);
        await backgroundTaskManager.startBackgroundRunning(
          current, ['audioPlayback'], agent);
        logI('[CallKeepAliveTask] started mode=audioPlayback (fallback)');
      }
      this.started = true;
      await this.ensureSession(current);
      if (!this.wantsRunning) {
        await this.stopCurrent();
      }
    });
  }

  stop(): void {
    this.wantsRunning = false;
    this.enqueue(async (): Promise<void> => this.stopCurrent());
  }

  private async ensureSession(context: common.UIAbilityContext): Promise<void> {
    if (this.session !== null) {
      return;
    }
    try {
      const session = await avSession.createAVSession(context, 'telegram_call', 'voice_call');
      await session.setAVMetadata({ assetId: 'telegram_call', title: str('svc_in_call') });
      await session.setAVPlaybackState({
        state: avSession.PlaybackState.PLAYBACK_STATE_PLAY
      });
      await session.activate();
      this.session = session;
      logI('[CallKeepAliveTask] avsession activated');
    } catch (caught) {
      logE(`[CallKeepAliveTask] avsession failed: ${(caught as Error).message}`);
    }
  }

  private async destroySession(): Promise<void> {
    const session = this.session;
    if (session === null) {
      return;
    }
    this.session = null;
    try {
      await session.deactivate();
      await session.destroy();
    } catch (caught) {
      logE(`[CallKeepAliveTask] avsession destroy failed: ${(caught as Error).message}`);
    }
  }

  private async stopCurrent(): Promise<void> {
    if (!this.started || this.context === null) {
      return;
    }
    await this.destroySession();
    await backgroundTaskManager.stopBackgroundRunning(this.context);
    this.started = false;
    logI('[CallKeepAliveTask] stopped');
  }

  private enqueue(action: () => Promise<void>): void {
    this.operation = this.operation.then(action).catch((error: Error): void => {
      logE(`[CallKeepAliveTask] ${error.message}`);
    });
  }
}

export const callKeepAliveTask: CallKeepAliveTask = new CallKeepAliveTask();
