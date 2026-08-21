import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { logE } from './log';

// 已下载的头像文件 → PixelMap。系统通知的 largeIcon 与来电界面的 userProfile
// 都要 PixelMap，解码逻辑在此共用。
// 解码结果按路径缓存：通知可能连续发布多条，重复解码同一头像很浪费。
const cache: Map<string, image.PixelMap> = new Map();
const SIZE: number = 96;

export function avatarPixelMap(avatarPath: string): image.PixelMap | undefined {
  if (avatarPath === '') {
    return undefined;
  }
  const cached = cache.get(avatarPath);
  if (cached !== undefined) {
    return cached;
  }
  let file: fileIo.File | null = null;
  try {
    file = fileIo.openSync(avatarPath, fileIo.OpenMode.READ_ONLY);
    const source: image.ImageSource = image.createImageSource(file.fd);
    const pixelMap: image.PixelMap = source.createPixelMapSync({
      desiredSize: { width: SIZE, height: SIZE }
    });
    source.release();
    // 头像文件路径随内容变化，缓存不会读到过期图；上限防止长期运行膨胀。
    if (cache.size > 64) {
      cache.clear();
    }
    cache.set(avatarPath, pixelMap);
    return pixelMap;
  } catch (e) {
    logE(`avatarPixelMap(${avatarPath}) failed: ${(e as Error).message}`);
    return undefined;
  } finally {
    if (file !== null) {
      try {
        fileIo.closeSync(file);
      } catch (e) {
        // 关闭失败不影响已解码的位图
      }
    }
  }
}

// 来电界面的 userProfile 是必填项，没有头像时给一张占位图。
export function avatarPixelMapOrPlaceholder(avatarPath: string): image.PixelMap {
  const decoded = avatarPixelMap(avatarPath);
  if (decoded !== undefined) {
    return decoded;
  }
  return image.createPixelMapSync(
    new ArrayBuffer(SIZE * SIZE * 4), { size: { width: SIZE, height: SIZE } });
}
