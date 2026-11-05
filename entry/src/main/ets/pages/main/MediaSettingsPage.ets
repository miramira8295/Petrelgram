import { HOLD_SPEED_LIMIT_OPTIONS, HOLD_SPEED_LIMIT_DEFAULT, normalizeHoldSpeedLimit } from '../../util/holdSpeedLimit';
import { router } from '@kit.ArkUI';
import { HdsSubDestination } from '../common/HdsSubDestination';
import { BLUR_MAX_VP, EDGE_OVERLAY_VP, edgeBlurStops } from '../../util/scrollEdgeBlur';
import {
  setBoolean, setNumber, KEY_VIDEO_AUTO_PRELOAD,
  KEY_POWER_AUTOPLAY_VIDEO, KEY_POWER_AUTOPLAY_GIF, KEY_AUTOPLAY_MUTED,
  KEY_AUTOPLAY_MAX_MB, AUTOPLAY_MAX_MB_OPTIONS, KEY_HOLD_SPEED_LIMIT,
  KEY_BG_PLAY_MUSIC, KEY_BG_PLAY_VOICE, KEY_BG_PLAY_VIDEO, KEY_BG_PLAY_LIVE
} from '../../store/AppSettings';
import {
  COLOR_DIVIDER, COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE,
  COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY, accentSoft
} from '../../util/theme';
import { str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';

const CARD_RADIUS: number = 14;

// 「媒体」设置页：长按播放速度、自动播放与后台播放。
// 路由表（router_map.json）的 buildFunction 指向这里。系统在跳转时动态加载本模块
// 并调用它，页面因此不再进 main_pages.json——一个页面不能同时是 router 页和
// NavDestination。形状与试点的 PowerUsagePageBuilder 一致。
@Builder
export function MediaSettingsPageBuilder(): void {
  MediaSettingsPage();
}

@Component
export struct MediaSettingsPage {
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  private pageScroller: Scroller = new Scroller();
  // 滚动区实测高度（vp）：linearGradientBlur 的 fractionStops 按实际高度归一化。
  @State private blurViewH: number = 0;
  @StorageProp(KEY_VIDEO_AUTO_PRELOAD) videoAutoPreload: boolean = true;
  @StorageProp(KEY_POWER_AUTOPLAY_VIDEO) autoplayVideo: boolean = true;
  @StorageProp(KEY_POWER_AUTOPLAY_GIF) autoplayGif: boolean = true;
  @StorageProp(KEY_AUTOPLAY_MUTED) autoplayMuted: boolean = true;
  @StorageProp(KEY_AUTOPLAY_MAX_MB) autoplayMaxMb: number = 0;
  @StorageProp(KEY_HOLD_SPEED_LIMIT) holdSpeedLimit: number = HOLD_SPEED_LIMIT_DEFAULT;
  @StorageProp(KEY_BG_PLAY_MUSIC) bgMusic: boolean = true;
  @StorageProp(KEY_BG_PLAY_VOICE) bgVoice: boolean = true;
  @StorageProp(KEY_BG_PLAY_VIDEO) bgVideo: boolean = false;
  @StorageProp(KEY_BG_PLAY_LIVE) bgLive: boolean = true;

  @Styles
  actionNormalStyle() {
    .backgroundColor(Color.Transparent).opacity(1).scale({ x: 1, y: 1 })
  }

  @Styles
  actionPressedStyle() {
    .backgroundColor($r('app.color.surface_alt')).opacity(0.74).scale({ x: 0.94, y: 0.94 })
  }

  @Builder
  toggleRow(title: string, subtitle: string, value: boolean, change: (next: boolean) => void) {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text(title).fontSize(15).fontColor(COLOR_TEXT_PRIMARY);
        if (subtitle !== '') {
          Text(subtitle).fontSize(11).fontColor(COLOR_TEXT_SECONDARY).maxLines(2);
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      Toggle({ type: ToggleType.Switch, isOn: value }).selectedColor(COLOR_PRIMARY)
        .onChange((next: boolean): void => change(next));
    }.width('100%').padding({ left: 14, right: 14, top: 10, bottom: 10 });
  }

  // 自动播放的视频大小上限（#226）：一排档位胶囊，选中的那档染强调色。
  @Builder
  autoplaySizeRow() {
    Column({ space: 8 }) {
      Column({ space: 2 }) {
        Text(str('ms_autoplay_limit')).fontSize(15).fontColor(COLOR_TEXT_PRIMARY);
        Text(str('ms_autoplay_limit_sub')).fontSize(11).fontColor(COLOR_TEXT_SECONDARY).maxLines(2);
      }.width('100%').alignItems(HorizontalAlign.Start);
      Row({ space: 6 }) {
        ForEach(AUTOPLAY_MAX_MB_OPTIONS, (mb: number): void => {
          Text(mb === 0 ? str('ms_cache_unlimited') : str('size_mb', `${mb}`))
            .fontSize(13)
            .fontColor(this.autoplayMaxMb === mb ? COLOR_PRIMARY : COLOR_TEXT_PRIMARY)
            .fontWeight(this.autoplayMaxMb === mb ? FontWeight.Medium : FontWeight.Normal)
            .textAlign(TextAlign.Center)
            .layoutWeight(1).height(32)
            .borderRadius(16)
            .backgroundColor(this.autoplayMaxMb === mb ? accentSoft() : $r('app.color.reaction_chip'))
            .onClick((): void => { setNumber(KEY_AUTOPLAY_MAX_MB, mb); });
        }, (mb: number): string => `${mb}`);
      }.width('100%');
    }.width('100%').padding({ left: 14, right: 14, top: 10, bottom: 12 });
  }

  @Builder
  holdSpeedCard() {
    Column({ space: 8 }) {
      Row({ space: 12 }) {
        Text(str('ms_hold_speed_limit')).fontSize(15).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
        Select(HOLD_SPEED_LIMIT_OPTIONS.map((speed: number): SelectOption => ({ value: `${speed}×` })))
          .selected(HOLD_SPEED_LIMIT_OPTIONS.indexOf(normalizeHoldSpeedLimit(this.holdSpeedLimit)))
          .value(`${normalizeHoldSpeedLimit(this.holdSpeedLimit)}×`)
          .fontColor(COLOR_PRIMARY)
          .onSelect((index: number): void => {
            const speed = HOLD_SPEED_LIMIT_OPTIONS[index];
            if (speed !== undefined) { setNumber(KEY_HOLD_SPEED_LIMIT, speed); }
          });
      }.width('100%');
      Text(str('ms_hold_speed_limit_sub')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
        .width('100%');
    }.width('100%').padding(14).backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
  }

  @Builder
  autoplayCard() {
    Column() {
      this.toggleRow(str('power_autoplay_video'), '', this.autoplayVideo,
        (next: boolean): void => setBoolean(KEY_POWER_AUTOPLAY_VIDEO, next));
      if (this.autoplayVideo) {
        Divider().strokeWidth(0.5).color(COLOR_DIVIDER).margin({ left: 14 });
        this.toggleRow(str('ms_autoplay_muted'), '', this.autoplayMuted,
          (next: boolean): void => setBoolean(KEY_AUTOPLAY_MUTED, next));
        Divider().strokeWidth(0.5).color(COLOR_DIVIDER).margin({ left: 14 });
        this.autoplaySizeRow();
      }
      Divider().strokeWidth(0.5).color(COLOR_DIVIDER).margin({ left: 14 });
      this.toggleRow(str('ms_video_auto_preload'), str('ms_video_auto_preload_sub'), this.videoAutoPreload,
        (next: boolean): void => setBoolean(KEY_VIDEO_AUTO_PRELOAD, next));
      Divider().strokeWidth(0.5).color(COLOR_DIVIDER).margin({ left: 14 });
      this.toggleRow(str('power_autoplay_gif'), '', this.autoplayGif,
        (next: boolean): void => setBoolean(KEY_POWER_AUTOPLAY_GIF, next));
    }.width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS).clip(true);
  }

  @Builder
  backgroundPlaybackCard() {
    Column() {
      this.toggleRow(str('bgplay_music'), str('bgplay_music_sub'), this.bgMusic,
        (next: boolean): void => setBoolean(KEY_BG_PLAY_MUSIC, next));
      Divider().strokeWidth(0.5).color(COLOR_DIVIDER).margin({ left: 14 });
      this.toggleRow(str('bgplay_voice'), str('bgplay_voice_sub'), this.bgVoice,
        (next: boolean): void => setBoolean(KEY_BG_PLAY_VOICE, next));
      Divider().strokeWidth(0.5).color(COLOR_DIVIDER).margin({ left: 14 });
      this.toggleRow(str('bgplay_video'), str('bgplay_video_sub'), this.bgVideo,
        (next: boolean): void => setBoolean(KEY_BG_PLAY_VIDEO, next));
      Divider().strokeWidth(0.5).color(COLOR_DIVIDER).margin({ left: 14 });
      this.toggleRow(str('bgplay_live'), str('bgplay_live_sub'), this.bgLive,
        (next: boolean): void => setBoolean(KEY_BG_PLAY_LIVE, next));
    }.width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS).clip(true);
  }

  build() {
    // 外面这层 Column 是必需的：@Entry 组件的 build 根节点必须是**容器组件**，
    // 自定义组件（HdsSubPage）不行。它不带任何样式，只是个合法的根。
    // 【迁移后】@Entry 已经摘掉，这条约束对本页不再成立；这层 Column 仍然留着，
    // 因为它不带任何样式，删不删对渲染没有区别，留着可以让 diff 只有必须的几行。
    Column() {
    HdsSubDestination({
      title: $r('app.string.settings_media'),
      pageBackground: COLOR_PAGE_BG,
      scroller: this.pageScroller
    }) {
      Scroll(this.pageScroller) {
        Column({ space: 12 }) {
          this.holdSpeedCard();
          Text(str('ms_autoplay_group')).fontSize(14).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY)
            .width('100%').padding({ left: 4, top: 4 });
          this.autoplayCard();
          Text($r('app.string.settings_background_playback')).fontSize(14).fontWeight(FontWeight.Medium)
            .fontColor(COLOR_PRIMARY).width('100%').padding({ left: 4, top: 4 });
          this.backgroundPlaybackCard();
          Text($r('app.string.bgplay_note'))
            .fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
            .width('100%').padding({ left: 14, right: 14 });
        }.width('100%').padding({ left: 12, right: 12, top: EDGE_OVERLAY_VP, bottom: this.bottomSafe + 24 });
      }
      .align(Alignment.Top)
      .width('100%').scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      // 不裁剪，内容才能穿到标题栏底下——渐变模糊模糊的正是这部分。
      .clip(false)
      // 边缘渐变虚化：与设置页/首页同一套参数（顶/底 118vp、峰 22px）。
      .linearGradientBlur(BLUR_MAX_VP, {
        fractionStops: edgeBlurStops(this.blurViewH),
        direction: GradientDirection.Bottom
      })
      .onAreaChange((_old: Area, area: Area): void => {
        const h: number = Number(area.height);
        if (h > 0 && Math.abs(h - this.blurViewH) > 0.5) {
          this.blurViewH = h;
        }
      });
    }
    }.width('100%').height('100%');
  }
}
