import { common, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { avSession } from '@kit.AVSessionKit';
import { str } from '../util/strings';
import { logE, logI } from '../util/log';

// 媒体播放期后台保活：正在播（音乐/语音/视频原声）时挂 audioPlayback
// 长时任务 + AVSession，切后台继续播放；全部停止即释放。
// 各播放来源用 kind 引用计数（'music' | 'voice' | 'video'），
// 多路并存时共享一个任务。直播有自己的 LiveStreamBackgroundTask，不走这里。
class MediaPlaybackKeepAlive {
  private context: common.UIAbilityContext | null = null;
  private activeKinds: Set<string> = new Set();
  private started: boolean = false;
  private session: avSession.AVSession | null = null;
  private operation: Promise<void> = Promise.resolve();

  acquire(context: common.UIAbilityContext, kind: string): void {
    this.context = context;
    this.activeKinds.add(kind);
    this.enqueue(async (): Promise<void> => {
      if (this.started || this.activeKinds.size === 0 || this.context === null) {
        return;
      }
      const current = this.context;
      const info: wantAgent.WantAgentInfo = {
        wants: [{
          bundleName: current.abilityInfo.bundleName,
          abilityName: current.abilityInfo.name
        }],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 8299,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      const agent = await wantAgent.getWantAgent(info);
      await backgroundTaskManager.startBackgroundRunning(current, ['audioPlayback'], agent);
      this.started = true;
      await this.ensureSession(current);
      logI(`[MediaPlaybackKeepAlive] started kinds=${Array.from(this.activeKinds).join(',')}`);
      if (this.activeKinds.size === 0) {
        await this.stopCurrent();
      }
    });
  }

  release(kind: string): void {
    this.activeKinds.delete(kind);
    this.enqueue(async (): Promise<void> => {
      if (this.activeKinds.size === 0) {
        await this.stopCurrent();
      }
    });
  }

  private async stopCurrent(): Promise<void> {
    if (!this.started || this.context === null) {
      return;
    }
    await this.destroySession();
    await backgroundTaskManager.stopBackgroundRunning(this.context);
    this.started = false;
    logI('[MediaPlaybackKeepAlive] stopped');
  }

  // 系统要求后台音频播放持有已激活的 AVSession，否则流仍会被静音/冻结
  // （与 LiveStreamBackgroundTask 相同的约束）。
  private async ensureSession(context: common.UIAbilityContext): Promise<void> {
    if (this.session !== null) {
      return;
    }
    try {
      const session = await avSession.createAVSession(context, 'telegram_media', 'audio');
      session.on('play', (): void => {});
      session.on('pause', (): void => {});
      session.on('stop', (): void => {});
      await session.setAVMetadata({ assetId: 'telegram_media', title: str('svc_playing') });
      await session.setAVPlaybackState({
        state: avSession.PlaybackState.PLAYBACK_STATE_PLAY
      });
      await session.activate();
      this.session = session;
    } catch (caught) {
      logE(`[MediaPlaybackKeepAlive] avsession failed: ${(caught as Error).message}`);
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
      logE(`[MediaPlaybackKeepAlive] avsession destroy failed: ${(caught as Error).message}`);
    }
  }

  private enqueue(action: () => Promise<void>): void {
    this.operation = this.operation.then(action).catch((error: Error): void => {
      logE(`[MediaPlaybackKeepAlive] ${error.message}`);
    });
  }
}

export const mediaPlaybackKeepAlive: MediaPlaybackKeepAlive = new MediaPlaybackKeepAlive();
