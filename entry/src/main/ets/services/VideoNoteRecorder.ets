import { camera } from '@kit.CameraKit';
import { display } from '@kit.ArkUI';
import { media } from '@kit.MediaKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { logE } from '../util/log';

const MIC_PERMISSION: Permissions = 'ohos.permission.MICROPHONE';
const CAMERA_PERMISSION: Permissions = 'ohos.permission.CAMERA';

// Telegram 圆形视频消息的官方上限就是 60 秒，超过会被服务端拒绝。
// TEXTURE 类型的 XComponent 拿到的预览画面，相当于已按这个镜头角度补偿过。
const TEXTURE_BASE_ROTATION: number = 90;

export const VIDEO_NOTE_MAX_SECONDS: number = 60;

// 圆形视频只在气泡里显示成一个小圆，采集分辨率越高越浪费流量；官方客户端
// 大致落在 384~640 之间，这里把候选档位限制在同一区间内挑最接近正方形的。
const MIN_SIDE: number = 320;
const MAX_SIDE: number = 720;
const FRAME_RATE: number = 30;
const VIDEO_BITRATE: number = 1200000;
const AUDIO_BITRATE: number = 64000;
const AUDIO_SAMPLE_RATE: number = 48000;

// 打开摄像头失败时区分原因，UI 才能给出对应的中文提示。
export type VideoNoteOpenResult = 'ok' | 'denied' | 'failed';

// 一次圆形视频录制会话：持有摄像头 + AVRecorder，预览与录制共用同一个
// VideoSession（录制的输入面来自 AVRecorder.getInputSurface）。
// 生命周期：open() 起预览 → beginRecord() 起录 → stop()/cancel() 收尾。
// 与 VoiceRecorder 一样，一次录制一个实例，收尾后不再复用。
export class VideoNoteRecorder {
  path: string = '';
  // 圆形视频是正方形，td 的 length 取采集分辨率的边长。
  length: number = 0;

  private recorder: media.AVRecorder | null = null;
  private file: fs.File | null = null;
  private cameraInput: camera.CameraInput | null = null;
  private previewOutput: camera.PreviewOutput | null = null;
  // 设备是否同时具备前后摄像头，决定 UI 上要不要给切换按钮。
  bothCameras: boolean = false;
  // 取景需要补的旋转角度，由 UI 层套在 XComponent 上。
  previewRotationDeg: number = 0;
  private videoOutput: camera.VideoOutput | null = null;
  private session: camera.VideoSession | null = null;
  private startedAtMs: number = 0;
  private recording: boolean = false;
  private released: boolean = false;

