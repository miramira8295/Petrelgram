import { describe, expect, it } from '@ohos/hypium';
import {
  DeviceFacts, FALLBACK_APP_VERSION, FALLBACK_DEVICE_MODEL, resolveTdDeviceParams
} from '../main/ets/util/tdDeviceParams';

export default function tdDeviceParamsTest() {
  describe('tdDeviceParams', () => {
    const full: DeviceFacts = {
      marketName: 'HUAWEI Mate 70 Pro+', productModel: 'MLR-AL10',
      distributionOSVersion: '6.0.0', osFullName: 'OpenHarmony-7.0.0.102(Beta2)',
      sdkApiVersion: 26, versionName: '1.4.3'
    };

    it('机型用市场名、系统版本带 API 号、应用版本来自包信息', 0, (): void => {
      const p = resolveTdDeviceParams(full);
      expect(p.deviceModel).assertEqual('HUAWEI Mate 70 Pro+');
      expect(p.systemVersion).assertEqual('HarmonyOS 6.0.0 (API 26)');
      expect(p.applicationVersion).assertEqual('1.4.3');
    });

    it('没有市场名时退到产品型号', 0, (): void => {
      const facts: DeviceFacts = {
        marketName: '', productModel: full.productModel,
        distributionOSVersion: full.distributionOSVersion, osFullName: full.osFullName,
        sdkApiVersion: full.sdkApiVersion, versionName: full.versionName
      };
      expect(resolveTdDeviceParams(facts).deviceModel).assertEqual('MLR-AL10');
    });

    it('发行版版本号取不到时用 osFullName，去掉 OpenHarmony- 前缀', 0, (): void => {
      const facts: DeviceFacts = {
        marketName: full.marketName, productModel: full.productModel,
        distributionOSVersion: '', osFullName: full.osFullName,
        sdkApiVersion: full.sdkApiVersion, versionName: full.versionName
      };
      expect(resolveTdDeviceParams(facts).systemVersion)
        .assertEqual('HarmonyOS 7.0.0.102(Beta2) (API 26)');
    });

    it('全部取不到时三项仍非空——TDLib 拒绝空的 device_model / application_version', 0, (): void => {
      const facts: DeviceFacts = {
        marketName: ' ', productModel: '', distributionOSVersion: '', osFullName: '',
        sdkApiVersion: 0, versionName: ''
      };
      const p = resolveTdDeviceParams(facts);
      expect(p.deviceModel).assertEqual(FALLBACK_DEVICE_MODEL);
      expect(p.systemVersion).assertEqual('HarmonyOS');
      expect(p.applicationVersion).assertEqual(FALLBACK_APP_VERSION);
    });
  });
}
