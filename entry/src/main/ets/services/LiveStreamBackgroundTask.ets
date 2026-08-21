import { common, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { avSession } from '@kit.AVSessionKit';
import { KEY_BG_PLAY_LIVE } from '../store/AppSettings';
import { str } from '../util/strings';
import { logE, logI } from '../util/log';

// One live-room page can be active at a time. Serialize changes because
// start/update/stop are asynchronous system calls and a quick mute + back
// gesture must not leave an orphan notification or an incorrect recording
// background mode behind.
class LiveStreamBackgroundTask {
  private context: common.UIAbilityContext | null = null;
  private started: boolean = false;
  private wantsRunning: boolean = false;
  private recording: boolean = false;
  private operation: Promise<void> = Promise.resolve();
  // The live renderer plays a STREAM_USAGE_MOVIE stream. The system mutes and
  // freezes such streams in the background unless the app holds BOTH an
  // audioPlayback continuous task AND an activated AVSession, so the session
  // must live exactly as long as the task.
  private session: avSession.AVSession | null = null;

  start(context: common.UIAbilityContext, recording: boolean): void {
    // 设置里关闭"直播后台播放"时不申请后台任务（切后台由系统正常挂起；
    // 推流/录音场景 recording=true 不受该开关限制）。
    if (!recording && !(AppStorage.get<boolean>(KEY_BG_PLAY_LIVE) ?? true)) {
      logI('[LiveStreamBackgroundTask] bg play disabled by setting, skip');
      return;
    }
    this.context = context;
    this.wantsRunning = true;
    this.recording = recording;
    this.enqueue(async (): Promise<void> => {
      if (!this.wantsRunning || this.context === null) { return; }
      if (this.started) {
        await this.updateModes();
        return;
      }
      const current = this.context;
      const info: wantAgent.WantAgentInfo = {
        wants: [{
          bundleName: current.abilityInfo.bundleName,
          abilityName: current.abilityInfo.name
        }],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 8295,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      const agent = await wantAgent.getWantAgent(info);
      await backgroundTaskManager.startBackgroundRunning(current, this.modes(), agent);
      this.started = true;
      await this.ensureSession(current);
      logI(`[LiveStreamBackgroundTask] started modes=${this.modes().join(',')}`);
      if (!this.wantsRunning) { await this.stopCurrent(); }
    });
  }

  setRecording(recording: boolean): void {
    if (this.recording === recording) { return; }
    this.recording = recording;
    this.enqueue(async (): Promise<void> => {
      if (this.started && this.wantsRunning) { await this.updateModes(); }
    });
  }

  stop(): void {
    this.wantsRunning = false;
    this.enqueue(async (): Promise<void> => this.stopCurrent());
  }

  private modes(): string[] {
    return this.recording ? ['audioPlayback', 'audioRecording'] : ['audioPlayback'];
  }

  private async updateModes(): Promise<void> {
    if (this.context === null) { return; }
    await backgroundTaskManager.updateBackgroundRunning(this.context, this.modes());
    logI(`[LiveStreamBackgroundTask] updated modes=${this.modes().join(',')}`);
  }

  private async stopCurrent(): Promise<void> {
    if (!this.started || this.context === null) { return; }
    await this.destroySession();
    await backgroundTaskManager.stopBackgroundRunning(this.context);
    this.started = false;
    logI('[LiveStreamBackgroundTask] stopped');
  }

  private async ensureSession(context: common.UIAbilityContext): Promise<void> {
    if (this.session !== null) { return; }
    try {
      const session = await avSession.createAVSession(context, 'telegram_live', 'video');
      // Live streams cannot seek or pause; the handlers only exist because the
      // system requires registered commands for a session to count as valid.
      session.on('play', (): void => {});
      session.on('pause', (): void => {});
      session.on('stop', (): void => {});
      await session.setAVMetadata({ assetId: 'telegram_live', title: str('cp_live_now') });
      await session.setAVPlaybackState({
        state: avSession.PlaybackState.PLAYBACK_STATE_PLAY
      });
      await session.activate();
      this.session = session;
      logI('[LiveStreamBackgroundTask] avsession activated');
    } catch (caught) {
      const error = caught as Error;
      logE(`[LiveStreamBackgroundTask] avsession failed: ${error.message}`);
    }
  }

  private async destroySession(): Promise<void> {
    const session = this.session;
    if (session === null) { return; }
    this.session = null;
    try {
      await session.deactivate();
      await session.destroy();
    } catch (caught) {
      const error = caught as Error;
      logE(`[LiveStreamBackgroundTask] avsession destroy failed: ${error.message}`);
    }
  }

  private enqueue(action: () => Promise<void>): void {
    this.operation = this.operation.then(action).catch((error: Error): void => {
      logE(`[LiveStreamBackgroundTask] ${error.message}`);
    });
  }
}

export const liveStreamBackgroundTask: LiveStreamBackgroundTask = new LiveStreamBackgroundTask();
