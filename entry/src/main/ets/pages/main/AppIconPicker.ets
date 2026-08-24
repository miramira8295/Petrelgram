import { bundleManager } from '@kit.AbilityKit';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { str } from '../../util/strings';
import { previewResource } from '../../util/appIconPreview';
import { logE } from '../../util/log';
import {
  APP_ICON_DEFAULT, AppIconOption, IconEnabledState,
  appIconAvailable, appIconOptions, selectedIconName
} from '../../util/appIcon';

// 预览方块的边长。在 440vp 的手机上一行放得下三个，平板右栏更宽会自动排四个
// ——用 Flex 换行而不是固定列数，就是为了不给每种宽度各写一套。
const SWATCH: number = 72;
// 桌面图标的圆角。华为的分层图标是超椭圆，方形预览配一个大圆角最接近；画成正圆
// 会让它看起来像头像而不是应用图标。
const SWATCH_RADIUS: number = 19;

// 「外观设置」里的应用图标选择器。
//
// 机制见 util/appIcon.ets 开头——纯本地的 bundleManager.setAlternateIcon，不走
// AGC、不需要权限、不需要联网。
//
// **调用方必须自己挡版本**：这个组件在 API 26 以下不该被渲染（那两个函数在低版本
// 上根本不存在）。组件内部仍然再挡一次，因为"入口藏起来了"和"调用挡住了"是两件
// 事，前者将来加第二个入口就会失效。
@Component
export struct AppIconPicker {
  // 当前生效的图标名。空串 = 默认。
  @State private selected: string = APP_ICON_DEFAULT;
  // 正在切换的那一张。切换是异步的，期间禁掉整组点击——连点两张时系统按哪一次为
  // 准是未定义的，而界面已经高亮了后点的那张，两者会对不上。
  @State private applying: boolean = false;
  private options: AppIconOption[] = appIconOptions();

  aboutToAppear(): void {
    this.loadSelection();
  }

  // 读当前启用的是哪一张。
  //
  // 不自己存这个状态：系统才是权威——重装、恢复出厂都会把它变回默认，我们存的那
  // 份会和真实桌面对不上。每次挂载现问一次，代价是一次本地调用。
  private loadSelection(): void {
    if (!appIconAvailable(deviceInfo.sdkApiVersion)) {
      return;
    }
    bundleManager.getAlternateIcons().then((infos: Array<bundleManager.AlternateIconInfo>): void => {
      const states: IconEnabledState[] = infos.map(
        (info: bundleManager.AlternateIconInfo): IconEnabledState => {
          return { name: info.iconName, enabled: info.enabled };
        });
      this.selected = selectedIconName(states);
    }).catch((e: BusinessError): void => {
      // 读不到就停在默认高亮上。不弹提示：用户是来换图标的，一进页面先看到一条
      // 没有任何可操作性的错误，而点某一张仍然可能成功。
      logE(`getAlternateIcons failed: ${e.code} ${e.message}`);
    });
  }

  private apply(option: AppIconOption): void {
    if (this.applying || option.name === this.selected) {
      return;
    }
    if (!appIconAvailable(deviceInfo.sdkApiVersion)) {
      promptAction.showToast({ message: str('app_icon_failed'), duration: 1800 });
      return;
    }
    this.applying = true;
    // 空串就是官方的「取消备用图标、恢复默认」，所以默认项走同一个调用，不需要
    // 单开一条分支。
    bundleManager.setAlternateIcon(option.name).then((): void => {
      this.selected = option.name;
      this.applying = false;
      promptAction.showToast({ message: str('app_icon_applied'), duration: 1600 });
    }).catch((e: BusinessError): void => {
      this.applying = false;
      // 高亮不动——切换失败时桌面上还是原来那张，界面必须跟桌面一致。
      logE(`setAlternateIcon(${option.name}) failed: ${e.code} ${e.message}`);
      promptAction.showToast({ message: str('app_icon_failed'), duration: 2000 });
    });
  }

  @Builder
  swatch(option: AppIconOption) {
    Column({ space: 6 }) {
      Stack() {
        // 预览图由脚本从桌面图标那两层合成，来源与真实图标完全相同——所以这里
        // 直接贴图，不再拿底色现拼（后加的三张各有各的前景，拼不出来）。
        Image(previewResource(option.preview))
          .width(SWATCH).height(SWATCH)
          .borderRadius(SWATCH_RADIUS)
          .draggable(false);
        if (this.selected === option.name) {
          // 选中标记压在右下角，而不是盖住中间——用户要同时看清选中的是哪一张。
          Row() {
            SymbolGlyph($r('sys.symbol.checkmark'))
              .fontSize(13).fontColor([Color.White]);
          }
          .width(22).height(22).borderRadius(11)
          .backgroundColor(COLOR_PRIMARY)
          .justifyContent(FlexAlign.Center)
          .border({ width: 2, color: $r('app.color.surface') })
          .offset({ x: 5, y: 5 });
        }
      }
      .width(SWATCH).height(SWATCH)
      .alignContent(Alignment.BottomEnd);
      Text(str(option.labelKey))
        .fontSize(12)
        .fontColor(this.selected === option.name ? COLOR_TEXT_PRIMARY : COLOR_TEXT_SECONDARY)
        .fontWeight(this.selected === option.name ? FontWeight.Medium : FontWeight.Normal)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis });
    }
    .width(SWATCH + 24)
    .padding({ top: 10, bottom: 10 })
    .opacity(this.applying ? 0.5 : 1)
    .accessibilityText(str('a11y_option_state', str(option.labelKey),
      this.selected === option.name ? str('a11y_selected') : ''))
    .onClick((): void => this.apply(option));
  }

  build() {
    Column({ space: 2 }) {
      Row() {
        Text(str('app_icon_title')).fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
      }.width('100%').padding({ left: 16, right: 16, top: 12 });
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        ForEach(this.options, (option: AppIconOption): void => {
          this.swatch(option);
        }, (option: AppIconOption): string => option.name);
      }
      .width('100%')
      .padding({ left: 8, right: 8 });
      Text(str('app_icon_note'))
        .fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
        .width('100%').padding({ left: 16, right: 16, bottom: 12 });
    }.width('100%');
  }
}
