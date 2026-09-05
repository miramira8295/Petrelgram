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

// --- 以下两段是 B3 从 ChatPage.ets 搬来的纯计算，副作用（拨号、拉起地图、
// toast）仍留在页面里。搬迁只把 `this` 换成显式参数，判据与拼串逐字不变。---

// 共享联系人卡片里的电话号码 → 能交给 `tel:` 的号码。原
// `private openSharedPhone(phone, skipGuard)` 的第一段。
//
// 白名单只留 0-9 和 `+ * #`：vCard 里的号码常带空格、连字符、括号，甚至
// "(work) +86 138-0000-0000" 这种前缀文字；`*`/`#` 要留是因为分机与运营商
// 短码（如 `*100#`）本来就靠它们。
//
// 返回 `''` 表示这串东西里根本没有可拨的字符——页面据此弹「无电话号码」并
// **不**拉起拨号盘（原实现同此）。
export function normalizePhoneForDial(phone: string): string {
  return phone.trim().replace(/[^0-9+*#]/g, '');
}

// 打开共享位置要用的两个 URI：先试 geo:（系统地图），拉不起来再退到网页。
export interface SharedLocationUris {
  // 交给系统地图 App 的 geo: URI。
  geoUri: string;
  // geo: 没人接时的网页兜底（OpenStreetMap）。
  webFallback: string;
}

// 原 `private openSharedLocation(latitude, longitude, label, valid)` 里的拼串段。
//
// valid = 消息自带的坐标可用（TDLib 的 location 有效）。无效时坐标是 0,0，
// 只能拿标签去搜——geo 用 `geo:0,0?q=<标签>`（Android 的老约定：0,0 + q 表示
// "按名字搜"），网页走 OSM 的 /search。
//
// 【返回空串 = 无事可做】原实现在 `!valid && 标签为空` 时直接弹「无位置信息」
// 并 return，压根不拼 URI。这里保持同一边界：两个字段都返回 `''`，页面按
// `geoUri === ''` 走那条 toast 分支。**不要**擅自改成"照样拼一个 geo:0,0?q="
// ——那会把一个没有任何信息的搜索丢给地图 App。
export function sharedLocationUris(
  latitude: number, longitude: number, label: string, valid: boolean
): SharedLocationUris {
  const cleanLabel: string = label.trim();
  if (!valid && cleanLabel === '') {
    return { geoUri: '', webFallback: '' };
  }
  // 没有标签时用坐标当搜索词，这样地图 App 的搜索框里至少显示得出东西。
  const coordinate: string = `${latitude},${longitude}`;
  const query: string = encodeURIComponent(cleanLabel !== '' ? cleanLabel : coordinate);
  const geoUri: string = valid ? `geo:${latitude},${longitude}?q=${query}` : `geo:0,0?q=${query}`;
  const webFallback: string = valid
    ? `https://www.openstreetmap.org/?mlat=${latitude}&mlon=${longitude}#map=16/${latitude}/${longitude}`
    : `https://www.openstreetmap.org/search?query=${query}`;
  return { geoUri: geoUri, webFallback: webFallback };
}
