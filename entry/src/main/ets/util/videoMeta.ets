import { media } from '@kit.MediaKit';
import { fileIo } from '@kit.CoreFileKit';
import { DisplaySize, NO_DISPLAY_SIZE, videoDisplaySize } from './videoDisplaySize';
import { logE, logW } from './log';

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
  let src: fileIo.File | null = null;
  let extractor: media.AVMetadataExtractor | null = null;
  try {
    src = await fileIo.open(videoPath, fileIo.OpenMode.READ_ONLY);
    extractor = await media.createAVMetadataExtractor();
    extractor.fdSrc = { fd: src.fd };
    const meta: media.AVMetadata = await extractor.fetchMetadata();
    // 这三个字段在 AVMetadata 里都是字符串，缺失时是 undefined。
    const w: number = Number(meta.videoWidth ?? '');
    const h: number = Number(meta.videoHeight ?? '');
    const rotation: number = Number(meta.videoOrientation ?? '0');
    const size: DisplaySize =
      videoDisplaySize(w, h, Number.isFinite(rotation) ? rotation : 0);
    logW(`[LivePhoto] video meta ${w}x${h} rot=${rotation}` +
      ` -> display ${size.width}x${size.height}`);
    return size;
  } catch (error) {
    logE(`videoDisplaySizeOf(${videoPath}) failed: ${error}`);
    return NO_DISPLAY_SIZE;
  } finally {
    if (extractor !== null) {
      try {
        await extractor.release();
      } catch (error) {
        logE(`videoDisplaySizeOf release failed: ${error}`);
      }
    }
    if (src !== null) {
      fileIo.closeSync(src);
    }
  }
}
