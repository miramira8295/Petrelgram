import { str } from './strings';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs, fileShare, fileUri, picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { logE } from './log';

const COPY_BUF: number = 1024 * 1024;
const DOWNLOAD_PREFS: string = 'download_location';
const DOWNLOAD_DIRECTORY_URI: string = 'directory_uri';
const DOWNLOAD_ROOT_URI: string = 'file://docs/storage/Users/currentUser/Download';
const DOWNLOAD_APP_FOLDER: string = 'com.miramira8295.petrelgram';

export interface FileSaveProgress {
  onSaving(percent: number): void;
  onSaved(destination: string): void;
  onCancelled(): void;
  onFailed(): void;
}

function nextEventLoop(): Promise<void> {
  return new Promise<void>((resolve: (value: void) => void): void => {
    setTimeout(resolve, 0);
  });
}

async function copyToUri(
  srcPath: string, destUri: string, progress?: FileSaveProgress
): Promise<void> {
  const dest = fs.openSync(destUri,
    fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  const src = fs.openSync(srcPath, fs.OpenMode.READ_ONLY);
  try {
    const total: number = fs.statSync(src.fd).size;
    let copied: number = 0;
    let chunkCount: number = 0;
    progress?.onSaving(total === 0 ? 100 : 0);
    const buffer = new ArrayBuffer(COPY_BUF);
    let readLen = fs.readSync(src.fd, buffer); // sequential reads advance the fd position
    while (readLen > 0) {
      fs.writeSync(dest.fd, buffer.slice(0, readLen));
      copied += readLen;
      progress?.onSaving(total > 0 ? Math.min(100, Math.floor((copied / total) * 100)) : 100);
      chunkCount++;
      if (chunkCount % 4 === 0) {
        await nextEventLoop();
      }
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

function safeFileName(srcPath: string, fileName: string): string {
  const suppliedName: string = fileName.trim();
  const suppliedSlash: number = Math.max(
    suppliedName.lastIndexOf('/'),
    suppliedName.lastIndexOf('\\')
  );
  const safeSuppliedName: string = suppliedSlash >= 0
    ? suppliedName.substring(suppliedSlash + 1) : suppliedName;
  const pathName: string = srcPath.substring(srcPath.lastIndexOf('/') + 1);
  return safeSuppliedName !== ''
    ? safeSuppliedName : (pathName !== '' ? pathName : str('media_kind_file'));
}

function availableDownloadPath(directory: string, fileName: string): string {
  const dot: number = fileName.lastIndexOf('.');
  const stem: string = dot > 0 ? fileName.substring(0, dot) : fileName;
  const extension: string = dot > 0 ? fileName.substring(dot) : '';
  let candidate: string = `${directory}/${fileName}`;
  let suffix: number = 1;
  while (fs.accessSync(candidate)) {
    candidate = `${directory}/${stem} (${suffix})${extension}`;
    suffix++;
  }
  return candidate;
}

// Save a downloaded photo/video into the system gallery. Uses the asset
// creation dialog (system confirmation) — no persistent permission needed and
// it works from a plain menu item, unlike the SaveButton security control.
export async function saveMediaToGallery(
  context: common.UIAbilityContext, srcPath: string, isVideo: boolean,
  progress?: FileSaveProgress
): Promise<void> {
  try {
    const helper = photoAccessHelper.getPhotoAccessHelper(context);
    const config: photoAccessHelper.PhotoCreationConfig = {
      fileNameExtension: extensionOf(srcPath, isVideo ? 'mp4' : 'jpg'),
      photoType: isVideo ? photoAccessHelper.PhotoType.VIDEO : photoAccessHelper.PhotoType.IMAGE
    };
    const uris = await helper.showAssetsCreationDialog([fileUri.getUriFromPath(srcPath)], [config]);
    if (uris.length === 0) {
      progress?.onCancelled();
      return;
    }
    await copyToUri(srcPath, uris[0], progress);
    progress?.onSaved(str('transfer_gallery'));
    promptAction.showToast({ message: str('media_saved_gallery'), duration: 2000 });
  } catch (e) {
    logE(`saveMediaToGallery(${srcPath}) failed: ${e}`);
    progress?.onFailed();
    promptAction.showToast({ message: str('media_save_failed'), duration: 2000 });
  }
}

// Save a downloaded document via the system "save as" picker (user-visible
// location, e.g. Downloads — a silent sandbox copy would be unreachable).
export function saveFileToLocal(
  context: common.UIAbilityContext, srcPath: string, fileName: string,
  progress?: FileSaveProgress
): void {
  if (srcPath === '' || context === undefined) {
    progress?.onFailed();
    promptAction.showToast({ message: str('media_file_unavailable'), duration: 1800 });
    return;
  }
  const saveName: string = safeFileName(srcPath, fileName);
  const docPicker = new picker.DocumentViewPicker(context);
  const opts = new picker.DocumentSaveOptions();
  opts.newFileNames = [saveName];
  docPicker.save(opts).then(async (uris: string[]): Promise<void> => {
    if (uris.length === 0) {
      progress?.onCancelled();
      return;
    }
    try {
      await copyToUri(srcPath, uris[0], progress);
      progress?.onSaved(str('transfer_selected_location'));
      promptAction.showToast({ message: str('media_saved'), duration: 2000 });
    } catch (e) {
      logE(`saveFileToLocal copy failed: ${e}`);
      progress?.onFailed();
      promptAction.showToast({ message: str('media_save_failed'), duration: 2000 });
    }
  }).catch((e: Object) => {
    if (isPickerCancellation(e)) {
      progress?.onCancelled();
      return;
    }
    logE(`saveFileToLocal picker failed: ${JSON.stringify(e)}`);
    progress?.onFailed();
    promptAction.showToast({ message: str('media_cannot_open_location'), duration: 1800 });
  });
}

function downloadPolicy(uri: string): fileShare.PolicyInfo {
  return {
    uri: uri,
    operationMode: fileShare.OperationMode.READ_MODE | fileShare.OperationMode.WRITE_MODE
  };
}

function isPickerCancellation(error: Object): boolean {
  return (error as BusinessError).code === -1;
}

function folderAuthorizationAvailable(): boolean {
  return canIUse('SystemCapability.FileManagement.UserFileService.FolderSelection') &&
    canIUse('SystemCapability.FileManagement.AppFileService.FolderAuthorization');
}

async function selectDownloadDirectoryUri(context: common.UIAbilityContext): Promise<string> {
  const docPicker = new picker.DocumentViewPicker(context);
  const opts = new picker.DocumentSelectOptions();
  opts.maxSelectNumber = 1;
  opts.selectMode = picker.DocumentSelectMode.FOLDER;
  opts.defaultFilePathUri = DOWNLOAD_ROOT_URI;
  let uris: string[] = [];
  try {
    uris = await docPicker.select(opts);
  } catch (e) {
    if (isPickerCancellation(e as Object)) {
      return '';
    }
    throw e as Error;
  }
  if (uris.length === 0) {
    return '';
  }
  const directoryUri: string = uris[0];
  await fileShare.persistPermission([downloadPolicy(directoryUri)]);
  const store = preferences.getPreferencesSync(context, { name: DOWNLOAD_PREFS });
  store.putSync(DOWNLOAD_DIRECTORY_URI, directoryUri);
  await store.flush();
  return directoryUri;
}

function downloadDirectoryPath(directoryUri: string): string {
  const authorizedDirectory: string = new fileUri.FileUri(directoryUri).path;
  return authorizedDirectory.endsWith(`/${DOWNLOAD_APP_FOLDER}`)
    ? authorizedDirectory : `${authorizedDirectory}/${DOWNLOAD_APP_FOLDER}`;
}

export function getDownloadDirectoryPath(context: common.UIAbilityContext): string {
  if (context === undefined || !folderAuthorizationAvailable()) {
    return '';
  }
  const store = preferences.getPreferencesSync(context, { name: DOWNLOAD_PREFS });
  const remembered: string = store.getSync(DOWNLOAD_DIRECTORY_URI, '') as string;
  return downloadDirectoryPath(remembered !== '' ? remembered : DOWNLOAD_ROOT_URI);
}

export async function changeDownloadDirectory(context: common.UIAbilityContext): Promise<boolean> {
  if (context === undefined || !folderAuthorizationAvailable()) {
    return false;
  }
  const store = preferences.getPreferencesSync(context, { name: DOWNLOAD_PREFS });
  const previous: string = store.getSync(DOWNLOAD_DIRECTORY_URI, '') as string;
  const selected: string = await selectDownloadDirectoryUri(context);
  if (selected === '') {
    return false;
  }
  if (previous !== '' && previous !== selected) {
    try {
      await fileShare.revokePermission([downloadPolicy(previous)]);
    } catch (e) {
      logE(`changeDownloadDirectory revoke old permission failed: ${JSON.stringify(e)}`);
    }
  }
  return true;
}

async function resolveDownloadDirectoryUri(context: common.UIAbilityContext): Promise<string> {
  const store = preferences.getPreferencesSync(context, { name: DOWNLOAD_PREFS });
  const remembered: string = store.getSync(DOWNLOAD_DIRECTORY_URI, '') as string;
  if (remembered !== '') {
    try {
      await fileShare.activatePermission([downloadPolicy(remembered)]);
      return remembered;
    } catch (e) {
      store.deleteSync(DOWNLOAD_DIRECTORY_URI);
      await store.flush();
    }
  }
  return selectDownloadDirectoryUri(context);
}

// Remote saves call this before starting the TDLib download. That keeps the
// system folder picker attached to the user's tap instead of trying to open it
// later from another chat or while the app is in the background.
export async function prepareDownloadDirectory(context: common.UIAbilityContext): Promise<boolean> {
  if (context === undefined || !folderAuthorizationAvailable()) {
    return true;
  }
  try {
    return await resolveDownloadDirectoryUri(context) !== '';
  } catch (e) {
    logE(`prepareDownloadDirectory failed: ${JSON.stringify(e)}`);
    promptAction.showToast({ message: str('media_cannot_open_location'), duration: 1800 });
    return false;
  }
}

async function copyToDownloadDirectory(
  srcPath: string, fileName: string, directoryUri: string,
  progress?: FileSaveProgress
): Promise<void> {
  const directory: string = downloadDirectoryPath(directoryUri);
  if (!fs.accessSync(directory)) {
    fs.mkdirSync(directory);
  }
  const destination: string = availableDownloadPath(directory, safeFileName(srcPath, fileName));
  await copyToUri(srcPath, destination, progress);
  progress?.onSaved(DOWNLOAD_APP_FOLDER);
  promptAction.showToast({ message: str('media_saved'), duration: 2000 });
}

// The document-card save action asks for a destination directory once, then
// persists that folder grant for later saves. Regular file download/open does
// not call this function and therefore never prompts for storage access.
export function saveFileToDownloads(
  context: common.UIAbilityContext, srcPath: string, fileName: string,
  progress?: FileSaveProgress
): void {
  if (srcPath === '' || context === undefined) {
    progress?.onFailed();
    promptAction.showToast({ message: str('media_file_unavailable'), duration: 1800 });
    return;
  }
  if (!folderAuthorizationAvailable()) {
    saveFileToLocal(context, srcPath, fileName, progress);
    return;
  }
  const operation: Promise<void> = resolveDownloadDirectoryUri(context)
    .then((directoryUri: string): Promise<void> | void => {
      if (directoryUri === '') {
        progress?.onCancelled();
        return;
      }
      return copyToDownloadDirectory(srcPath, fileName, directoryUri, progress);
    });
  operation.catch((e: Object): void => {
    logE(`saveFileToDownloads failed: ${JSON.stringify(e)}`);
    progress?.onFailed();
    promptAction.showToast({ message: str('media_cannot_open_location'), duration: 1800 });
  });
}
