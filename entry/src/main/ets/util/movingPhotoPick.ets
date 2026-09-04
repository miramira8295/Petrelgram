import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { dataSharePredicates } from '@kit.ArkData';
import { livePhotoFileName } from './livePhoto';
import { ImageSize, imageSizeOf } from './imageSize';
import { NO_SEND_THUMB, SendThumb, makeSendThumb } from './sendThumb';
import { logE, logW } from './log';

// 从相册选中的这一项，如果是**实况照片**（鸿蒙「动态照片」，PhotoSubtype.MOVING_PHOTO），
// 就把它的动态部分——带音轨的 mp4——导出到应用沙箱并返回路径；不是实况、或导出
// 失败时返回 ''，调用方按普通图片处理。
//
// 【视频 + 静图两半都要】PG 发实况走的是 inputMessageVideo：其他客户端收到就是
// 一段普通有声视频、照常播放，而 PG 靠文件名标记把它认回实况（判据见
// util/livePhoto）。
//
// **静图不能删。** 这里原来的假设是「视频的封面帧就是它，静图用不上」——不成立：
// TDLib 的 inputMessageVideo.thumbnail 是**发送方**提供封面的地方，不给就没有，
// 于是接收端气泡里一片空白（用户实测："这个视频没有预览图"）。而且静图的宽高是
// **旋转之后**的真实显示尺寸，正好用来填 inputMessageVideo 的 width/height——
// 不填的话接收侧按容器里那对旋转前的值排版，视频就是横过来的（同一条用户反馈
// 的后半句："打开后也是横向的90度旋转了"）。
//
// 【为什么不用 MOVING_PHOTO_IMAGE_TYPE 过滤】那个 MIME 会把选择器**限制成只能选
// 实况**，而这里是通用的「发图/发视频」入口，用户多半在选普通照片。所以仍然用
// IMAGE_VIDEO_TYPE 让他随便挑，选完之后再按 URI 回查 subtype。
// 实况导出的结果。videoPath 为空串表示"这一项不是实况 / 导出失败"，
// 调用方按普通图片处理。
export interface LivePhotoExport {
  videoPath: string;
  // 全尺寸静图。**不**直接当封面发（太大，见 util/sendThumb），它的用处是
  // 提供旋转之后的真实显示尺寸。
  stillPath: string;
  // 视频的显示宽高（= 静图宽高）。填进 inputMessageVideo.width/height，
  // 不填接收侧就按容器里旋转前那对值排版，竖拍视频横过来。
  displayWidth: number;
  displayHeight: number;
  // 真正发出去的封面：静图缩到长边 320 的那一份，以及**它自己**的宽高。
  // inputThumbnail.width/height 说的是缩略图的尺寸，不是视频的。
  thumbPath: string;
  thumbWidth: number;
  thumbHeight: number;
}

export const NO_LIVE_PHOTO: LivePhotoExport = {
  videoPath: '', stillPath: '',
  displayWidth: 0, displayHeight: 0,
  thumbPath: '', thumbWidth: 0, thumbHeight: 0
};

export async function exportLivePhotoMotion(context: Context, uri: string,
  filesDir: string, unique: string): Promise<LivePhotoExport> {
  try {
    const helper: photoAccessHelper.PhotoAccessHelper =
      photoAccessHelper.getPhotoAccessHelper(context);
    const predicates: dataSharePredicates.DataSharePredicates =
      new dataSharePredicates.DataSharePredicates();
    predicates.equalTo(photoAccessHelper.PhotoKeys.URI, uri);
    // fetchColumns 必须显式带上 subtype，否则 asset.get 取不到它。
    const options: photoAccessHelper.FetchOptions = {
      fetchColumns: [photoAccessHelper.PhotoKeys.PHOTO_SUBTYPE],
      predicates: predicates
    };
    const fetched: photoAccessHelper.FetchResult<photoAccessHelper.PhotoAsset> =
      await helper.getAssets(options);
    const asset: photoAccessHelper.PhotoAsset = await fetched.getFirstObject();
    const subtype: number =
      asset.get(photoAccessHelper.PhotoKeys.PHOTO_SUBTYPE) as number;
    if (subtype !== photoAccessHelper.PhotoSubtype.MOVING_PHOTO) {
      return NO_LIVE_PHOTO;
    }

    const videoPath: string = `${filesDir}/${livePhotoFileName(unique)}`;
    const stillPath: string = `${filesDir}/live_still_${unique}.jpg`;
    const moving: photoAccessHelper.MovingPhoto =
      await new Promise<photoAccessHelper.MovingPhoto>((
        resolve: (value: photoAccessHelper.MovingPhoto) => void,
        reject: (reason: Error) => void
      ): void => {
        photoAccessHelper.MediaAssetManager.requestMovingPhoto(context, asset,
          { deliveryMode: photoAccessHelper.DeliveryMode.FAST_MODE },
          {
            onDataPrepared: (data: photoAccessHelper.MovingPhoto): void => { resolve(data); }
          }).catch((error: Error): void => { reject(error); });
      });
    await moving.requestContent(stillPath, videoPath);
    // 静图给几何，缩略图给封面——两件事，两个文件。
    const size: ImageSize = await imageSizeOf(stillPath);
    const thumb: SendThumb = size.width > 0
      ? await makeSendThumb(stillPath, `${filesDir}/live_thumb_${unique}.jpg`)
      : NO_SEND_THUMB;
    logW(`[LivePhoto] exported motion+still ${size.width}x${size.height}` +
      ` thumb=${thumb.width}x${thumb.height} for ${uri}`);
    return {
      videoPath, stillPath,
      displayWidth: size.width, displayHeight: size.height,
      thumbPath: thumb.path, thumbWidth: thumb.width, thumbHeight: thumb.height
    };
  } catch (error) {
    // 拿不到 subtype、不是实况、导出失败——一律退回"当普通图片发"。这条路径不该
    // 因为实况没导出成功就让用户发不了图。
    logE(`exportLivePhotoMotion failed: ${error}`);
    return NO_LIVE_PHOTO;
  }
}
