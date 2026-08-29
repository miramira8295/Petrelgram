import { router, promptAction } from '@kit.ArkUI';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import {
  BG_BLUR_MAX, CHAT_DIM_MAX, KEY_APP_BG_BLUR, KEY_APP_BG_DIM,
  KEY_APP_BG_STATE_DARK, KEY_APP_BG_STATE_LIGHT
} from '../../store/AppSettings';
import {
  ChatBackgroundState, emptyChatBackground, parseSnapshot, serialiseSnapshot
} from '../../store/ChatBackgroundStore';
import { appWallpaperFileName } from '../../util/localWallpaper';
import { isSplitLayout } from '../../util/splitMetrics';
import { KEY_APP_DARK } from '../../util/theme';
import {
  KEY_TEXT_SIZE, KEY_BUBBLE_RADIUS, KEY_THREE_LINES, KEY_NIGHT_MODE, KEY_REDUCE_ANIM, KEY_SEND_BY_ENTER,
  KEY_POWER_SMOOTH_TRANSITIONS, KEY_IN_APP_BROWSER,
  TEXT_SIZE_MIN, TEXT_SIZE_MAX, RADIUS_MIN, RADIUS_MAX,
  NIGHT_SYSTEM, NIGHT_DARK, NIGHT_LIGHT,
  KEY_MATERIAL_THICKNESS, KEY_MATERIAL_LIGHT,
  powerAnimationDuration, setNumber, setBoolean, setString, setNightMode
} from '../../store/AppSettings';
import {
  LIGHT_ADAPTIVE, LIGHT_DEFAULT, LIGHT_EXQUISITE, LIGHT_GENTLE, LIGHT_SMOOTH,
  THICKNESS_DEFAULT, THICKNESS_OFF, THICKNESS_REGULAR, THICKNESS_THICK, THICKNESS_THIN,
  THICKNESS_ULTRA_THICK, THICKNESS_ULTRA_THIN
} from '../../util/materialTuning';
import {
  APPEARANCE_EPOCH, KEY_MATERIAL_LIGHT_DARK, KEY_MATERIAL_THICKNESS_DARK, recomputeAppearance
} from '../../util/appearance';
import { bumpMaterialEpoch, immersiveMaterialAvailable } from '../../util/overlayMaterial';
import {
  COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_ICON_SECONDARY, COLOR_TEXT_SECONDARY, COLOR_BUBBLE_IN, COLOR_BUBBLE_OUT, bubbleTextFor
} from '../../util/theme';
import {
  AccentColorCard, AccountColorsCard, BubbleColorsCard, BubbleMaterialCard
} from './AppearanceCards';
import { str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { logE } from '../../util/log';
import { HdsSubDestination } from '../common/HdsSubDestination';
import { deviceInfo } from '@kit.BasicServicesKit';
import { appIconAvailable } from '../../util/appIcon';
import { AppIconPicker } from './AppIconPicker';

const CARD_BG: ResourceColor = $r('app.color.surface');
const CARD_RADIUS: number = 14;

interface NightOption {
  label: string;
  value: string;
}

interface MaterialThicknessOption {
  label: string;
  value: number;
}

interface MaterialLightOption {
  label: string;
  value: string;
}

// 从薄到厚，和 ImmersiveStyle 的枚举次序一致。存的是相对偏移，"标准" 是 0，
// 也就是出厂手感——见 materialTuning 里为什么不存绝对档位。
const THICKNESS_OPTIONS: MaterialThicknessOption[] = [
  { label: str('material_thickness_off'), value: THICKNESS_OFF },
  { label: str('material_thickness_ultra_thin'), value: THICKNESS_ULTRA_THIN },
  { label: str('material_thickness_thin'), value: THICKNESS_THIN },
  { label: str('material_thickness_regular'), value: THICKNESS_REGULAR },
  { label: str('material_thickness_thick'), value: THICKNESS_THICK },
  { label: str('material_thickness_ultra_thick'), value: THICKNESS_ULTRA_THICK }
];

// 从省到满，四档单调包含（单测钉着）。默认自适应。
const LIGHT_OPTIONS: MaterialLightOption[] = [
  { label: str('material_light_smooth'), value: LIGHT_SMOOTH },
  { label: str('material_light_gentle'), value: LIGHT_GENTLE },
  { label: str('material_light_adaptive'), value: LIGHT_ADAPTIVE },
  { label: str('material_light_exquisite'), value: LIGHT_EXQUISITE }
];

const NIGHT_OPTIONS: NightOption[] = [
  { label: str('night_system'), value: NIGHT_SYSTEM },
  { label: str('night_always_on'), value: NIGHT_DARK },
  { label: str('night_always_off'), value: NIGHT_LIGHT }
];

// 聊天设置. Deliberately limited to settings the app actually honours — the
// official page also offers wallpapers, colour themes and app icons, which need
// capabilities we don't have yet, and a switch that changes nothing is worse
// than no switch at all.
// 路由表（router_map.json）的 buildFunction 指向这里。系统在跳转时动态加载本模块
// 并调用它，页面因此不再进 main_pages.json——一个页面不能同时是 router 页和
// NavDestination。形状与试点的 PowerUsagePageBuilder 一致。
@Builder
export function ChatSettingsPageBuilder(): void {
  ChatSettingsPage();
}

@Component
export struct ChatSettingsPage {

  // 强调色是 theme 里的活绑定，读一次 epoch 让 ArkUI 记下依赖，用户改色后即时重绘。
  private accent(): ResourceColor {
    return this.appearanceEpoch < 0 ? Color.Transparent : COLOR_PRIMARY;
  }

  private hdsScroller: Scroller = new Scroller();
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @StorageLink(KEY_TEXT_SIZE) textSize: number = 16;
  @StorageLink(KEY_BUBBLE_RADIUS) bubbleRadius: number = 17;
  @StorageLink(KEY_THREE_LINES) threeLines: boolean = false;
  @StorageLink(KEY_NIGHT_MODE) nightMode: string = NIGHT_SYSTEM;
  @StorageLink(KEY_REDUCE_ANIM) reduceAnim: boolean = false;
  @StorageLink(KEY_SEND_BY_ENTER) sendByEnter: boolean = false;
  @StorageLink(KEY_IN_APP_BROWSER) inAppBrowser: boolean = true;
  // 厚度/光感按浅色/深色各一份，两组并列展示；当前模式那份由 overlayMaterial 自己选。
  @StorageLink(KEY_MATERIAL_THICKNESS) materialThickness: number = THICKNESS_DEFAULT;
  @StorageLink(KEY_MATERIAL_LIGHT) materialLight: string = LIGHT_DEFAULT;
  @StorageLink(KEY_MATERIAL_THICKNESS_DARK) materialThicknessDark: number = THICKNESS_DEFAULT;
  // 气泡色/文字色是 theme 里的活绑定，不是状态；预览读一次 epoch 让 ArkUI 记下依赖。
  @StorageProp(APPEARANCE_EPOCH) appearanceEpoch: number = 0;
  @StorageLink(KEY_MATERIAL_LIGHT_DARK) materialLightDark: string = LIGHT_DEFAULT;
  // 迁移前这里还有 leavingPage/leaveTimer 两个字段、一个 aboutToDisappear 清理，
  // 和一个 leavePage()：500ms 防抖 + router.back()，防的是连点两下返回箭头弹掉
  // 两页。三者随迁移一起失效，理由与试点 PowerUsagePage 逐字相同：
  //   · router.back() 在 NavDestination 上是**错的**——它弹的是 router 页栈，
  //     而本页已不在那条栈上，弹掉的会是 Index，现象是直接退到桌面
  //     （HdsSubDestination 文件头记了同一条实测）。返回改由外壳默认的出栈
  //     （NavPathStack.pop）承担，不再需要本页自己写，onBack 也随之不用传。
  //   · 防抖随之无对象：设置栈的推入走 decidePush 的 clearAndPush，栈深恒为 1，
  //     连点两下的第二次 pop() 落在空栈上是 no-op。
  //   · leavingPage 全文件没有任何渲染读取（不像 AccountEditPage 那个同名字段
  //     驱动 .enabled()），删掉不影响任何 UI。
  // 注意本页的 router import **要留着**：底下「聊天背景」那一项还在 router.pushUrl
  // 到 ChatBackgroundPage——那个页面这一轮没迁，仍是 router 页，从 NavDestination
  // 往 router 页跳是可以的（整页盖上来），反过来才不行。
  // 【将来要注意】哪天设置子页开始互相跳转、栈深可能大于 1 时，防抖要按
  // NavPathStack 重新加回来。

  private numberValue(key: string): number {
    return key === KEY_TEXT_SIZE ? this.textSize : this.bubbleRadius;
  }

  // 每个开关都要在这里挂号。toggleRow 只拿到 key，读值只能靠这张表——
  // 漏一个不会报错，而是**静默读到兜底那一项**：新开关会显示别人的状态，
  // 点它又按别人的值取反写自己。inAppBrowser 就这么错过一次。
  private booleanValue(key: string): boolean {
    if (key === KEY_REDUCE_ANIM) { return this.reduceAnim; }
    if (key === KEY_IN_APP_BROWSER) { return this.inAppBrowser; }
    return this.sendByEnter;
  }

  @Styles
  actionNormalStyle() {
    .backgroundColor(Color.Transparent)
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  actionPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.72)
    .scale({ x: 0.92, y: 0.92 })
  }

  @Styles
  optionNormalStyle() {
    .backgroundColor(Color.Transparent)
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  optionPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.75)
    .scale({ x: 0.98, y: 0.98 })
  }

  @Builder
  cardTitle(text: ResourceStr) {
    Text(text).fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.accent())
      .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 4 });
  }

  // Live sample of what the sliders above do — same colours, size and radius as
  // a real bubble.
  @Builder
  preview() {
    Column({ space: 8 }) {
      Row() {
        Text($r('app.string.chat_settings_preview_in'))
          .fontSize(this.textSize).fontColor(this.previewText(false))
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor(this.previewBubble(false))
          .borderRadius(this.bubbleRadius);
      }.width('100%').justifyContent(FlexAlign.Start);
      Row() {
        Text($r('app.string.chat_settings_preview_out'))
          .fontSize(this.textSize).fontColor(this.previewText(true))
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor(this.previewBubble(true))
          .borderRadius(this.bubbleRadius);
      }.width('100%').justifyContent(FlexAlign.End);
    }
    .width('100%').padding(14);
  }

  private previewBubble(outgoing: boolean): ResourceColor {
    if (this.appearanceEpoch < 0) {
      return Color.Transparent;
    }
    return outgoing ? COLOR_BUBBLE_OUT : COLOR_BUBBLE_IN;
  }

  private previewText(outgoing: boolean): ResourceColor {
    return this.appearanceEpoch < 0 ? Color.Transparent : bubbleTextFor(outgoing);
  }

  @Builder
  sliderRow(title: string, key: string, min: number, max: number) {
    Column() {
      this.cardTitle(title);
      Row({ space: 12 }) {
        Slider({ value: this.numberValue(key), min: min, max: max, step: 1 })
          .layoutWeight(1)
          .trackColor($r('app.color.divider')).selectedColor(this.accent()).blockColor(this.accent())
          .onChange((value: number): void => { setNumber(key, Math.round(value)); });
        Text(`${this.numberValue(key)}`)
          .fontSize(15).fontColor(this.accent()).width(28).textAlign(TextAlign.End);
      }.width('100%').padding({ left: 16, right: 16, bottom: 6 });
    }.width('100%');
  }

  @Builder
  toggleRow(title: string, subtitle: string, key: string) {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(title).fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
        if (subtitle !== '') {
          Text(subtitle).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
        }
      }
      .height(52)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .borderRadius(10)
      .stateStyles({
        normal: this.optionNormalStyle,
        pressed: this.optionPressedStyle
      })
      .accessibilityText(str('a11y_toggle_state', title, this.booleanValue(key) ? str('state_on') : str('state_off')))
      .onClick((): void => { setBoolean(key, !this.booleanValue(key)); });
      Toggle({ type: ToggleType.Switch, isOn: this.booleanValue(key) })
        .selectedColor(this.accent())
        .onChange((value: boolean): void => { setBoolean(key, value); });
    }
    .width('100%').height(64).padding({ left: 16, right: 13 })
    .alignItems(VerticalAlign.Center);
  }

  // Chat-list row density: two lines (name + preview) or three (adds a second
  // preview line).
  @Builder
  chatListView() {
    Column() {
      this.cardTitle($r('app.string.chat_settings_list_view'));
      Row({ space: 12 }) {
        this.densityOption(str('chat_settings_two_lines'), false);
        this.densityOption(str('chat_settings_three_lines'), true);
      }.width('100%').padding({ left: 16, right: 16, top: 4, bottom: 12 });
    }.width('100%');
  }

  @Builder
  densityOption(label: string, isThree: boolean) {
    Column({ space: 8 }) {
      Column({ space: 5 }) {
        Row({ space: 8 }) {
          Circle({ width: 22, height: 22 }).fill($r('app.color.divider'));
          Column({ space: 3 }) {
            Row().width('70%').height(4).borderRadius(2).backgroundColor($r('app.color.divider'));
            Row().width('90%').height(4).borderRadius(2).backgroundColor($r('app.color.divider'));
            if (isThree) {
              Row().width('80%').height(4).borderRadius(2).backgroundColor($r('app.color.divider'));
            }
          }.alignItems(HorizontalAlign.Start).layoutWeight(1);
        }.width('100%').alignItems(VerticalAlign.Center);
      }
      .width('100%').padding(10)
      .borderRadius(10)
      .border({ width: this.threeLines === isThree ? 2 : 1,
        color: this.threeLines === isThree ? this.accent() : $r('app.color.divider') })
      .backgroundColor(this.threeLines === isThree ? $r('app.color.surface_alt') : Color.Transparent)
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 160),
        curve: Curve.EaseOut
      });
      Text(label).fontSize(13)
        .fontColor(this.threeLines === isThree ? this.accent() : COLOR_TEXT_SECONDARY);
    }
    .layoutWeight(1)
    .borderRadius(12)
    .stateStyles({
      normal: this.optionNormalStyle,
      pressed: this.optionPressedStyle
    })
    .accessibilityText(str('a11y_chat_list_view', label, this.threeLines === isThree ? str('a11y_selected') : ''))
    .onClick((): void => {
      if (this.threeLines !== isThree) {
        setBoolean(KEY_THREE_LINES, isThree);
      }
    });
  }

  // 浮层材质厚度。降级路径（低于 API 26）上它驱动自绘玻璃的高斯模糊半径，
  // 所以这一档在任何设备上都有效果，永远显示。
  @Builder
  materialThicknessCard() {
    Column() {
      this.cardTitle($r('app.string.chat_settings_material_thickness'));
      Text($r('app.string.chat_settings_material_thickness_sub'))
        .fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
        .width('100%').padding({ left: 16, right: 16, bottom: 4 });
      this.thicknessSelectRow(false);
      Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16 });
      this.thicknessSelectRow(true);
    }.width('100%');
  }

  private thicknessOf(forDark: boolean): number {
    return forDark ? this.materialThicknessDark : this.materialThickness;
  }

  private lightOf(forDark: boolean): string {
    return forDark ? this.materialLightDark : this.materialLight;
  }

  private thicknessIndex(forDark: boolean): number {
    const idx = THICKNESS_OPTIONS.findIndex((o: MaterialThicknessOption): boolean => o.value === this.thicknessOf(forDark));
    return idx < 0 ? 0 : idx;
  }

  private lightIndex(forDark: boolean): number {
    const idx = LIGHT_OPTIONS.findIndex((o: MaterialLightOption): boolean => o.value === this.lightOf(forDark));
    return idx < 0 ? 0 : idx;
  }

  // 一行一个模式：左边「浅色模式 / 深色模式」，右边下拉选档。
  @Builder
  thicknessSelectRow(forDark: boolean) {
    Row({ space: 12 }) {
      Text(forDark ? $r('app.string.appearance_mode_dark') : $r('app.string.appearance_mode_light'))
        .fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
      Select(THICKNESS_OPTIONS.map((o: MaterialThicknessOption): SelectOption => ({ value: o.label } as SelectOption)))
        .selected(this.thicknessIndex(forDark))
        .value(THICKNESS_OPTIONS[this.thicknessIndex(forDark)].label)
        .font({ size: 15 }).fontColor(this.accent())
        .onSelect((index: number): void => {
          const v = THICKNESS_OPTIONS[index].value;
          if (this.thicknessOf(forDark) !== v) {
            setNumber(forDark ? KEY_MATERIAL_THICKNESS_DARK : KEY_MATERIAL_THICKNESS, v);
            bumpMaterialEpoch();
            recomputeAppearance();
          }
        });
    }
    .width('100%').height(52).padding({ left: 16, right: 8 }).alignItems(VerticalAlign.Center);
  }

  // 光感等级。lightEffect / interactive 是 ImmersiveOptions 的字段，没有材质
  // 就没有它们——低于 API 26 时整张卡片不显示。挂个调了没反应的开关比没有更糟。
  @Builder
  materialLightCard() {
    Column() {
      this.cardTitle($r('app.string.chat_settings_material_light'));
      Text($r('app.string.chat_settings_material_light_sub'))
        .fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
        .width('100%').padding({ left: 16, right: 16, bottom: 4 });
      this.lightSelectRow(false);
      Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16 });
      this.lightSelectRow(true);
    }.width('100%');
  }

  @Builder
  lightSelectRow(forDark: boolean) {
    Row({ space: 12 }) {
      Text(forDark ? $r('app.string.appearance_mode_dark') : $r('app.string.appearance_mode_light'))
        .fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
      Select(LIGHT_OPTIONS.map((o: MaterialLightOption): SelectOption => ({ value: o.label } as SelectOption)))
        .selected(this.lightIndex(forDark))
        .value(LIGHT_OPTIONS[this.lightIndex(forDark)].label)
        .font({ size: 15 }).fontColor(this.accent())
        .onSelect((index: number): void => {
          const v = LIGHT_OPTIONS[index].value;
          if (this.lightOf(forDark) !== v) {
            setString(forDark ? KEY_MATERIAL_LIGHT_DARK : KEY_MATERIAL_LIGHT, v);
            bumpMaterialEpoch();
            recomputeAppearance();
          }
        });
    }
    .width('100%').height(52).padding({ left: 16, right: 8 }).alignItems(VerticalAlign.Center);
  }

  @Builder
  nightModeCard() {
    Column() {
      this.cardTitle($r('app.string.chat_settings_night_mode'));
      ForEach(NIGHT_OPTIONS, (opt: NightOption, idx: number) => {
        if (idx > 0) {
          Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16 });
        }
        Row() {
          Text(opt.label).fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
          if (this.nightMode === opt.value) {
            SymbolGlyph($r('sys.symbol.checkmark')).fontSize(18).fontColor([this.accent()]);
          }
        }
        .width('100%').height(48).padding({ left: 16, right: 16 })
        .stateStyles({
          normal: this.optionNormalStyle,
          pressed: this.optionPressedStyle
        })
        .accessibilityText(str('a11y_option_state', opt.label, this.nightMode === opt.value ? str('a11y_selected') : ''))
        .onClick((): void => {
          if (this.nightMode !== opt.value) {
            setNightMode(opt.value);
          }
        });
      }, (opt: NightOption) => opt.value);
    }.width('100%');
  }

  @StorageProp('screenWidthVp') private appBgScreenW: number = 360;
  @StorageProp('screenHeightVp') private appBgScreenH: number = 780;
  @StorageProp(KEY_APP_DARK) private appDark: boolean = false;
  @StorageProp(KEY_APP_BG_STATE_LIGHT) private appBgLight: string = '';
  @StorageProp(KEY_APP_BG_STATE_DARK) private appBgDark: string = '';
  private pickingAppBg: boolean = false;

  private appBgSplit(): boolean {
    return isSplitLayout(this.appBgScreenW, this.appBgScreenH);
  }

  private appBgKey(): string {
    return this.appDark ? KEY_APP_BG_STATE_DARK : KEY_APP_BG_STATE_LIGHT;
  }

  private appBgRaw(): string {
    return this.appDark ? this.appBgDark : this.appBgLight;
  }

  // 当前 APP 壁纸的本机图片路径（'' = 没设，或设的是原生壁纸而非本机图）。
  // 只用来在换图/移除时把旧文件删掉——原生壁纸没有本机文件，自然什么都不用删。
  private appBgPath(): string {
    const state: ChatBackgroundState | null = parseSnapshot(this.appBgRaw());
    return state !== null ? state.path : '';
  }

  private pickAppBg(): void {
    if (this.pickingAppBg) {
      return;
    }
    this.pickingAppBg = true;
    const picker = new photoAccessHelper.PhotoViewPicker();
    const opts = new photoAccessHelper.PhotoSelectOptions();
    opts.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    opts.maxSelectNumber = 1;
    picker.select(opts).then((res: photoAccessHelper.PhotoSelectResult): void => {
      this.pickingAppBg = false;
      if (res.photoUris.length === 0) {
        return;
      }
      this.installAppBg(res.photoUris[0]);
    }).catch((): void => { this.pickingAppBg = false; });
  }

  private installAppBg(uri: string): void {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      // 文件名带时间戳，理由同聊天壁纸：固定名会被 Image 的解码缓存卡住。
      const dest: string = `${ctx.filesDir}/${appWallpaperFileName(this.appDark, Date.now())}`;
      const src = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      fs.copyFileSync(src.fd, dest);
      fs.closeSync(src);
      const previous: string = this.appBgPath();
      // 存成序列化的 ChatBackgroundState，而不是裸路径：APP 槽位和聊天槽位共用
      // 同一种数据，原生壁纸因此也能给 APP 背景用（见 pages/common/AppBackdrop）。
      // blurred 恒为 true——对整图而言这一位的含义就是"模糊滑杆对它生效"，而本机
      // 自选的图没有"自己的属性"，见 ChatBackgroundStore 里同一处说明。
      const state: ChatBackgroundState = emptyChatBackground();
      state.custom = true;
      state.path = dest;
      state.blurred = true;
      setString(this.appBgKey(), serialiseSnapshot(state));
      this.removeAppBgFile(previous);
      promptAction.showToast({ message: $r('app.string.cb_local_applied'), duration: 1500 });
    } catch (error) {
      logE(`ChatSettings installAppBg failed: ${error}`);
      promptAction.showToast({ message: $r('app.string.cb_local_failed'), duration: 1800 });
    }
  }

  private clearAppBg(): void {
    const previous: string = this.appBgPath();
    setString(this.appBgKey(), '');
    this.removeAppBgFile(previous);
  }

  // 删旧图。删不掉不该打断流程——壁纸已经换好了，沙箱里残留一个文件不影响任何事。
  private removeAppBgFile(path: string): void {
    if (path === '') {
      return;
    }
    try {
      fs.unlinkSync(path);
    } catch (error) {
      logE(`ChatSettings removeAppBgFile failed: ${error}`);
    }
  }

  build() {
    Column() {
      HdsSubDestination({ title: $r('app.string.settings_chat'), scroller: this.hdsScroller }) {
      Scroll(this.hdsScroller) {
        Column({ space: 14 }) {
          // 字号 + 圆角, with the preview they drive.
          Column() {
            this.sliderRow(str('chat_settings_text_size'), KEY_TEXT_SIZE, TEXT_SIZE_MIN, TEXT_SIZE_MAX);
            this.preview();
            Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16, right: 16 });
            this.sliderRow(str('chat_settings_corner'), KEY_BUBBLE_RADIUS, RADIUS_MIN, RADIUS_MAX);
          }
          .width('100%').backgroundColor(CARD_BG).borderRadius(CARD_RADIUS);

          // 气泡颜色紧贴预览——上面那两个气泡就是它的效果。
          BubbleColorsCard();

          Row({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.picture')).fontSize(20).fontColor([this.accent()]);
            Text($r('app.string.chat_settings_background')).fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
            SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16)
              .fontColor([COLOR_ICON_SECONDARY]);
          }
          .width('100%').height(52).padding({ left: 16, right: 12 })
          .backgroundColor(CARD_BG).borderRadius(CARD_RADIUS)
          .onClick((): void => {
            router.pushUrl({ url: 'pages/main/ChatBackgroundPage' })
              .catch((error: Error): void => {
                logE(`ChatSettings open background failed: ${error.message}`);
              });
          });

          // APP 背景图（主界面壁纸）。**分栏下整段不渲染**：右栏被聊天壁纸盖住，
          // 这张图只能从左栏那条窄缝里露出来，给一个看不出效果的开关不如不给
          // （用户："pad 没有这个选项"）。判据同 AppBackdrop 用的那一个。
          if (!this.appBgSplit()) {
            Column() {
              Row({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.picture')).fontSize(20).fontColor([this.accent()]);
                Text($r('app.string.cs_app_background')).fontSize(16)
                  .fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
                Text($r('app.string.cb_pick_local')).fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
              }
              .width('100%').height(52).padding({ left: 16, right: 12 })
              .onClick((): void => { this.pickAppBg(); });
              if (this.appBgRaw() !== '') {
                Row({ space: 12 }) {
                  SymbolGlyph($r('sys.symbol.trash')).fontSize(20)
                    .fontColor([COLOR_ICON_SECONDARY]);
                  Text($r('app.string.cb_clear_local')).fontSize(16)
                    .fontColor(COLOR_TEXT_SECONDARY).layoutWeight(1);
                }
                .width('100%').height(52).padding({ left: 16, right: 12 })
                .onClick((): void => { this.clearAppBg(); });
                this.sliderRow(str('cs_app_bg_blur'), KEY_APP_BG_BLUR, 0, BG_BLUR_MAX);
                // 遮罩只在深色模式下起作用（见 AppBackdrop.maskOpacity），
                // 浅色模式下摆一根无效的滑杆只会让人以为坏了。
                if (this.appDark) {
                  this.sliderRow(str('cs_app_bg_dim'), KEY_APP_BG_DIM, 0, CHAT_DIM_MAX);
                }
              }
            }
            .width('100%').backgroundColor(CARD_BG).borderRadius(CARD_RADIUS);
          }

          AccentColorCard();

          // 桌面图标自选。整块在 API 26 以下不渲染——getAlternateIcons/
          // setAlternateIcon 是 @since 26.0.0，而本应用 compatibleSdkVersion 是
          // 6.0.0(20)，低版本上那两个函数根本不存在。判据在 util/appIcon。
          if (appIconAvailable(deviceInfo.sdkApiVersion)) {
            Column() {
              AppIconPicker();
            }.width('100%').backgroundColor(CARD_BG).borderRadius(CARD_RADIUS);
          }

          Column() {
            this.chatListView();
          }.width('100%').backgroundColor(CARD_BG).borderRadius(CARD_RADIUS);

          Column() {
            this.nightModeCard();
          }.width('100%').backgroundColor(CARD_BG).borderRadius(CARD_RADIUS).padding({ bottom: 4 });

          BubbleMaterialCard();

          Column() {
            this.materialThicknessCard();
          }.width('100%').backgroundColor(CARD_BG).borderRadius(CARD_RADIUS).padding({ bottom: 4 });

          if (immersiveMaterialAvailable()) {
            Column() {
              this.materialLightCard();
            }.width('100%').backgroundColor(CARD_BG).borderRadius(CARD_RADIUS).padding({ bottom: 4 });
          }

          Column() {
            this.toggleRow(str('chat_settings_reduce_anim'), str('chat_settings_reduce_anim_sub'), KEY_REDUCE_ANIM);
            Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16 });
            this.toggleRow(str('chat_settings_send_by_enter'), str('chat_settings_send_by_enter_sub'), KEY_SEND_BY_ENTER);
            Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16 });
            this.toggleRow(str('chat_settings_in_app_browser'),
              str('chat_settings_in_app_browser_sub'), KEY_IN_APP_BROWSER);
          }
          .width('100%').backgroundColor(CARD_BG).borderRadius(CARD_RADIUS)
          .padding({ top: 4, bottom: 4 });

          AccountColorsCard();
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: this.bottomSafe + 24 });
      }
      .layoutWeight(1).width('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      // 不裁剪，内容才能穿到标题栏底下——渐变模糊模糊的正是这部分。
      .clip(false);
    }
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.page_bg'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
  }
}
