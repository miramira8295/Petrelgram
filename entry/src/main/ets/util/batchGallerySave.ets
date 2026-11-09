import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileUri } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { copyToUri, extensionOf } from './mediaSaver';
import { noteSavedLocal } from '../store/SavedLocalRegistry';
import { logE, logW } from './log';

// 下载中心「批量存本地」里的图片和视频（2026-09-15）：一次系统确认框存多个——showAssetsCreationDialog
// 本来就收数组，逐个调 saveMediaToGallery 会连弹 N 个框。返回存成功的源路径（用户取消 = 空数组）。

const MAX_PER_DIALOG: number = 100;

export interface GallerySaveEntry {
  path: string;
  isVideo: boolean;
}

export async function saveMediaBatchToGallery(context: common.UIAbilityContext,
  entries: GallerySaveEntry[]): Promise<string[]> {
  const valid: GallerySaveEntry[] = entries.filter((e: GallerySaveEntry): boolean => e.path !== '');
  const batch: GallerySaveEntry[] = valid.slice(0, MAX_PER_DIALOG);
  if (batch.length < valid.length) {
    logW(`saveMediaBatchToGallery: ${valid.length - batch.length} entries over the per-dialog cap were skipped`);
  }
  if (batch.length === 0) {
    return [];
  }
  const helper = photoAccessHelper.getPhotoAccessHelper(context);
  const configs: photoAccessHelper.PhotoCreationConfig[] =
    batch.map((e: GallerySaveEntry): photoAccessHelper.PhotoCreationConfig => {
      const config: photoAccessHelper.PhotoCreationConfig = {
        fileNameExtension: extensionOf(e.path, e.isVideo ? 'mp4' : 'jpg'),
        photoType: e.isVideo ? photoAccessHelper.PhotoType.VIDEO : photoAccessHelper.PhotoType.IMAGE
      };
      return config;
    });
  const sources: string[] = batch.map((e: GallerySaveEntry): string => fileUri.getUriFromPath(e.path));
  const uris: string[] = await helper.showAssetsCreationDialog(sources, configs);
  const saved: string[] = [];
  for (let i = 0; i < uris.length && i < batch.length; i++) {
    try {
      await copyToUri(batch[i].path, uris[i]);
      noteSavedLocal(context, batch[i].path);
      saved.push(batch[i].path);
    } catch (e) {
      logE(`saveMediaBatchToGallery copy(${batch[i].path}) failed: ${e}`);
    }
  }
  return saved;
}
