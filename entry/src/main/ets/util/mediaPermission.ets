// 相册（媒体库）的读/写权限申请。
//
// 这两条是 user_grant：`photoAccessHelper` 的 applyChanges / getAssets /
// requestMovingPhoto 等全量接口在未授权时会抛 201，所以调用前必须先要。
// 系统选择器（PhotoViewPicker / SaveButton）不需要权限，这里管的是
// 「实况照片」那条自己直连媒体库的路。
import { abilityAccessCtrl, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { logE } from './log';

const READ_MEDIA: Permissions[] = ['ohos.permission.READ_IMAGEVIDEO'];
const WRITE_MEDIA: Permissions[] = ['ohos.permission.WRITE_IMAGEVIDEO'];

async function ensure(context: Context, permissions: Permissions[], tag: string): Promise<boolean> {
  try {
    const manager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    const result = await manager.requestPermissionsFromUser(context, permissions);
    // 全部授予才算过：被拒时调用方按"没权限"降级（实况当普通图/视频处理）。
    return result.authResults.every((code: number): boolean => code === 0);
  } catch (e) {
    logE(`${tag} permission request failed: ${(e as BusinessError).message}`);
    return false;
  }
}

export function ensureMediaRead(context: Context): Promise<boolean> {
  return ensure(context, READ_MEDIA, 'readMedia');
}

export function ensureMediaWrite(context: Context): Promise<boolean> {
  return ensure(context, WRITE_MEDIA, 'writeMedia');
}
