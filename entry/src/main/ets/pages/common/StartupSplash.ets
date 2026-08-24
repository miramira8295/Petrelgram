import { bundleManager } from '@kit.AbilityKit';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { logE } from '../../util/log';
import { previewResource } from '../../util/appIconPreview';
import {
  APP_ICON_DEFAULT, IconEnabledState,
  appIconAvailable, previewNameOf, selectedIconName
} from '../../util/appIcon';

// 启动那一帧的品牌图。
const BRAND: number = 96;

// 系统启动窗消失之后、TDLib 就绪之前的那一帧。
//
// **这不是新增的启动阶段。** 这一帧本来就存在——Index 在 AuthStage.Init 上画的
// 是一个裸 LoadingProgress。这里只是把裸转圈换成"用户自己选的那张图标 + 转圈"，
// 没有新页面、没有 setTimeout、没有改 loadContent，启动一秒都不会变慢。
//
// **为什么不改系统启动窗。** 启动窗的图形层（startWindowAppIcon /
// Illustration / BackgroundImage）全是 profile 里的静态资源，装包时定死，整个
// SDK 里只有 setStartWindowBackgroundColor 一个运行时接口、只能改底色。而一旦
// 调了它，默认启动页就不再自动跟系统深浅色走（那是 base/dark 两份 color.json
// 在起作用）——为了让启动图跟着图标变而牺牲深浅色自适应，不划算。
//
// 所以顺序是：系统启动窗（所有人一样）→ 这一帧（你选的图标）→ 聊天列表。
// 改动之前是：系统启动窗 → 裸转圈 → 聊天列表。跳变次数没有增加。
@Component
export struct StartupSplash {
  // 当前生效的图标名。空串 = 默认，也是 API 26 以下的恒定取值。
  @State private iconName: string = APP_ICON_DEFAULT;

  aboutToAppear(): void {
    this.loadSelection();
  }

  // API 26 以下这两个函数不存在（见 util/appIcon 开头），直接停在默认那张。
  // 那也正是低版本设备上桌面图标的真实样子——它们根本换不了图标。
  private loadSelection(): void {
    if (!appIconAvailable(deviceInfo.sdkApiVersion)) {
      return;
    }
    bundleManager.getAlternateIcons().then((infos: Array<bundleManager.AlternateIconInfo>): void => {
      const states: IconEnabledState[] = infos.map(
        (info: bundleManager.AlternateIconInfo): IconEnabledState => {
          return { name: info.iconName, enabled: info.enabled };
        });
      this.iconName = selectedIconName(states);
    }).catch((e: BusinessError): void => {
      // 读不到就停在默认那张。**绝不能因此不画**：这是启动画面，空白会被当成
      // 卡死。查询是异步的，首帧本来就先画默认再换，读失败无非是没换成。
      logE(`startup getAlternateIcons failed: ${e.code} ${e.message}`);
    });
  }

  build() {
    Column({ space: 28 }) {
      Image(previewResource(previewNameOf(this.iconName)))
        .width(BRAND).height(BRAND)
        // 和选择器里同一个比例：华为分层图标是超椭圆，方图配大圆角最接近。
        .borderRadius(BRAND / 4)
        .draggable(false);
      LoadingProgress().width(36).height(36);
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center);
  }
}
