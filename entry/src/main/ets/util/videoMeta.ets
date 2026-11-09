import { media } from '@kit.MediaKit';
import { fileIo } from '@kit.CoreFileKit';
import { DisplaySize, NO_DISPLAY_SIZE, videoDisplaySize } from './videoDisplaySize';
import { extractFirstFrame } from './livePhotoSave';
import { ImageSize, imageSizeOf } from './imageSize';
import { NO_SEND_THUMB, SendThumb, makeSendThumb } from './sendThumb';
import { seedVideoPoster } from './videoPosterStore';
import { logE, logW } from './log';

export interface LocalVideoMeta {
  width: number;
  height: number;
  durationSec: number;
}

export const NO_LOCAL_VIDEO_META: LocalVideoMeta = {
  width: 0,
  height: 0,
  durationSec: 0
};

export interface PreparedLocalVideo {
  displayWidth: number;
  displayHeight: number;
  durationSec: number;
  posterPath: string;
  thumbPath: string;
  thumbWidth: number;
  thumbHeight: number;
}

export const NO_PREPARED_LOCAL_VIDEO: PreparedLocalVideo = {
  displayWidth: 0,
  displayHeight: 0,
  durationSec: 0,
  posterPath: '',
  thumbPath: '',
  thumbWidth: 0,
  thumbHeight: 0
};

// 读本地视频的显示分辨率（含旋转校正）与时长（秒）。
export async function localVideoMetaOf(videoPath: string): Promise<LocalVideoMeta> {
  let src: fileIo.File | null = null;
  let extractor: media.AVMetadataExtractor | null = null;
  try {
    src = await fileIo.open(videoPath, fileIo.OpenMode.READ_ONLY);
    extractor = await media.createAVMetadataExtractor();
    extractor.fdSrc = { fd: src.fd };
    const meta: media.AVMetadata = await extractor.fetchMetadata();
    const w: number = Number(meta.videoWidth ?? '');
    const h: number = Number(meta.videoHeight ?? '');
    const rotation: number = Number(meta.videoOrientation ?? '0');
    const durationMs: number = Number(meta.duration ?? '0');
    const size: DisplaySize =
      videoDisplaySize(w, h, Number.isFinite(rotation) ? rotation : 0);
    const durationSec: number = Number.isFinite(durationMs) && durationMs > 0
      ? Math.max(1, Math.round(durationMs / 1000)) : 0;
    logW(`[VideoMeta] ${w}x${h} rot=${rotation} durMs=${durationMs}` +
      ` -> display ${size.width}x${size.height} dur=${durationSec}s`);
    return { width: size.width, height: size.height, durationSec };
  } catch (error) {
    logE(`localVideoMetaOf(${videoPath}) failed: ${error}`);
    return NO_LOCAL_VIDEO_META;
  } finally {
    if (extractor !== null) {
      try {
        await extractor.release();
      } catch (error) {
        logE(`localVideoMetaOf release failed: ${error}`);
      }
    }
    if (src !== null) {
      fileIo.closeSync(src);
    }
  }
}

// 读一个本地视频文件真正的**显示**分辨率。
//
// 【为什么需要】TDLib 的 inputMessageVideo.width/height 说的是显示尺寸，而
// 我们此前在实况照片那条路上拿**静图**的宽高去顶它（见 util/movingPhotoPick）。
// 静图是全传感器分辨率、动态部分只有 1080p 级别，两者差一个数量级——接收端和
// 我们自己的存图库都会按那个夸大的值去放大，就是 issue #193 的「特模糊」。
//
// 【为什么不能直接用容器里的宽高】容器存的是**旋转前**的值，竖拍视频在里面是
// 1920×1080 + rotation=90。直接填会让接收端把视频横过来排版（这正是当初改用
// 静图尺寸想解决的问题）。所以宽高和旋转角都要读，再由 videoDisplaySize 合成
// ——那一步是纯函数，有单测。
//
// 读不到就返回 NO_DISPLAY_SIZE，调用方退回原来的行为，不要把 0 填进协议字段。
export async function videoDisplaySizeOf(videoPath: string): Promise<DisplaySize> {
  const meta: LocalVideoMeta = await localVideoMetaOf(videoPath);
  return { width: meta.width, height: meta.height };
}

// 普通本地视频发送前的准备工作：
// 1. 读取旋转校正后的显示宽高与秒级时长，保证发送中与发送完成后的气泡宽高比、
//    时长药丸完全一致（不再先画 16:9 灰框、发完再突变成 9:16 竖屏）。
// 2. 抽取首帧全分辨率 JPEG 作为本端高清海报（posterPath），并缩出一张 <=320px
//    的缩略图（thumbPath）供 TDLib inputThumbnail 上传给接收端。
export async function prepareLocalVideoForSend(
  videoPath: string, filesDir: string, unique: string
): Promise<PreparedLocalVideo> {
  if (videoPath === '') {
    return NO_PREPARED_LOCAL_VIDEO;
  }
  const meta: LocalVideoMeta = await localVideoMetaOf(videoPath);
  let displayW: number = meta.width;
  let displayH: number = meta.height;
  let posterPath: string = '';
  let thumb: SendThumb = NO_SEND_THUMB;
  if (filesDir !== '') {
    const posterCand: string = `${filesDir}/video_poster_${unique}.jpg`;
    const extracted: boolean = await extractFirstFrame(videoPath, posterCand);
    if (extracted) {
      posterPath = posterCand;
      seedVideoPoster(videoPath, posterPath);
      if (displayW <= 0 || displayH <= 0) {
        const frameSize: ImageSize = await imageSizeOf(posterPath);
        displayW = frameSize.width;
        displayH = frameSize.height;
      }
      thumb = await makeSendThumb(posterPath, `${filesDir}/video_thumb_${unique}.jpg`);
    }
  }
  return {
    displayWidth: displayW,
    displayHeight: displayH,
    durationSec: meta.durationSec,
    posterPath,
    thumbPath: thumb.path,
    thumbWidth: thumb.width,
    thumbHeight: thumb.height
  };
}
