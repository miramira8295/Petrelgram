import { fileIo } from '@kit.CoreFileKit';
import { buildLiveStillBox, findLiveStillBox, LiveStillSlice } from './livePhotoBox';
import { logE, logW } from './log';

// 夹带静图的文件层：读写在这里，字节格式在 util/livePhotoBox（纯函数，有单测）。
//
// ⚠️ **这一整块目前是存活实验**：要验证的是 Telegram 是否原样保存上传的视频
// 字节。验通了它就是拿回实况原图清晰度的通道；验不通就把 livePhotoBox +
// 本文件 + 两个调用点一起删掉。理由与格式见 util/livePhotoBox 文件头。

// 静图夹带的体积上限。全尺寸 JPEG 常有 2–5 MB，而实况的动态部分才 1–3 MB——
// 无脑夹带会让消息体积翻倍，而且**每个收到的人都要下载**，包括用不上它的其他
// 客户端。超过上限就不夹带：宁可退回"诚实的 1080p"，也不让一条实况变成 8 MB。
export const MAX_EMBED_BYTES: number = 4 * 1024 * 1024;

// 把静图追加到视频末尾。返回真正写进去的字节数，0 表示没夹带（文件太大、
// 读失败、或静图不存在）——调用方只用它打日志，主链路不依赖。
export async function appendLiveStill(videoPath: string, stillPath: string): Promise<number> {
  let still: fileIo.File | null = null;
  let video: fileIo.File | null = null;
  try {
    const stat: fileIo.Stat = await fileIo.stat(stillPath);
    if (stat.size <= 0 || stat.size > MAX_EMBED_BYTES) {
      logW(`[LiveBox] skip embed: still is ${stat.size} bytes (cap ${MAX_EMBED_BYTES})`);
      return 0;
    }
    const jpeg: Uint8Array = new Uint8Array(stat.size);
    still = await fileIo.open(stillPath, fileIo.OpenMode.READ_ONLY);
    await fileIo.read(still.fd, jpeg.buffer);
    const box: Uint8Array = buildLiveStillBox(jpeg);
    if (box.length === 0) {
      return 0;
    }
    // 追加而不是重写：mp4 的所有盒子原样不动，我们只在最后面多挂一个 free 盒。
    video = await fileIo.open(videoPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.APPEND);
    await fileIo.write(video.fd, box.buffer);
    return box.length;
  } catch (error) {
    // 夹带是增量能力，失败绝不能影响发送。
    logE(`appendLiveStill(${videoPath}) failed: ${error}`);
    return 0;
  } finally {
    if (still !== null) { fileIo.closeSync(still); }
    if (video !== null) { fileIo.closeSync(video); }
  }
}

// 从收到的视频里取出夹带的静图，写成一个独立的 jpg。
// 返回 true 表示取出来了（destJpg 可用），false 表示这条视频没有夹带。
export async function extractLiveStill(videoPath: string, destJpg: string): Promise<boolean> {
  let src: fileIo.File | null = null;
  let dest: fileIo.File | null = null;
  try {
    const stat: fileIo.Stat = await fileIo.stat(videoPath);
    if (stat.size <= 0) {
      return false;
    }
    // 只读尾部：夹带盒在文件末尾，整段读进来对大视频是浪费。
    // 上限 + 一点余量足够覆盖盒头与整张 jpeg。
    const tailLen: number = Math.min(stat.size, MAX_EMBED_BYTES + 64 * 1024);
    const tail: Uint8Array = new Uint8Array(tailLen);
    src = await fileIo.open(videoPath, fileIo.OpenMode.READ_ONLY);
    await fileIo.read(src.fd, tail.buffer, { offset: stat.size - tailLen });
    const slice: LiveStillSlice | null = findLiveStillBox(tail);
    if (slice === null) {
      logW(`[LiveBox] no embedded still in ${videoPath} (${stat.size} bytes)`);
      return false;
    }
    logW(`[LiveBox] found embedded still: ${slice.length} bytes`);
    dest = await fileIo.open(destJpg,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    await fileIo.write(dest.fd, tail.buffer.slice(slice.start, slice.start + slice.length));
    return true;
  } catch (error) {
    logE(`extractLiveStill(${videoPath}) failed: ${error}`);
    return false;
  } finally {
    if (src !== null) { fileIo.closeSync(src); }
    if (dest !== null) { fileIo.closeSync(dest); }
  }
}
