// 发送视频时随消息一起上传的**小封面**。
//
// 【为什么不能直接把静图当封面发】TDLib 的 inputMessageVideo.thumbnail 走的是
// 内联缩略图那条路：它要求 JPEG、长边约 320、体积很小（Telegram 侧的约定是
// 200KB 以内）。实况导出的静图是 1440x1920 / 340KB 的整张原图，尺寸和体积都
// 越界——发出去接收端拿不到预览图，我们自己这端 TDLib 回来的 message 里
// video.thumbnail 也是空的（于是 photoFileId=0，气泡落到灰底那一支）。
//
// 静图本身仍然有用：它是**旋转之后**的真实显示尺寸来源，也是"存回图库"要写的
// 那一半。所以两者分开——静图留全尺寸，封面另存一份缩小的。
//
// 只做"读一张图 → 缩小 → 写一张 JPEG"，不碰 TDLib、不碰相册。

import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { logE } from './log';

// 长边上限。Telegram 的内联缩略图约定是 320。
export const SEND_THUMB_MAX_EDGE: number = 320;

// JPEG 质量。85 在 320px 上肉眼无损，而体积只有几十 KB。
const SEND_THUMB_QUALITY: number = 85;

export interface SendThumb {
  // 空串 = 没做出来，调用方按"没有封面"处理（保持不填 thumbnail 的老行为）。
  path: string;
  width: number;
  height: number;
}

export const NO_SEND_THUMB: SendThumb = { path: '', width: 0, height: 0 };

// 目标尺寸：等比缩到长边不超过 maxEdge，**不放大**。
// 纯函数，好测——尺寸算错就是"封面又被拒一次"，值得单独钉住。
export function thumbTargetSize(width: number, height: number, maxEdge: number): SendThumb {
  if (width <= 0 || height <= 0 || maxEdge <= 0) {
    return NO_SEND_THUMB;
  }
  const longest: number = Math.max(width, height);
  if (longest <= maxEdge) {
    return { path: '', width: Math.round(width), height: Math.round(height) };
  }
  const scale: number = maxEdge / longest;
  // 至少 1px：极端长条图等比缩下来短边会归零，解码器不收 0。
  return {
    path: '',
    width: Math.max(1, Math.round(width * scale)),
    height: Math.max(1, Math.round(height * scale))
  };
}

// 把 srcPath 缩小写到 destPath。失败一律返回 NO_SEND_THUMB——没有封面只是没有
// 预览图，不该让整条消息发不出去。
export async function makeSendThumb(srcPath: string, destPath: string,
  maxEdge: number = SEND_THUMB_MAX_EDGE): Promise<SendThumb> {
  if (srcPath === '' || destPath === '') {
    return NO_SEND_THUMB;
  }
  let source: image.ImageSource | null = null;
  let pixels: image.PixelMap | null = null;
  let dest: fileIo.File | null = null;
  let packer: image.ImagePacker | null = null;
  try {
    source = image.createImageSource(srcPath);
    const info: image.ImageInfo = await source.getImageInfo();
    const target: SendThumb =
      thumbTargetSize(info.size.width, info.size.height, maxEdge);
    if (target.width <= 0 || target.height <= 0) {
      return NO_SEND_THUMB;
    }
    // desiredSize 是在**解码时**降采样，不是解完再缩——省内存也省时间。
    pixels = await source.createPixelMap({
      desiredSize: { width: target.width, height: target.height }
    });
    dest = await fileIo.open(destPath,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    packer = image.createImagePacker();
    await packer.packToFile(pixels, dest.fd,
      { format: 'image/jpeg', quality: SEND_THUMB_QUALITY });
    return { path: destPath, width: target.width, height: target.height };
  } catch (error) {
    logE(`makeSendThumb(${srcPath}) failed: ${error}`);
    return NO_SEND_THUMB;
  } finally {
    if (packer !== null) {
      try {
        await packer.release();
      } catch (error) {
        logE(`makeSendThumb packer release failed: ${error}`);
      }
    }
    if (pixels !== null) {
      try {
        await pixels.release();
      } catch (error) {
        logE(`makeSendThumb pixelmap release failed: ${error}`);
      }
    }
    if (dest !== null) {
      fileIo.closeSync(dest);
    }
    source?.release();
  }
}
