import { common, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { avSession } from '@kit.AVSessionKit';
import { str } from '../util/strings';
import { logE, logI } from '../util/log';
import { currentNowPlaying, NowPlaying, subscribeNowPlaying } from '../util/nowPlayingChannel';

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
  // 曲目信息的订阅。系统媒体卡片（下拉状态栏那张）原来只拿到通用文案
  // 「正在播放」——setAVMetadata 只在建会话时调过一次，且没有曲名/演唱者/封面。
  // 现在跟着 nowPlayingChannel 走，换歌就刷新。
  private unsubNowPlaying: (() => void) | null = null;

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
      await session.setAVMetadata(this.metadataOf(currentNowPlaying()));
      await session.setAVPlaybackState({
        state: avSession.PlaybackState.PLAYBACK_STATE_PLAY
      });
      await session.activate();
      this.session = session;
      // 换歌时刷新系统媒体卡片。订阅在这里挂、在 destroySession 里退。
      if (this.unsubNowPlaying === null) {
        this.unsubNowPlaying = subscribeNowPlaying((state: NowPlaying | null): void => {
          this.publishMetadata(state);
        });
      }
    } catch (caught) {
      logE(`[MediaPlaybackKeepAlive] avsession failed: ${(caught as Error).message}`);
    }
  }

  // 曲目 → 系统媒体卡片。没有曲目信息时退回原来那句通用文案，不留空白。
  private metadataOf(track: NowPlaying | null): avSession.AVMetadata {
    if (track === null) {
      return { assetId: 'telegram_media', title: str('svc_playing') };
    }
    const meta: avSession.AVMetadata = {
      assetId: `telegram_media_${track.messageId}`,
      title: track.title !== '' ? track.title : str('svc_playing'),
      artist: track.performer,
      duration: track.durationSec > 0 ? track.durationSec * 1000 : undefined
    };
    // 封面用本地文件 URI；没有封面就不给这个字段，系统会用应用图标。
    if (track.coverPath !== '') {
      meta.mediaImage = track.coverPath.startsWith('/')
        ? `file://${track.coverPath}` : track.coverPath;
    }
    return meta;
  }

  private publishMetadata(track: NowPlaying | null): void {
    const session = this.session;
    if (session === null) {
      return;
    }
    session.setAVMetadata(this.metadataOf(track)).catch((caught: Object): void => {
      logE(`[MediaPlaybackKeepAlive] setAVMetadata failed: ${caught}`);
    });
  }

  private async destroySession(): Promise<void> {
    const session = this.session;
    if (session === null) {
      return;
    }
    this.session = null;
    if (this.unsubNowPlaying !== null) {
      this.unsubNowPlaying();
      this.unsubNowPlaying = null;
    }
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
