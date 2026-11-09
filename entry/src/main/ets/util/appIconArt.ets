// 启动页与登录页画的图案，与当前桌面图标同源。
//
// 系统启动窗那一帧只能是包内静态资源（resources/base/profile/start_window.json），
// 没有任何运行时接口能按备用图标改它——所以那一帧已经退成纯底色，真正"跟着图标
// 变"的是应用内的 StartupSplash 和登录页主视觉：用户选的是哪张图标，它们就画
// 哪一张的图案。
//
// 画的都是**无背景那一层**：图标自己的底色（那张圆角方砖）不画，图案直接落在
// 页面底色上。要画成整块图标的话，底色层参见 AppScope 里对应 icon_*.json 的分层。
//
// **素材取 AppScope 里的 1024px 原图，不取 entry 的 iconprev_\*。** 那批是 192px
// 的合成预览，只够设置页的小方块，放大到启动页上会糊。
import { bundleManager } from '@kit.AbilityKit';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { logE } from './log';
import { APP_ICON_DEFAULT, IconEnabledState, appIconAvailable, selectedIconName } from './appIcon';

// 目录里的 name → 图案（无背景那一层，1024×1024 原图）。
//
// **只能写成这样一串 if**：$r() 的参数必须是编译期字面量，拼不出
// `$r('app.media.' + name)`（AppIconPicker.previewOf 是同一个理由）。加一张图标
// 时这里是第五个必改点——原来那四处见 util/appIcon.ets 开头的注释。
//
// 为什么取前景层就够：每张图标都有一份 clear 变体，那对是 bg_clear（全透明）+
// 同一张前景层，说明前景本来就设计成能单独站住，不必另做"无背景"素材。分层关系
// 逐条见 AppScope/resources/base/media/icon_*.json。
//
// 默认图标（''）是唯一的例外：2026-09-18 换新图标时整幅画面都画进了背景层
// （bg_petrel2），前景层是一张全透明图（fg_empty），取前景会得到一片空白。它的
// 透明底版本是 fg_nightflight——nightflight 那张用的正是它，画的是同一只海燕。
export function appIconArtNoBackground(name: string): Resource {
  if (name === 'frost' || name === 'frost_clear') { return $r('app.media.fg_frost'); }
  if (name === 'neon' || name === 'neon_clear') { return $r('app.media.fg_neon'); }
  if (name === 'aurora' || name === 'aurora_clear') { return $r('app.media.fg_aurora'); }
  // 这几张是同一个海燕前景换底色（classic 是 1.5.0 之前的实色底那版）。底色去掉
  // 之后图案是同一张，所以都落到 foreground。
  if (name === 'midnight' || name === 'graphite' || name === 'forest' ||
    name === 'sunset' || name === 'violet' || name === 'classic' || name === 'classic_clear') {
    return $r('app.media.foreground');
  }
  // 默认（''）、nightflight（本来就是透明底 + 同一只海燕），以及所有对不上的名字
  // ——宁可画成默认那张，也不要留一块空白。
  return $r('app.media.fg_nightflight');
}

// 第一帧就能用的名字。undefined = 现在还不知道，得异步问系统。
//
// API 26 以下没有备用图标这回事，默认那张是确定的，直接给。26 及以上要先问系统，
// 而 getAlternateIcons 是异步的——先不画图案：系统启动窗现在就是纯底色，第一帧
// 什么都不画反而与那一帧完全一致，图案随后补上不会有跳变。
//
// 返回值不能拿空串当"还不知道"：APP_ICON_DEFAULT 本身就是空串（官方约定
// setAlternateIcon('') 表示恢复默认），两者会撞在一起。
export function initialIconName(): string | undefined {
  return appIconAvailable(deviceInfo.sdkApiVersion) ? undefined : APP_ICON_DEFAULT;
}

// 问系统当前生效的是哪一张。
//
// 失败一律回落默认：启动页是用户还什么都操作不了的那一帧，这里既没法重试也没法
// 提示，让图案暂时与桌面上那张对不上，远好过留一屏空白。
export async function resolveIconName(): Promise<string> {
  if (!appIconAvailable(deviceInfo.sdkApiVersion)) {
    return APP_ICON_DEFAULT;
  }
  return bundleManager.getAlternateIcons().then((infos: Array<bundleManager.AlternateIconInfo>): string => {
    const states: IconEnabledState[] = infos.map(
      (info: bundleManager.AlternateIconInfo): IconEnabledState => {
        return { name: info.iconName, enabled: info.enabled };
      });
    return selectedIconName(states);
  }).catch((e: BusinessError): string => {
    logE(`splash getAlternateIcons failed: ${e.code} ${e.message}`);
    return APP_ICON_DEFAULT;
  });
}
