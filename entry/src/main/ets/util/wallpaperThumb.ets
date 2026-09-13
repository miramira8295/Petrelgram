import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { uploadedThumbPath } from './localWallpaper';
import { logE } from './log';

// 上传壁纸的小缩略图（issue #201 第 7 条）。
//
// 自选壁纸是原样拷贝的相机原图，「已上传」那排却把它当 52vp 小方块显示。
// Image.autoResize 默认 false，不给尺寸就按原图分辨率解码：一张 12MP ≈ 48MB，
// 几张下来低内存机型直接被杀——就是"部分设备闪退"。
// 这里在导入时另存一份 ≤512px 的 JPEG。desiredSize 对 JPEG/HEIF 是**解码时
// 降采样**（图片框架文档），原图不会在内存里完整出现。
// createThumbnail 更省（能直接取 EXIF 缩略图）但 @since 26，底线 20 用不了。
const THUMB_MAX_PX: number = 512;

export async function writeUploadedThumb(srcPath: string): Promise<string> {
  const dest: string = uploadedThumbPath(srcPath);
  let source: image.ImageSource | null = null;
  let pixels: image.PixelMap | null = null;
  let packer: image.ImagePacker | null = null;
  let file: fs.File | null = null;
  try {
    source = image.createImageSource(srcPath);
    const info: image.ImageInfo = await source.getImageInfo();
    const w: number = Math.max(1, info.size.width);
    const h: number = Math.max(1, info.size.height);
    const scale: number = Math.min(1, THUMB_MAX_PX / Math.max(w, h));
    pixels = await source.createPixelMap({
      desiredSize: { width: Math.max(1, Math.round(w * scale)), height: Math.max(1, Math.round(h * scale)) }
    });
    packer = image.createImagePacker();
    file = fs.openSync(dest, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    await packer.packToFile(pixels, file.fd, { format: 'image/jpeg', quality: 85 });
    return dest;
  } catch (e) {
    logE(`writeUploadedThumb failed for ${srcPath}: ${e}`);
    return '';
  } finally {
    if (file !== null) { try { fs.closeSync(file); } catch (_e) { /* 已关 */ } }
    if (packer !== null) { packer.release(); }
    if (pixels !== null) { pixels.release(); }
    if (source !== null) { source.release(); }
  }
}
