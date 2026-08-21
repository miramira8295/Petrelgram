import { common, Want, wantConstant } from '@kit.AbilityKit';
import { fileUri } from '@kit.CoreFileKit';
import { logE } from './log';

// Open a downloaded local file with whatever system app handles its type.
// Resolves false when the source is invalid or no installed ability accepts it,
// so callers can show a useful failure state instead of silently doing nothing.
export async function openLocalFile(
  context: common.UIAbilityContext,
  path: string,
  mimeType: string
): Promise<boolean> {
  if (path === '' || context === undefined) {
    return false;
  }
  try {
    const uri = fileUri.getUriFromPath(path);
    const want: Want = {
      action: 'ohos.want.action.viewData',
      uri,
      flags: wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION
    };
    if (mimeType !== '') {
      want.type = mimeType;
    }
    await context.startAbility(want);
    return true;
  } catch (e) {
    logE(`openLocalFile failed for ${path}: ${JSON.stringify(e)}`);
    return false;
  }
}
