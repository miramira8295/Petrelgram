// 从包信息和 deviceInfo 读 setTdlibParameters 的设备三项。纯逻辑在
// tdDeviceParams.ets，这里只负责「读」，故意和它分开——见那边的文件头。
import { bundleManager } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { logE } from './log';
import { DeviceFacts, TdDeviceParams, resolveTdDeviceParams } from './tdDeviceParams';

// 每一项单独 try：getBundleInfoForSelfSync 会抛（diagLogExport 里有前例），
// 而少一项退到兜底远好过登录起不来。
export function readTdDeviceParams(): TdDeviceParams {
  let versionName: string = '';
  try {
    versionName = bundleManager.getBundleInfoForSelfSync(
      bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT
    ).versionName;
  } catch (e) {
    logE(`tdDeviceParams getBundleInfo failed: ${e}`);
  }
  let facts: DeviceFacts = {
    marketName: '', productModel: '', distributionOSVersion: '', osFullName: '',
    sdkApiVersion: 0, versionName: versionName
  };
  try {
    facts = {
      marketName: deviceInfo.marketName,
      productModel: deviceInfo.productModel,
      distributionOSVersion: deviceInfo.distributionOSVersion,
      osFullName: deviceInfo.osFullName,
      sdkApiVersion: deviceInfo.sdkApiVersion,
      versionName: versionName
    };
  } catch (e) {
    logE(`tdDeviceParams deviceInfo failed: ${e}`);
  }
  return resolveTdDeviceParams(facts);
}
