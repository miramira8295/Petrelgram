import { describe, expect, it } from '@ohos/hypium';
import {
  APP_ICON_API, APP_ICON_DEFAULT, AppIconOption, IconEnabledState,
  appIconAvailable, appIconOptions, isKnownIconName, selectedIconName
} from '../main/ets/util/appIcon';

function state(name: string, enabled: boolean): IconEnabledState {
  return { name: name, enabled: enabled };
}

export default function appIconTest() {
  describe('appIcon', () => {
    it('低于 26 的设备上整个模块不可用', 0, () => {
      // setAlternateIcon 是 @since 26.0.0，而本应用 compatibleSdkVersion 是
      // 6.0.0(20)。在 20~25 上调用会抛 undefined is not callable——和当初
      // enableVisibilityLifecycleWithContentCover 崩四个路由容器是同一类。
      expect(appIconAvailable(20)).assertFalse();
      expect(appIconAvailable(25)).assertFalse();
    });

    it('26 及以上可用', 0, () => {
      expect(appIconAvailable(APP_ICON_API)).assertTrue();
      expect(appIconAvailable(30)).assertTrue();
    });

    it('sdkApiVersion 读不出来时按不可用处理', 0, () => {
      // deviceInfo.sdkApiVersion 理论上恒有值，但读到 0/NaN 时宁可少一个设置
      // 项，也不能让页面去调一个可能不存在的函数。
      expect(appIconAvailable(0)).assertFalse();
      expect(appIconAvailable(Number.NaN)).assertFalse();
    });

    it('首项恒为默认图标，且名字是空串', 0, () => {
      // setAlternateIcon('') 就是官方的「取消备用图标」，所以默认项不需要在
      // app.json5 的 alternateIcons 里占一条。
      const options: AppIconOption[] = appIconOptions();
      expect(options[0].name).assertEqual(APP_ICON_DEFAULT);
      expect(APP_ICON_DEFAULT).assertEqual('');
    });

    it('备用图标的名字互不重复且非空', 0, () => {
      // app.json5 的 schema 要求 uniqueItems；重名会让 setAlternateIcon 落到
      // 哪一张变成未定义行为。
      const options: AppIconOption[] = appIconOptions();
      const seen: string[] = [];
      for (let i = 1; i < options.length; i++) {
        expect(options[i].name.length > 0).assertTrue();
        expect(seen.indexOf(options[i].name)).assertEqual(-1);
        seen.push(options[i].name);
      }
      expect(options.length > 1).assertTrue();
    });

    it('每一项都有预览图的资源名，且是 iconprev_ 前缀', 0, () => {
      // 预览图是从各自那两层现合成的（见提交说明），命名必须与 entry 的 media
      // 一一对应——AppIconPicker 里那张映射表照着这个名字挑 $r()。
      const options: AppIconOption[] = appIconOptions();
      for (let i = 0; i < options.length; i++) {
        expect(options[i].preview.startsWith('iconprev_')).assertTrue();
      }
    });

    it('预览图资源名互不重复', 0, () => {
      // 重名意味着两张图标共用一张预览，界面上会看不出区别。
      const options: AppIconOption[] = appIconOptions();
      const seen: string[] = [];
      for (let i = 0; i < options.length; i++) {
        expect(seen.indexOf(options[i].preview)).assertEqual(-1);
        seen.push(options[i].preview);
      }
    });

    it('每一项都有文案键', 0, () => {
      const options: AppIconOption[] = appIconOptions();
      for (let i = 0; i < options.length; i++) {
        expect(options[i].labelKey.length > 0).assertTrue();
      }
    });

    it('默认名与目录里的名字都算已知', 0, () => {
      const options: AppIconOption[] = appIconOptions();
      expect(isKnownIconName(APP_ICON_DEFAULT)).assertTrue();
      expect(isKnownIconName(options[1].name)).assertTrue();
    });

    it('目录里没有的名字不算已知', 0, () => {
      expect(isKnownIconName('probe')).assertFalse();
    });

    it('没有任何备用图标启用时选中的是默认', 0, () => {
      const states: IconEnabledState[] = [state('midnight', false), state('forest', false)];
      expect(selectedIconName(states)).assertEqual(APP_ICON_DEFAULT);
    });

    it('空列表也当默认', 0, () => {
      expect(selectedIconName([])).assertEqual(APP_ICON_DEFAULT);
    });

    it('启用了哪张就选中哪张', 0, () => {
      const states: IconEnabledState[] = [state('midnight', false), state('forest', true)];
      expect(selectedIconName(states)).assertEqual('forest');
    });

    it('系统同时报了两张启用时取第一张，不抛', 0, () => {
      // 不该发生，但 getAlternateIcons 的返回值是外部数据，不能假设它自洽。
      const states: IconEnabledState[] = [state('midnight', true), state('forest', true)];
      expect(selectedIconName(states)).assertEqual('midnight');
    });
  });
}
