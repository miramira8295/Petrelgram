import { image } from '@kit.ImageKit';
import { sendableImage } from '@kit.ImageKit';
import { DecodeSize, decodeDesiredSize } from './decodeSize';
import { logE } from './log';

// Image decoding, off the UI thread.
//
// The decode itself was never the problem — 11–20ms per photo is normal for a
// 700×1280 JPEG. The problem was WHERE it ran: a device capture showed every
// CreatePixelMap on the process's main tid, because `await` in ArkTS yields the
// call stack without leaving the thread. Two or three photos entering the
// viewport in the same frame therefore spent 40ms of that frame decoding, which
// is exactly the dropped frames the jank monitor reported while scrolling a
// media-heavy chat.
//
// TaskPool runs this on a worker. PixelMap is not transferable across the
// concurrency boundary, which is what sendableImage exists for: decode to a
// sendable PixelMap here, and the caller converts it back on its own thread.
//
// desiredSize is an exact output size, NOT a bounding box: handing it the
// display box squeezes the photo into that shape, because the PixelMap itself
// comes out distorted and ImageFit.Cover has nothing left to crop. Scale the
// SOURCE dimensions so the result still covers the box at the original aspect
// ratio, and let Cover do the cropping.
//
// 缩不缩、缩多少由 util/decodeSize 决定——小幅缩放不走这条路，它的采样质量
// 不如渲染阶段的 interpolation(High)（issue #92 的头像斜边锯齿）。
@Concurrent
export async function decodeSendable(
  path: string, targetW: number, targetH: number
): Promise<sendableImage.PixelMap | undefined> {
  let source: sendableImage.ImageSource | undefined = undefined;
  try {
    // sendableImage.ImageSource only exposes createPixelMap/release, so the
    // dimensions come from a plain ImageSource — that call just parses the
    // header, and it runs on this worker too.
    const opts: image.DecodingOptions = {};
    const probe: image.ImageSource = image.createImageSource(path);
    try {
      const info: image.ImageInfo = await probe.getImageInfo();
      const want: DecodeSize | undefined =
        decodeDesiredSize(info.size.width, info.size.height, targetW, targetH);
      // undefined = 原样解码。**不是所有缩放都值得交给解码器**：见 decodeSize
      // 里的说明，小幅缩放换来的是斜边锯齿，而省不下什么。
      if (want !== undefined) {
        opts.desiredSize = { width: want.width, height: want.height };
      }
    } finally {
      probe.release();
    }
    source = sendableImage.createImageSource(path);
    return await source.createPixelMap(opts);
  } catch (e) {
    logE(`pixelDecodeTask(${path}) failed: ${e}`);
    return undefined;
  } finally {
    if (source !== undefined) {
      try {
        source.release();
      } catch (e) {
        logE(`pixelDecodeTask release failed: ${e}`);
      }
    }
  }
}
