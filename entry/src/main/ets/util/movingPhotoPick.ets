import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { dataSharePredicates } from '@kit.ArkData';
import { livePhotoFileName } from './livePhoto';
import { ImageSize, imageSizeOf } from './imageSize';
import { DisplaySize } from './videoDisplaySize';
import { videoDisplaySizeOf } from './videoMeta';
import { appendLiveStill } from './livePhotoEmbed';
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
  // 生成封面缩略图，以及在读不到视频元信息时兜底提供朝向。
  stillPath: string;
  // 视频的显示宽高。填进 inputMessageVideo.width/height，不填接收侧就按容器里
  // 旋转前那对值排版，竖拍视频横过来。
  //
  // **这里必须是「视频自己的」分辨率，不能拿静图的顶。**（issue #193）
  // 华为实况的静图是全传感器几千万像素，动态部分只有 1080p 级别；填静图尺寸
  // 就是在告诉所有人「这段 1080p 的视频有 4096×3072」，接收端和存图库都会照着
  // 放大，用户看到的就是「分辨率降低、特模糊」。
  // 读不到视频元信息时才退回静图尺寸——那时朝向至少是对的，比不填强。
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
        // **HIGH_QUALITY_MODE，不能用 FAST_MODE**（issue #193：「保存的动态图片
        // 分辨率会降低，特模糊，感觉不是同一个图片一样」）。
        //
        // 华为是**分段式拍照**：按下快门先落一份低质量的，高质量那份异步生成。
        // 官方文档对两个模式的分工写得很明确——FAST_MODE 拿到什么给什么，
        // HIGH_QUALITY_MODE「确保返回高质量资源……若当前存在低质量图或视频，
        // 则申请高质量图的生成任务，待生成后返回」。
        //
        // 真机实测（2026-09-07）FAST_MODE 导出的静图只有 1440x1920（2.7MP），
        // 对实况照片的原图来说明显偏小——用户那句"感觉不是同一个图片"字面意义上
        // 就是对的：那本来就是另一份低质量资源。
        //
        // 代价是慢：需要等系统生成高质量版本。这条路本来就是"选完图再发"的
        // 异步流程，等得起；发出去的是原图比快几百毫秒重要。
        photoAccessHelper.MediaAssetManager.requestMovingPhoto(context, asset,
          { deliveryMode: photoAccessHelper.DeliveryMode.HIGH_QUALITY_MODE },
          {
            onDataPrepared: (data: photoAccessHelper.MovingPhoto): void => { resolve(data); }
          }).catch((error: Error): void => { reject(error); });
      });
    await moving.requestContent(stillPath, videoPath);
    // 静图给封面，视频给几何——两件事，两个来源。
    const size: ImageSize = await imageSizeOf(stillPath);
    const thumb: SendThumb = size.width > 0
      ? await makeSendThumb(stillPath, `${filesDir}/live_thumb_${unique}.jpg`)
      : NO_SEND_THUMB;
    // 视频自己的显示分辨率（含旋转）。读不到就退回静图尺寸——朝向是对的，
    // 只是分辨率偏大；总比不填让接收端按旋转前的值排版强。
    const shown: DisplaySize = await videoDisplaySizeOf(videoPath);
    const displayW: number = shown.width > 0 ? shown.width : size.width;
    const displayH: number = shown.height > 0 ? shown.height : size.height;
    // ⚠️ 存活实验（2026-09-07）：把全尺寸静图夹带进 mp4 尾部的 free 盒。
    // 目的是验证 Telegram 是否原样保存视频字节——验通了这就是拿回原图清晰度的
    // 通道（见 util/livePhotoBox 文件头），验不通就整块删掉。
    // 追加失败不影响发送：夹带是增量，主链路一个字节都不依赖它。
    const embedded: number = await appendLiveStill(videoPath, stillPath);
    logW(`[LivePhoto] exported motion+still still=${size.width}x${size.height}` +
      ` display=${displayW}x${displayH} thumb=${thumb.width}x${thumb.height}` +
      ` embed=${embedded} for ${uri}`);
    return {
      videoPath, stillPath,
      displayWidth: displayW, displayHeight: displayH,
      thumbPath: thumb.path, thumbWidth: thumb.width, thumbHeight: thumb.height
    };
  } catch (error) {
    // 拿不到 subtype、不是实况、导出失败——一律退回"当普通图片发"。这条路径不该
    // 因为实况没导出成功就让用户发不了图。
    logE(`exportLivePhotoMotion failed: ${error}`);
    return NO_LIVE_PHOTO;
  }
}
