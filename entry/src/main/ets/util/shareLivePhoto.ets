import { common } from '@kit.AbilityKit';
import { LivePhotoExport, exportLivePhotoMotion } from './movingPhotoPick';
import { SharedItem, SharedPayload } from './sharedContent';
import { logI } from './log';

// 分享进来的实况照片。
//
// 【问题】系统分享把一张实况照片交给我们时，记录里的 utd 就是普通图片
// （general.image / general.jpeg），uri 指向那张静图——**动态部分根本不在
// 这条记录里**。照着发出去就是一张静态图，用户报的「实况照片分享变成图片了」。
//
// 【怎么拿回来】和从相册选图那条路完全一样：拿**原始 URI**去媒体库查
// PhotoKeys.PHOTO_SUBTYPE，是 MOVING_PHOTO 就用 requestMovingPhoto 导出动态
// 部分（util/movingPhotoPick 里那一整套，含 HIGH_QUALITY_MODE 与 #193 的
// 尺寸订正）。所以 SharedItem 上必须留着复制进沙箱**之前**那个 sourceUri。
//
// 【为什么放在主应用做、不在分享面板里做】导出走 HIGH_QUALITY_MODE，系统要
// 现生成高质量资源，是秒级的；分享面板那个扩展进程只有几百毫秒把界面画出来，
// 在那里等就是让面板卡住，而且它未必有媒体库的读权限。
//
// 查不到就原样退回按静图发——绝不因为一次查询失败丢内容。

// 视频的封面与几何。**不放进 SharedItem**：那个结构要跨进程序列化，多带六个
// 字段只为一种情形不值当；而且这些值只有主应用侧算得出来。
export interface ShareMediaGeometry {
  thumbPath: string;
  thumbWidth: number;
  thumbHeight: number;
  width: number;
  height: number;
}

export interface UpgradedShare {
  payload: SharedPayload;
  // 按最终路径索引。发送时查一下，没有就是普通图片/视频，按原来的发。
  geometry: Map<string, ShareMediaGeometry>;
}

// 逐个 await 而不是并发：requestMovingPhoto 背后是媒体库的解码与落盘，
// 一次几张全并发只会互相抢资源（与 AttachActions.collectPickedMedia 同一理由）。
export async function upgradeLivePhotos(context: common.Context,
  payload: SharedPayload): Promise<UpgradedShare> {
  const media: SharedItem[] = [];
  const geometry: Map<string, ShareMediaGeometry> = new Map<string, ShareMediaGeometry>();
  let seq: number = 0;
  for (let i = 0; i < payload.media.length; i++) {
    const item: SharedItem = payload.media[i];
    // 只有图片才可能是实况；视频/文档/音频直接过。
    if (item.kind !== 'image' || item.sourceUri === '') {
      media.push(item);
      continue;
    }
    const live: LivePhotoExport = await exportLivePhotoMotion(
      context, item.sourceUri, context.filesDir, `share_${Date.now()}_${++seq}`);
    if (live.videoPath === '') {
      media.push(item);
      continue;
    }
    logI(`[Share] live photo recovered: ${live.displayWidth}x${live.displayHeight}`);
    media.push({
      kind: 'video',
      uri: live.videoPath,
      text: '',
      title: item.title,
      sourceUri: item.sourceUri
    });
    geometry.set(live.videoPath, {
      thumbPath: live.thumbPath,
      thumbWidth: live.thumbWidth,
      thumbHeight: live.thumbHeight,
      width: live.displayWidth,
      height: live.displayHeight
    });
  }
  return { payload: { caption: payload.caption, media: media }, geometry: geometry };
}
