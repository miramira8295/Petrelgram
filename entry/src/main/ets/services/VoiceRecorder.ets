import { media } from '@kit.MediaKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { logE } from '../util/log';

const MIC_PERMISSION: Permissions = 'ohos.permission.MICROPHONE';

// Records a voice message (AAC in m4a) into the app cache via AVRecorder.
// One instance per recording session.
export class VoiceRecorder {
  path: string = '';
  private recorder: media.AVRecorder | null = null;
  private file: fs.File | null = null;
  private startedAtMs: number = 0;

  private async requestPermission(context: common.UIAbilityContext): Promise<boolean> {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const res = await atManager.requestPermissionsFromUser(context, [MIC_PERMISSION]);
      return res.authResults.length > 0 && res.authResults[0] === 0;
    } catch (e) {
      logE(`VoiceRecorder.requestPermission failed: ${e}`);
      return false;
    }
  }

  // Returns false when permission is denied or the recorder fails to start.
  async start(context: common.UIAbilityContext): Promise<boolean> {
    const granted = await this.requestPermission(context);
    if (!granted) {
      return false;
    }
    try {
      this.path = `${context.cacheDir}/voice_${Date.now()}.m4a`;
      this.file = fs.openSync(this.path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
      const recorder = await media.createAVRecorder();
      this.recorder = recorder;
      const config: media.AVRecorderConfig = {
        audioSourceType: media.AudioSourceType.AUDIO_SOURCE_TYPE_MIC,
        profile: {
          audioBitrate: 64000,
          audioChannels: 1,
          audioCodec: media.CodecMimeType.AUDIO_AAC,
          audioSampleRate: 48000,
          fileFormat: media.ContainerFormatType.CFT_MPEG_4A
        },
        url: `fd://${this.file.fd}`
      };
      await recorder.prepare(config);
      await recorder.start();
      this.startedAtMs = Date.now();
      return true;
    } catch (e) {
      logE(`VoiceRecorder.start failed: ${e}`);
      await this.cleanup();
      return false;
    }
  }

  // Stop and keep the file. Returns duration in seconds (0 = nothing usable).
  async stop(): Promise<number> {
    const duration = this.startedAtMs > 0 ? Math.round((Date.now() - this.startedAtMs) / 1000) : 0;
    await this.cleanup();
    return Math.max(duration, 1);
  }

  // Stop and delete the file (user cancelled).
  async cancel(): Promise<void> {
    await this.cleanup();
    if (this.path !== '') {
      try {
        fs.unlinkSync(this.path);
      } catch (e) {
        logE(`VoiceRecorder.cancel unlink failed: ${e}`);
      }
      this.path = '';
    }
  }

  private async cleanup(): Promise<void> {
    if (this.recorder !== null) {
      const r = this.recorder;
      this.recorder = null;
      try {
        await r.stop();
      } catch (e) {
        logE(`VoiceRecorder stop failed: ${e}`);
      }
      try {
        await r.release();
      } catch (e) {
        logE(`VoiceRecorder release failed: ${e}`);
      }
    }
    if (this.file !== null) {
      try {
        fs.closeSync(this.file);
      } catch (e) {
        logE(`VoiceRecorder close failed: ${e}`);
      }
      this.file = null;
    }
    this.startedAtMs = 0;
  }
}