  private async requestPermissions(context: common.UIAbilityContext): Promise<boolean> {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const res = await atManager.requestPermissionsFromUser(
        context, [CAMERA_PERMISSION, MIC_PERMISSION]);
      if (res.authResults.length < 2) {
        return false;
      }
      return res.authResults[0] === 0 && res.authResults[1] === 0;
    } catch (e) {
      logE(`VideoNoteRecorder.requestPermissions failed: ${e}`);
      return false;
    }
  }

  // 优先选最接近正方形的档位：圆形视频最终按边长裁成圆，越接近 1:1 裁掉的
  // 画面越少。同样方正时取更小的一档以省流量。
  private static pickVideoProfile(profiles: camera.VideoProfile[]): camera.VideoProfile | null {
    let best: camera.VideoProfile | null = null;
    let bestScore: number = Number.MAX_VALUE;
    let fallback: camera.VideoProfile | null = null;
    let fallbackSide: number = Number.MAX_VALUE;
    for (const profile of profiles) {
      const width: number = profile.size.width;
      const height: number = profile.size.height;
      const side: number = Math.min(width, height);
      if (side <= 0) {
        continue;
      }
      if (side < fallbackSide) {
        fallbackSide = side;
        fallback = profile;
      }
      if (side < MIN_SIDE || side > MAX_SIDE) {
        continue;
      }
      // 长宽比权重远大于边长，保证"方"优先于"小"。
      const aspect: number = Math.max(width, height) / side;
      const score: number = (aspect - 1) * 10000 + side;
      if (score < bestScore) {
        bestScore = score;
        best = profile;
      }
    }
    return best !== null ? best : fallback;
  }

  // 预览与录制必须同长宽比，否则部分机型 commitConfig 直接失败。
  private static pickPreviewProfile(
    profiles: camera.Profile[], video: camera.VideoProfile): camera.Profile | null {
    const target: number = video.size.width / video.size.height;
    let best: camera.Profile | null = null;
    let bestScore: number = Number.MAX_VALUE;
    for (const profile of profiles) {
      const width: number = profile.size.width;
      const height: number = profile.size.height;
      if (width <= 0 || height <= 0) {
        continue;
      }
      const ratioDiff: number = Math.abs(width / height - target);
      const sizeDiff: number = Math.abs(width - video.size.width);
      const score: number = ratioDiff * 100000 + sizeDiff;
      if (score < bestScore) {
        bestScore = score;
        best = profile;
      }
    }
    return best;
  }

  // 前置摄像头是圆形视频的默认取景（自拍），没有前置时退回第一个设备。
  private static pickDevice(devices: camera.CameraDevice[],
    position: camera.CameraPosition): camera.CameraDevice | null {
    if (devices.length === 0) {
      return null;
    }
    for (const device of devices) {
      if (device.cameraPosition === position) {
        return device;
      }
    }
    return devices[0];
  }

  // 设备上是否同时有前后摄像头——只有一个时不该显示切换按钮。
  static hasBothCameras(devices: camera.CameraDevice[]): boolean {
    let front: boolean = false;
    let back: boolean = false;
    for (const device of devices) {
      if (device.cameraPosition === camera.CameraPosition.CAMERA_POSITION_FRONT) { front = true; }
      if (device.cameraPosition === camera.CameraPosition.CAMERA_POSITION_BACK) { back = true; }
    }
    return front && back;
  }

  // 起预览。previewSurfaceId 来自 XComponent；返回 'ok' 才允许后续录制。
  // useFront=true 用前置（自拍，圆形视频的默认），false 用后置。
  async open(context: common.UIAbilityContext, previewSurfaceId: string,
    useFront: boolean = true): Promise<VideoNoteOpenResult> {
    if (previewSurfaceId === '') {
      return 'failed';
    }
    const granted: boolean = await this.requestPermissions(context);
    if (!granted) {
      return 'denied';
    }
    try {
      const manager: camera.CameraManager = camera.getCameraManager(context);
      const devices: camera.CameraDevice[] = manager.getSupportedCameras();
      this.bothCameras = VideoNoteRecorder.hasBothCameras(devices);
      const device: camera.CameraDevice | null = VideoNoteRecorder.pickDevice(devices,
        useFront ? camera.CameraPosition.CAMERA_POSITION_FRONT
          : camera.CameraPosition.CAMERA_POSITION_BACK);
      if (device === null) {
        return 'failed';
      }
      const capability: camera.CameraOutputCapability =
        manager.getSupportedOutputCapability(device, camera.SceneMode.NORMAL_VIDEO);
      const videoProfile: camera.VideoProfile | null =
        VideoNoteRecorder.pickVideoProfile(capability.videoProfiles);
      if (videoProfile === null) {
        return 'failed';
      }
      const previewProfile: camera.Profile | null =
        VideoNoteRecorder.pickPreviewProfile(capability.previewProfiles, videoProfile);
      if (previewProfile === null) {
        return 'failed';
      }
      this.length = Math.min(videoProfile.size.width, videoProfile.size.height);

      const recorderSurfaceId: string = await this.prepareRecorder(context, videoProfile);
      if (recorderSurfaceId === '') {
        return 'failed';
      }

      const input: camera.CameraInput = manager.createCameraInput(device);
      this.cameraInput = input;
      await input.open();
      this.previewOutput = manager.createPreviewOutput(previewProfile, previewSurfaceId);
      const videoOutput: camera.VideoOutput = manager.createVideoOutput(videoProfile, recorderSurfaceId);
      this.videoOutput = videoOutput;

      const session: camera.VideoSession = manager.createSession<camera.VideoSession>(
        camera.SceneMode.NORMAL_VIDEO);
      this.session = session;
      session.beginConfig();
      session.addInput(input);
      session.addOutput(this.previewOutput);
      session.addOutput(videoOutput);
      await session.commitConfig();
      await session.start();
      // 方向必须在会话 start 之后再取。之前放在 createPreviewOutput 紧后面，
      // 那时会话还没 commitConfig，getPreviewRotation 直接抛异常，于是预览
      // 方向从未被设置过（前置取景上下颠倒就是这么来的）。
      this.applyPreviewRotation();
      this.applyRotation(videoOutput);
      return 'ok';
    } catch (e) {
      logE(`VideoNoteRecorder.open failed: ${e}`);
      await this.release();
      return 'failed';
    }
  }

  // display.rotation 是 0/1/2/3 的枚举而不是角度，官方示例里要乘 90 才是
  // 传给相机接口的度数。
  private static displayRotationDegrees(): number {
    try {
      return display.getDefaultDisplaySync().rotation * camera.ImageRotation.ROTATION_90;
    } catch (e) {
      return 0;
    }
  }

  // 预览旋转只能在 UI 层做。
  //
  // 官方公式是「镜头安装角度 + 屏幕旋转角度」，getPreviewRotation 会算好；
  // 但 setPreviewRotation 作用于 surface 的显示变换，只有 SURFACE 类型的
  // XComponent 会遵从。我们用的是 TEXTURE（SURFACE 是独立图层，叠上圆形
  // 裁剪会黑屏），画面走 ArkUI 合成，系统那层旋转对它不生效——实测调用
  // 返回成功、角度也正确，画面却纹丝不动。
  //
  // TEXTURE 呈现的画面相当于已按 90° 镜头补偿过（后置的常见值，所以后置
  // 看着是正的），因此我们只需补上差值。这一点依赖框架行为，换机型若发现
  // 方向不对，先打印这里的 previewRotation 再调整。
  private applyPreviewRotation(): void {
    const previewOutput: camera.PreviewOutput | null = this.previewOutput;
    if (previewOutput === null) {
      return;
    }
    try {
      const target: number =
        previewOutput.getPreviewRotation(VideoNoteRecorder.displayRotationDegrees());
      this.previewRotationDeg = ((target - TEXTURE_BASE_ROTATION) % 360 + 360) % 360;
    } catch (e) {
      logE(`VideoNoteRecorder.getPreviewRotation failed: ${e}`);
      this.previewRotationDeg = 0;
    }
  }

  // 录制方向只有拿到 videoOutput 之后才能问出来，而 prepare() 早于它，
  // 所以先按 0 度 prepare，再用 updateRotation 补正。失败不影响录制本身。
  private applyRotation(videoOutput: camera.VideoOutput): void {
    const recorder: media.AVRecorder | null = this.recorder;
    if (recorder === null) {
      return;
    }
    try {
      // 同样按屏幕旋转角度取，而不是写死 0——竖屏时两者等价，横屏录制时
      // 只有传了真实值才对。
      const rotation: number = videoOutput.getVideoRotation(
        VideoNoteRecorder.displayRotationDegrees());
      recorder.updateRotation(rotation).catch((e: Object): void => {
        logE(`VideoNoteRecorder.updateRotation failed: ${JSON.stringify(e)}`);
      });
    } catch (e) {
      logE(`VideoNoteRecorder.getVideoRotation failed: ${e}`);
    }
  }

  private async prepareRecorder(
    context: common.UIAbilityContext, videoProfile: camera.VideoProfile): Promise<string> {
    this.path = `${context.cacheDir}/videonote_${Date.now()}.mp4`;
    this.file = fs.openSync(this.path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
    const recorder: media.AVRecorder = await media.createAVRecorder();
    this.recorder = recorder;
    const config: media.AVRecorderConfig = {
      audioSourceType: media.AudioSourceType.AUDIO_SOURCE_TYPE_MIC,
      videoSourceType: media.VideoSourceType.VIDEO_SOURCE_TYPE_SURFACE_YUV,
      profile: {
        audioBitrate: AUDIO_BITRATE,
        audioChannels: 1,
        audioCodec: media.CodecMimeType.AUDIO_AAC,
        audioSampleRate: AUDIO_SAMPLE_RATE,
        fileFormat: media.ContainerFormatType.CFT_MPEG_4,
        videoBitrate: VIDEO_BITRATE,
        videoCodec: media.CodecMimeType.VIDEO_AVC,
        videoFrameWidth: videoProfile.size.width,
        videoFrameHeight: videoProfile.size.height,
        videoFrameRate: Math.min(FRAME_RATE, videoProfile.frameRateRange.max)
      },
      url: `fd://${this.file.fd}`,
      rotation: 0
    };
    await recorder.prepare(config);
    return recorder.getInputSurface();
  }

  isRecording(): boolean {
    return this.recording;
  }

  // 预览已经在跑，这里只是把编码器接上。返回 false 表示没能起录。
  async beginRecord(): Promise<boolean> {
    if (this.recording || this.released || this.recorder === null || this.videoOutput === null) {
      return false;
    }
    try {
      await this.videoOutput.start();
      await this.recorder.start();
      this.startedAtMs = Date.now();
      this.recording = true;
      return true;
    } catch (e) {
      logE(`VideoNoteRecorder.beginRecord failed: ${e}`);
      return false;
    }
  }

  // 停止并保留文件，返回实际录制秒数（0 表示没有可用内容）。
  async stop(): Promise<number> {
    if (!this.recording) {
      await this.release();
      return 0;
    }
    const elapsedMs: number = this.startedAtMs > 0 ? Date.now() - this.startedAtMs : 0;
    await this.release();
    // 与语音一致：不足 1 秒的也按 1 秒上报，避免接收端进度条除零。
    return Math.min(Math.max(Math.round(elapsedMs / 1000), 1), VIDEO_NOTE_MAX_SECONDS);
  }

  // 停止并删除文件（用户上滑取消，或权限/初始化失败后的收尾）。
  async cancel(): Promise<void> {
    await this.release();
    if (this.path !== '') {
      try {
        fs.unlinkSync(this.path);
      } catch (e) {
        logE(`VideoNoteRecorder.cancel unlink failed: ${e}`);
      }
      this.path = '';
    }
  }

  // 释放顺序与创建相反：先停编码再拆会话，否则部分机型会卡在 stop()。
  async release(): Promise<void> {
    if (this.released) {
      return;
    }
    this.released = true;
    const recorder: media.AVRecorder | null = this.recorder;
    this.recorder = null;
    if (recorder !== null) {
      if (this.recording) {
        try {
          await recorder.stop();
        } catch (e) {
          logE(`VideoNoteRecorder recorder stop failed: ${e}`);
        }
      }
      try {
        await recorder.release();
      } catch (e) {
        logE(`VideoNoteRecorder recorder release failed: ${e}`);
      }
    }
    this.recording = false;
    this.startedAtMs = 0;

    const videoOutput: camera.VideoOutput | null = this.videoOutput;
    this.videoOutput = null;
    if (videoOutput !== null) {
      try {
        await videoOutput.release();
      } catch (e) {
        logE(`VideoNoteRecorder videoOutput release failed: ${e}`);
      }
    }
    const previewOutput: camera.PreviewOutput | null = this.previewOutput;
    this.previewOutput = null;
    if (previewOutput !== null) {
      try {
        await previewOutput.release();
      } catch (e) {
        logE(`VideoNoteRecorder previewOutput release failed: ${e}`);
      }
    }
    const session: camera.VideoSession | null = this.session;
    this.session = null;
    if (session !== null) {
      try {
        await session.stop();
      } catch (e) {
        logE(`VideoNoteRecorder session stop failed: ${e}`);
      }
      try {
        await session.release();
      } catch (e) {
        logE(`VideoNoteRecorder session release failed: ${e}`);
      }
    }
    const input: camera.CameraInput | null = this.cameraInput;
    this.cameraInput = null;
    if (input !== null) {
      try {
        await input.close();
      } catch (e) {
        logE(`VideoNoteRecorder cameraInput close failed: ${e}`);
      }
    }
    if (this.file !== null) {
      try {
        fs.closeSync(this.file);
      } catch (e) {
        logE(`VideoNoteRecorder file close failed: ${e}`);
      }
      this.file = null;
    }
  }
}
