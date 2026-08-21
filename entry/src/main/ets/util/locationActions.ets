import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';
import { liveLocation } from '../services/LiveLocationService';
import { logE } from './log';

// 位置相关的两个交互前置动作。都不碰页面状态。

// 先要权限再干活。两个权限一起要：精确定位可能被用户拒掉，只给模糊的也能用。
export function withLocationPermission(
  context: common.UIAbilityContext, run: () => void
): void {
  const permissions: Permissions[] =
    ['ohos.permission.APPROXIMATELY_LOCATION', 'ohos.permission.LOCATION'];
  abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context, permissions)
    .then((result): void => {
      if (result.authResults.length > 0 && result.authResults[0] === 0) {
        run();
        return;
      }
      promptAction.showToast({ message: $r('app.string.cp_needs_location'), duration: 1800 });
    })
    .catch((e: BusinessError): void => {
      logE(`location permission failed: ${e.message}`);
    });
}

// 停止共享是不可撤销的：一旦结束，那条消息就再也编辑不回来了（服务端直接
// 判定为不可编辑），只能重新发一条。所以先确认。
export function confirmStopLiveLocation(): void {
  promptAction.showDialog({
    title: $r('app.string.cp_stop_live_location'),
    message: $r('app.string.cp_stop_live_location_body'),
    buttons: [
      { text: $r('app.string.cancel'), color: '#8E8E93' },
      { text: $r('app.string.cp_stop_sharing'), color: '#D95B57' }
    ]
  }).then((result: promptAction.ShowDialogSuccessResponse): void => {
    if (result.index !== 1) {
      return;
    }
    liveLocation.stopSharing();
    promptAction.showToast({ message: $r('app.string.cp_live_location_stopped'), duration: 1500 });
  }).catch((e: Object): void => {
    logE(`confirmStopLiveLocation failed: ${JSON.stringify(e)}`);
  });
}
