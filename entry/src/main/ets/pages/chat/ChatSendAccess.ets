import { promptAction } from '@kit.ArkUI';
import { GroupPermissions, allPermissions, permissionValue } from '../../util/chatPermissions';
import { canAttach, attachPermission, firstDeniedPermission, SEND_PERMISSION_KEYS } from '../../util/sendPermissions';
import { sendPermissionMessage } from '../../store/SendPermissionApi';
import { MediaSendItem } from '../../store/MessageStore';
import { ATTACH_KEYS } from '../../util/attachActions';
import { isAnimationPath } from '../../util/mediaPick';

export function mediaPermission(item: MediaSendItem): string {
  return item.isVideo ? 'sendVideos' : isAnimationPath(item.path) ? 'sendOtherMessages' : 'sendPhotos';
}

@ObservedV2
export class ChatSendAccess {
  @Trace value: GroupPermissions = allPermissions(true);

  update(value: GroupPermissions): void {
    if (SEND_PERMISSION_KEYS.some((key: string): boolean =>
      permissionValue(this.value, key) !== permissionValue(value, key))) { this.value = value; }
  }

  disabledAttachments(): string[] {
    return ATTACH_KEYS.filter((key: string): boolean => !canAttach(this.value, key));
  }

  allows(key: string): boolean { return permissionValue(this.value, key); }

  check(key: string): boolean {
    if (this.allows(key)) { return true; }
    promptAction.showToast({ message: sendPermissionMessage(key), duration: 2500 });
    return false;
  }

  checkAttach(key: string): boolean {
    if (canAttach(this.value, key)) { return true; }
    return this.check(key === 'media' ? 'sendPhotos' : attachPermission(key));
  }

  checkMedia(items: MediaSendItem[]): boolean {
    const denied: string = firstDeniedPermission(this.value, items.map(mediaPermission));
    return denied === '' || this.check(denied);
  }
}
