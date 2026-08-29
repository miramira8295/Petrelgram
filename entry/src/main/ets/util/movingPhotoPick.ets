import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { dataSharePredicates } from '@kit.ArkData';
import { fileIo as fs } from '@kit.CoreFileKit';
import { livePhotoFileName } from './livePhoto';
import { logE, logW } from './log';

// 从相册选中的这一项，如果是**实况照片**（鸿蒙「动态照片」，PhotoSubtype.MOVING_PHOTO），
// 就把它的动态部分——带音轨的 mp4——导出到应用沙箱并返回路径；不是实况、或导出
// 失败时返回 ''，调用方按普通图片处理。
//
// 【为什么只要视频那一半】PG 发实况走的是 inputMessageVideo：其他客户端收到就是
// 一段普通有声视频、照常播放，而 PG 靠文件名标记把它认回实况（判据见
// util/livePhoto）。静图那一半用不上——视频的封面帧就是它。但 requestContent 的
// 双参重载**要求两个路径都给**，所以静图还是得导一次，导完就删。
//
// 【为什么不用 MOVING_PHOTO_IMAGE_TYPE 过滤】那个 MIME 会把选择器**限制成只能选
// 实况**，而这里是通用的「发图/发视频」入口，用户多半在选普通照片。所以仍然用
// IMAGE_VIDEO_TYPE 让他随便挑，选完之后再按 URI 回查 subtype。
export async function exportLivePhotoMotion(context: Context, uri: string,
  filesDir: string, unique: string): Promise<string> {
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
      return '';
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
    removeQuietly(stillPath);
    logW(`[LivePhoto] exported motion for ${uri}`);
    return videoPath;
  } catch (error) {
    // 拿不到 subtype、不是实况、导出失败——一律退回"当普通图片发"。这条路径不该
    // 因为实况没导出成功就让用户发不了图。
    logE(`exportLivePhotoMotion failed: ${error}`);
    return '';
  }
}

function removeQuietly(path: string): void {
  try {
    fs.unlinkSync(path);
  } catch (error) {
    logE(`exportLivePhotoMotion cleanup failed: ${error}`);
  }
}
