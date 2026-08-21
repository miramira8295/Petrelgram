import { str } from './strings';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs, fileUri, picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { logE } from './log';

const COPY_BUF: number = 1024 * 1024;

function copyToUri(srcPath: string, destUri: string): void {
  const dest = fs.openSync(destUri, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
  const src = fs.openSync(srcPath, fs.OpenMode.READ_ONLY);
  try {
    const buffer = new ArrayBuffer(COPY_BUF);
    let readLen = fs.readSync(src.fd, buffer); // sequential reads advance the fd position
    while (readLen > 0) {
      fs.writeSync(dest.fd, buffer.slice(0, readLen));
      readLen = fs.readSync(src.fd, buffer);
    }
  } finally {
    fs.closeSync(src);
    fs.closeSync(dest);
  }
}

function extensionOf(path: string, fallback: string): string {
  const dot = path.lastIndexOf('.');
  const ext = dot >= 0 ? path.substring(dot + 1).toLowerCase() : '';
  return ext.length > 0 && ext.length <= 5 ? ext : fallback;
}

// Save a downloaded photo/video into the system gallery. Uses the asset
// creation dialog (system confirmation) — no persistent permission needed and
// it works from a plain menu item, unlike the SaveButton security control.
export async function saveMediaToGallery(context: common.UIAbilityContext, srcPath: string, isVideo: boolean): Promise<void> {
  try {
    const helper = photoAccessHelper.getPhotoAccessHelper(context);
    const config: photoAccessHelper.PhotoCreationConfig = {
      fileNameExtension: extensionOf(srcPath, isVideo ? 'mp4' : 'jpg'),
      photoType: isVideo ? photoAccessHelper.PhotoType.VIDEO : photoAccessHelper.PhotoType.IMAGE
    };
    const uris = await helper.showAssetsCreationDialog([fileUri.getUriFromPath(srcPath)], [config]);
    if (uris.length === 0) {
      return; // user declined the system dialog
    }
    copyToUri(srcPath, uris[0]);
    promptAction.showToast({ message: str('media_saved_gallery'), duration: 2000 });
  } catch (e) {
    logE(`saveMediaToGallery(${srcPath}) failed: ${e}`);
    promptAction.showToast({ message: str('media_save_failed'), duration: 2000 });
  }
}

// Save a downloaded document via the system "save as" picker (user-visible
// location, e.g. Downloads — a silent sandbox copy would be unreachable).
export function saveFileToLocal(context: common.UIAbilityContext, srcPath: string, fileName: string): void {
  if (srcPath === '' || context === undefined) {
    promptAction.showToast({ message: str('media_file_unavailable'), duration: 1800 });
    return;
  }
  const suppliedName: string = fileName.trim();
  const suppliedSlash: number = Math.max(
    suppliedName.lastIndexOf('/'),
    suppliedName.lastIndexOf('\\')
  );
  const safeSuppliedName: string = suppliedSlash >= 0
    ? suppliedName.substring(suppliedSlash + 1) : suppliedName;
  const pathName: string = srcPath.substring(srcPath.lastIndexOf('/') + 1);
  const saveName: string = safeSuppliedName !== ''
    ? safeSuppliedName : (pathName !== '' ? pathName : str('media_kind_file'));
  const docPicker = new picker.DocumentViewPicker(context);
  const opts = new picker.DocumentSaveOptions();
  opts.newFileNames = [saveName];
  docPicker.save(opts).then((uris: string[]) => {
    if (uris.length === 0) {
      return; // user cancelled
    }
    try {
      copyToUri(srcPath, uris[0]);
      promptAction.showToast({ message: str('media_saved'), duration: 2000 });
    } catch (e) {
      logE(`saveFileToLocal copy failed: ${e}`);
      promptAction.showToast({ message: str('media_save_failed'), duration: 2000 });
    }
  }).catch((e: Object) => {
    logE(`saveFileToLocal picker failed: ${JSON.stringify(e)}`);
    promptAction.showToast({ message: str('media_cannot_open_location'), duration: 1800 });
  });
}
