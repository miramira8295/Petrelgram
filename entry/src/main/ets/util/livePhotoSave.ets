import { media } from '@kit.MediaKit';
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { common } from '@kit.AbilityKit';
import { logE } from './log';

// 把 PG 发的实况存回图库，变回一张**真的**动态照片（PhotoSubtype.MOVING_PHOTO），
// 而不是一段视频。
//
// 【为什么必须走 SaveButton 安全控件】创建动态照片资产只有
// MediaAssetChangeRequest.createAssetRequest + 两次 addResource 这一条路（官方
// 《访问和管理动态照片资源》）。而它要么申请常驻的 ohos.permission.WRITE_IMAGEVIDEO，
// 要么由用户点一次 SaveButton 临时授权。本应用一贯避开常驻的媒体写权限——普通的
// 保存走的是免权限的 showAssetsCreationDialog（见 util/mediaSaver）——所以这里
// 用安全控件，调用方必须把它做成用户真的点下去的那个按钮。
//
// 【为什么不能沿用 showAssetsCreationDialog】它每个 config 只返回**一个**目标
// URI，而动态照片要写入静图和视频两份资源；官方文档里也没有用它创建动态照片的
// 写法。PhotoCreationConfig.subtype 虽然接受 MOVING_PHOTO，但"两份资源怎么进
// 一个 URI"没有任何说明，赌不得。

// 动态照片的视频时长上限（秒）。系统的硬限制，超了 applyChanges 会失败。
// util/livePhoto 的 LIVE_PHOTO_MAX_SECONDS 取同一个值，判定阶段就已经挡住了。
export const MOVING_PHOTO_MAX_SECONDS: number = 10;

// 从视频里抽第一帧存成 JPEG，当动态照片的静图那一半。
//
// 【为什么不用现成的缩略图】TDLib 给的视频缩略图只有几百像素宽，而动态照片的
// 静图就是用户在图库里看到的那张——低清的存回去等于毁了这张照片。抽首帧拿到的
// 是原始分辨率。
export async function extractFirstFrame(videoPath: string, destJpg: string,
  width: number, height: number): Promise<boolean> {
  let src: fileIo.File | null = null;
  let dest: fileIo.File | null = null;
  let generator: media.AVImageGenerator | null = null;
  try {
    src = await fileIo.open(videoPath, fileIo.OpenMode.READ_ONLY);
    generator = await media.createAVImageGenerator();
    generator.fdSrc = { fd: src.fd };
    // NEXT_SYNC：取 0 之后最近的一个**关键帧**。实况的第一帧必是关键帧，而
    // CLOSEST 会去解码非关键帧，慢且没必要。
    const frame: image.PixelMap = await generator.fetchFrameByTime(
      0, media.AVImageQueryOptions.AV_IMAGE_QUERY_NEXT_SYNC,
      { width: width > 0 ? width : -1, height: height > 0 ? height : -1 });
    dest = await fileIo.open(destJpg,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    const packer: image.ImagePacker = image.createImagePacker();
    await packer.packToFile(frame, dest.fd, { format: 'image/jpeg', quality: 95 });
    await packer.release();
    await frame.release();
    return true;
  } catch (error) {
    logE(`extractFirstFrame(${videoPath}) failed: ${error}`);
    return false;
  } finally {
    if (generator !== null) {
      try {
        await generator.release();
      } catch (error) {
        logE(`extractFirstFrame release failed: ${error}`);
      }
    }
    if (src !== null) {
      fileIo.closeSync(src);
    }
    if (dest !== null) {
      fileIo.closeSync(dest);
    }
  }
}

// 把静图 + 视频写成图库里的一张动态照片。
// **必须在 SaveButton 的 onClick 里调**，否则没有写入权限。
export async function saveMovingPhoto(context: common.UIAbilityContext,
  imagePath: string, videoPath: string, title: string): Promise<void> {
  const helper: photoAccessHelper.PhotoAccessHelper =
    photoAccessHelper.getPhotoAccessHelper(context);
  const request: photoAccessHelper.MediaAssetChangeRequest =
    photoAccessHelper.MediaAssetChangeRequest.createAssetRequest(
      context, photoAccessHelper.PhotoType.IMAGE, 'jpg',
      { title: title, subtype: photoAccessHelper.PhotoSubtype.MOVING_PHOTO });
  // addResource 要的是 fileUri 形式，不是裸路径。
  request.addResource(photoAccessHelper.ResourceType.IMAGE_RESOURCE,
    fileUri.getUriFromPath(imagePath));
  request.addResource(photoAccessHelper.ResourceType.VIDEO_RESOURCE,
    fileUri.getUriFromPath(videoPath));
  await helper.applyChanges(request);
}
