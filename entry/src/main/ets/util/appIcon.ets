// 桌面图标自选：目录与可用性判据。
//
// **这条路不走 AGC。** 华为还有一套「图标管理服务」（AppGalleryKit 的
// appInfoManager.queryDynamicIcons / selectDynamicIcon），那套要发邮件申请开通、
// 要求应用处于正式上架状态、每张图标单独过审 1~3 个工作日。本应用在 GitHub 上
// 发未签名包，那些前置条件一条都不满足。
//
// 这里用的是 bundleManager 的另一套：图标随包预置在 AppScope/app.json5 的
// alternateIcons 里，运行时用 setAlternateIcon(name) 切换。不需要任何权限、
// 不需要联网、不经过 AGC。实测（2026-08-24）打包校验器认这个字段，字段带着
// 解析好的 iconId 落进 hap 的 module.json，与 minAPIVersion 60000020 并存。
//
// **唯一的门槛是 API 版本。** getAlternateIcons/setAlternateIcon 都是
// @since 26.0.0，而本应用的 compatibleSdkVersion 是 6.0.0(20)。在 20~25 的设备
// 上这两个函数根本不存在——调用会抛 `TypeError: undefined is not callable`，
// 和当初 enableVisibilityLifecycleWithContentCover 崩掉四个路由容器是同一类
// 事故（见 util/navSheetLifecycle）。
//
// 区别在于**这次好挡**：那次缺的是属性链上的方法，ArkTS 的属性链是固定语法、
// 中间插不进 if，只能靠 AttributeModifier；这次缺的是模块上的普通函数，一个
// 版本判断就够。判断放在这里而不是散在页面里，是为了让它可测——设备版本没法
// 在单测里伪造，但一个纯函数可以。
export const APP_ICON_API: number = 26;

// 默认图标（app.json5 里的 icon 字段那张）在目录里的名字。
// 官方约定 setAlternateIcon('') 就是「取消备用图标、恢复默认」，所以默认项
// **不需要**在 alternateIcons 里另占一条。
export const APP_ICON_DEFAULT: string = '';

export interface AppIconOption {
  // alternateIcons 里的 name 字段，必须逐字一致——对不上 setAlternateIcon
  // 抛 17700308。
  name: string;
  // 文案键。存键而不是存已翻译的字符串：这个目录是模块级常量，会在字符串源
  // 装好之前就被求值，存字符串等于把首次加载时的语言锁死（settingGroups()
  // 写成函数而不是常量数组，是同一个原因）。
  labelKey: string;
  // 预览图在 entry media 里的资源名（不带 app.media. 前缀）。
  //
  // **为什么是预览图而不是现拼**：最早那五张只换底色、前景共用同一只海燕，预览
  // 可以在界面上拿一块色块加一张前景图拼出来。后加进来的三张（frost/neon/
  // aurora）各有各的前景图形，现拼这条路当场就不成立了。
  //
  // 现在所有预览图都由脚本从**各自那两层**合成（192px），来源与桌面上那张分层
  // 图标完全相同。现拼原本想保证的"预览不会和真实图标走样"，换成生成之后反而
  // 更牢——不存在"改了底色忘了改预览"这回事，因为预览就是从底色那张图生成的。
  //
  // 存资源名而不是 Resource：$r() 的参数必须是字面量，而这张表是数据、还要被
  // 单测读。名字到 $r() 的映射在 AppIconPicker。
  preview: string;
}

// getAlternateIcons() 返回值里我们关心的两个字段。
//
// 不直接用 SDK 的 AlternateIconInfo：那个类型 @since 26.0.0，在单测环境里
// 拿不到，而且带一个我们用不上的 iconId。
export interface IconEnabledState {
  name: string;
  enabled: boolean;
}

// 目录本身。首项恒为默认。
//
// 顺序即界面顺序：三张独立设计排在默认后面，五张换底色的排在最后。
//
// 加一张图标要同时动四处：AppScope 里的 bg_/fg_/icon_*.json、app.json5 的
// alternateIcons、这张表、以及 AppIconPicker 里 name → $r() 的映射。测试挡得住
// 重名和命名走样，挡不住"四处漏了一处"。
const OPTIONS: AppIconOption[] = [
  { name: APP_ICON_DEFAULT, labelKey: 'app_icon_default', preview: 'iconprev_default' },
  // 三张独立设计：各有各的前景图形，不是换底色。
  { name: 'frost', labelKey: 'app_icon_frost', preview: 'iconprev_frost' },
  { name: 'neon', labelKey: 'app_icon_neon', preview: 'iconprev_neon' },
  { name: 'aurora', labelKey: 'app_icon_aurora', preview: 'iconprev_aurora' },
  // 以下五张是同一只海燕换底色。
  { name: 'midnight', labelKey: 'app_icon_midnight', preview: 'iconprev_midnight' },
  { name: 'graphite', labelKey: 'app_icon_graphite', preview: 'iconprev_graphite' },
  { name: 'forest', labelKey: 'app_icon_forest', preview: 'iconprev_forest' },
  { name: 'sunset', labelKey: 'app_icon_sunset', preview: 'iconprev_sunset' },
  { name: 'violet', labelKey: 'app_icon_violet', preview: 'iconprev_violet' }
];

// 设备支不支持切换图标。不支持时设置里整条入口都不出现——给一个点进去只会
// 报错的入口，比没有这个功能更糟。
//
// NaN 和 0 都判不可用：`NaN >= 26` 本来就是 false，这里显式写出来是为了让
// "读不出版本就当不支持"成为被测试钉死的行为，而不是靠运算符的巧合。
export function appIconAvailable(sdkApiVersion: number): boolean {
  if (!Number.isFinite(sdkApiVersion) || sdkApiVersion <= 0) {
    return false;
  }
  return sdkApiVersion >= APP_ICON_API;
}

// 返回目录的副本。不交出 OPTIONS 本身：调用方拿到的是模块级常量，任何一次
// 就地排序或 splice 都会污染所有后续调用。
export function appIconOptions(): AppIconOption[] {
  return OPTIONS.slice();
}

// 图标名 → 预览图资源名。
//
// 两个调用方：设置里的选择器（画九宫格），和启动首帧（画当前这一张）。后者
// 拿到的名字来自 getAlternateIcons()——外部数据，可能是我们不认识的（比如降级
// 安装留下的旧名字）。**回落到默认那张而不是返回空**：启动那一帧空着比画错一张
// 更糟，用户会以为卡住了。
export function previewNameOf(name: string): string {
  for (let i = 0; i < OPTIONS.length; i++) {
    if (OPTIONS[i].name === name) {
      return OPTIONS[i].preview;
    }
  }
  return OPTIONS[0].preview;
}

export function isKnownIconName(name: string): boolean {
  for (let i = 0; i < OPTIONS.length; i++) {
    if (OPTIONS[i].name === name) {
      return true;
    }
  }
  return false;
}

// 当前生效的是哪一张。
//
// 系统那份列表是外部数据，不假设它自洽：同时报了两张启用时取第一张而不是抛，
// 一个界面高亮错了远好过设置页整页打不开。一张都没启用就是默认——这也是全新
// 安装和「重装后自定义图标不保留」之后的状态。
export function selectedIconName(states: IconEnabledState[]): string {
  for (let i = 0; i < states.length; i++) {
    if (states[i].enabled) {
      return states[i].name;
    }
  }
  return APP_ICON_DEFAULT;
}
