// 读本地图片的像素尺寸。
//
// 用途：实况照片的静图既是视频封面，**也是视频旋转之后的真实显示尺寸**——
// 相机把竖拍视频存成"横向宽高 + 旋转矩阵"，直接拿视频容器里那对值去填
// inputMessageVideo.width/height，接收端就会把它横过来（用户实测）。静图是
// 解码后落盘的，宽高天然是摆正的，拿它当几何来源最省事、也最准。
//
// 读不到时返回 0/0，调用方按"没有几何"处理（保持老行为，不填那几个字段）。

import { image } from '@kit.ImageKit';
import { logE } from './log';

export interface ImageSize {
  width: number;
  height: number;
}

export const EMPTY_IMAGE_SIZE: ImageSize = { width: 0, height: 0 };

export async function imageSizeOf(path: string): Promise<ImageSize> {
  if (path === '') {
    return EMPTY_IMAGE_SIZE;
  }
  let source: image.ImageSource | null = null;
  try {
    source = image.createImageSource(path);
    const info: image.ImageInfo = await source.getImageInfo();
    return { width: info.size.width, height: info.size.height };
  } catch (error) {
    logE(`imageSizeOf failed for ${path}: ${error}`);
    return EMPTY_IMAGE_SIZE;
  } finally {
    source?.release();
  }
}
