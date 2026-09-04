import { router, promptAction } from '@kit.ArkUI';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import {
  BG_BLUR_DEFAULT, BG_BLUR_MAX, BG_BLUR_MIN, BG_PATTERN_DEFAULT, BG_PATTERN_MIN,
  CHAT_DIM_MAX,
  KEY_APP_BG_STATE_DARK, KEY_APP_BG_STATE_LIGHT, KEY_LOCAL_BG_DARK, KEY_LOCAL_BG_EPOCH,
  KEY_LOCAL_BG_LIGHT
} from '../../store/AppSettings';
import {
  ChatBackgroundState, defaultChatBackgroundSnapshot, emptyChatBackground,
  localWallpaperState, parseSnapshot, serialiseSnapshot, referencedWallpaperPaths
} from '../../store/ChatBackgroundStore';
import { appWallpaperFileName, wallpaperFileStillUsed } from '../../util/localWallpaper';
import {
  SLOT_APP_DARK, SLOT_APP_LIGHT, SLOT_CHAT_DARK, SLOT_CHAT_LIGHT, WALLPAPER_SLOTS,
  slotHasDim, slotIsApp, slotIsDark, wallpaperSlotKeys
} from '../../util/wallpaperSlot';
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
  KEY_SURFACE_GLASS_LEVEL, KEY_BUBBLE_GLASS_LEVEL, KEY_SURFACE_GLASS_ON, KEY_BUBBLE_GLASS_ON,
  BUBBLE_GLASS_ON_DEFAULT, SURFACE_GLASS_LEVEL_DEFAULT,
  SURFACE_GLASS_LEVEL_VEIL,
  SURFACE_GLASS_ON_DEFAULT, bumpSurfaceGlassEpoch
} from '../../util/surfaceGlass';
import {
  COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_ICON_SECONDARY, COLOR_TEXT_SECONDARY, COLOR_BUBBLE_IN, COLOR_BUBBLE_OUT, bubbleTextFor
} from '../../util/theme';
import {
  AccentColorCard, AccountColorsCard, BubbleColorsCard
} from './AppearanceCards';
import { str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { logE } from '../../util/log';
import { HdsSubDestination } from '../common/HdsSubDestination';
import { deviceInfo } from '@kit.BasicServicesKit';
import { appIconAvailable } from '../../util/appIcon';
import { AppIconPicker } from './AppIconPicker';
import { WallpaperPreview } from './WallpaperPreview';

// 一个槽位缩略图要画的全部东西，预先算好——**色标数组的引用必须稳定**，
// 每帧新建会让 ArkUI 认为渐变变了、四行全部重画。
interface WallpaperThumb {
  has: boolean;
  background: ChatBackgroundState;
  path: string;      // 行内画的整图（图案为 ''）
  isPattern: boolean;
  angle: number;
  colors: [ResourceColor, number][];
}

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

// 全局界面模糊的档位候选：**去掉 OFF**——关不关由总开关负责，
// 档位里再放一个"关"会出现"开关开着、档位是关"的自相矛盾状态。
//
// 头一档是「薄纱」：只有那层纱、不挂模糊（见 util/surfaceGlass 的
// SURFACE_GLASS_LEVEL_VEIL）。它排第一是因为它最轻，也是打开开关后的默认档。
// 整体 / 气泡各一个下拉，**档位里含「关闭」**——不再有独立开关：一个下拉
// 就把"要不要"和"多浓"说完了，也不会出现"开关开着、档位是关"的自相矛盾。
// 顺序：关闭 → 薄纱（最轻，也是打开后的默认）→ 超薄 … 超厚。
const SURFACE_GLASS_OPTIONS: MaterialThicknessOption[] = [
  { label: str('material_thickness_off'), value: THICKNESS_OFF } as MaterialThicknessOption,
  { label: str('material_level_veil'), value: SURFACE_GLASS_LEVEL_VEIL } as MaterialThicknessOption
].concat(THICKNESS_OPTIONS.filter(
  (o: MaterialThicknessOption): boolean => o.value !== THICKNESS_OFF));

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
  // **同一个键只能有一条 @StorageLink。** 这里原来还有第二条（带 @Watch 的），
  // 两条双向绑定指向同一个键，页面重建时后初始化的那条会把自己的默认值 false
  // 写回 AppStorage，把用户刚打开的开关冲掉（实测"退出回来开关就关闭了"）。
  // @Watch 并到这一条上。
  //
  // 顶 epoch 的用途：util 里那些读开关的纯函数没有订阅，只订阅了 epoch 的读者
  // 靠它重绘。
  @Watch('onSurfaceGlassToggled') @StorageLink(KEY_SURFACE_GLASS_ON)
  surfaceGlass: boolean = SURFACE_GLASS_ON_DEFAULT;
  @Watch('onSurfaceGlassToggled') @StorageLink(KEY_BUBBLE_GLASS_ON)
  bubbleGlass: boolean = BUBBLE_GLASS_ON_DEFAULT;
  @StorageLink(KEY_SURFACE_GLASS_LEVEL) surfaceGlassLevel: number = SURFACE_GLASS_LEVEL_DEFAULT;
  @StorageLink(KEY_BUBBLE_GLASS_LEVEL) bubbleGlassLevel: number = SURFACE_GLASS_LEVEL_DEFAULT;
  // 取消警告框之后把 Select 拨回原值用的**短暂覆盖**。
  //
  // ArkUI 的 Select 在 onSelect 之后会自己保持用户点的那一项；我们没写入
  // AppStorage，绑定值就没变化，于是它一直显示新选项（用户实测「取消了弹窗，
  // 按钮不会切回去，需要刷新页面」）。回拨必须制造一次**真实的变化**：先把
  // selected 覆盖成一个不同的下标，下一帧再撤掉覆盖回到真实值。
  // -1 = 不覆盖；key 用来只影响出事的那一行，另一行不受牵连。
  // 本页是 V1 的 @Component，用 @State（@Local 只能在 @ComponentV2 里）。
  @State private glassSelOverride: number = -1;
  @State private glassSelOverrideKey: string = '';
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
  // toggleRow 的显示值与点击取反都走这里。
  //
  // **兜底不能再返回某个具体设置。** 原来最后一行是 `return this.sendByEnter`：
  // 不认识的键不报错，静默返回"回车发送"的值——新加的开关于是显示成别人的状态、
  // 点击写进去的也是别人的取反值（实测"界面模糊质感开关还是不行"，查了半天
  // 持久化，其实读写的根本不是同一个东西）。
  // 现在兜底读 AppStorage：值一定是对的。有 @StorageLink 字段的键仍然走字段，
  // 因为那条路才会在值变化时触发重绘。
  private booleanValue(key: string): boolean {
    if (key === KEY_REDUCE_ANIM) { return this.reduceAnim; }
    if (key === KEY_IN_APP_BROWSER) { return this.inAppBrowser; }
    if (key === KEY_SEND_BY_ENTER) { return this.sendByEnter; }
    if (key === KEY_SURFACE_GLASS_ON) { return this.surfaceGlass; }
    return AppStorage.get<boolean>(key) ?? false;
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
      // 界面模糊质感并在这张卡里，而不是底下另起一张无标题的卡。
      //
      // 它和上面两行是**同一件事的两个面**：厚度管"浮层有多厚"，这一项管"要不要
      // 把同一套玻璃铺到列表行/气泡这些数量巨大的节点上"。分成两张卡时下面那张
      // 没有标题，读起来像一条无关的开关（用户："不应该写在模糊质感的开关里面吗，
      // 作为一个质感引入"）。
      Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16 });
      this.surfaceGlassCard();
    }.width('100%');
  }

  // 全局界面模糊质感。总开关 + 档位，档位只在开着时才出现——关着时那一行
  // 除了制造"调了没反应"的困惑之外没有任何用。
  @Builder
  surfaceGlassCard() {
    Column() {
      this.glassSelectRow(str('chat_settings_surface_glass_ui'),
        str('chat_settings_surface_glass_ui_sub'),
        this.surfaceGlass, this.surfaceGlassLevel,
        KEY_SURFACE_GLASS_ON, KEY_SURFACE_GLASS_LEVEL);
      Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16 });
      this.glassSelectRow(str('chat_settings_bubble_glass'),
        str('chat_settings_bubble_glass_sub'),
        this.bubbleGlass, this.bubbleGlassLevel,
        KEY_BUBBLE_GLASS_ON, KEY_BUBBLE_GLASS_LEVEL);
    }.width('100%');
  }

  // 一面的档位行。**下拉是这一面的唯一写入口**：选「关闭」写 on=false，
  // 选别的写 on=true + 档位。渲染侧订阅的仍是那个布尔（ChatRow / chatEnvMirror
  // 都挂在它上面），它在这里被严格地当成"档位 !== 关闭"的缓存来维护。
  @Builder
  glassSelectRow(title: string, subtitle: string, on: boolean, level: number,
    onKey: string, levelKey: string) {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(title).fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
        Text(subtitle).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1);
      Select(SURFACE_GLASS_OPTIONS.map(
        (o: MaterialThicknessOption): SelectOption => ({ value: o.label } as SelectOption)))
        .selected(this.glassSelectedIndex(onKey, on, level))
        .value(SURFACE_GLASS_OPTIONS[this.glassSelectedIndex(onKey, on, level)].label)
        .font({ size: 15 }).fontColor(this.accent())
        .onSelect((index: number): void => {
          const v: number = SURFACE_GLASS_OPTIONS[index].value;
          if (v === THICKNESS_OFF) {
            setBoolean(onKey, false);
            bumpSurfaceGlassEpoch();
            return;
          }
          // 非「关闭」的档位一律先弹警告，确认后才生效。这不是客套：模糊每帧
          // 实时渲染，而这个开关覆盖的是全应用数量最多的那些节点（会话行、
          // 气泡）——09-03 真机 trace 里滤镜缓存命中率只有 4.6%，GPU 活跃段
          // p90 恒为 100%。用户有权在付这笔电费之前知道它。
          this.confirmGlassLevel(onKey, levelKey, v);
        });
    }
    // **右内边距必须是 8，和 thicknessSelectRow 一致**：Select 的右缘由它决定，
    // 给 16 就会比上面两行厚度的下拉往里缩 8vp，四个下拉排下来肉眼可见地错开
    // （用户实测「这几个下拉按钮文字还对不齐」）。
    // 上下用 10 而不是固定 height(52)：这两行的标题带副标题，是两行文字。
    .width('100%').padding({ left: 16, right: 8, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center);
  }

  // 弹一次耗电/发热/掉帧的确认。取消就什么都不写——`selected()` 绑的是
  // AppStorage 推出来的下标，没写入时下一次 build 会把 Select 拨回原值，
  // 不需要我们手动回滚。
  private confirmGlassLevel(onKey: string, levelKey: string, level: number): void {
    promptAction.showDialog({
      title: str('glass_warn_title'),
      message: str('glass_warn_body'),
      // color 是**必填**，且只吃 string | Resource —— 主题里的 COLOR_* 是
      // ResourceColor（可能是 Color 枚举），类型对不上，所以这里直接引资源。
      buttons: [
        { text: str('cancel'), color: $r('app.color.text_secondary') },
        { text: str('glass_warn_enable'), color: $r('app.color.primary') }
      ]
    }).then((res: promptAction.ShowDialogSuccessResponse): void => {
      if (res.index !== 1) {
        this.revertGlassSelect(onKey, this.glassOptionIndex(
          onKey === KEY_SURFACE_GLASS_ON ? this.surfaceGlass : this.bubbleGlass,
          onKey === KEY_SURFACE_GLASS_ON ? this.surfaceGlassLevel : this.bubbleGlassLevel));
        return;
      }
      setNumber(levelKey, level);
      setBoolean(onKey, true);
      bumpSurfaceGlassEpoch();
    }).catch((e: Object): void => {
      logE(`ChatSettingsPage.confirmGlassLevel failed: ${JSON.stringify(e)}`);
    });
  }

  private glassSelectedIndex(onKey: string, on: boolean, level: number): number {
    if (this.glassSelOverrideKey === onKey && this.glassSelOverride >= 0) {
      return this.glassSelOverride;
    }
    return this.glassOptionIndex(on, level);
  }

  // 先覆盖成一个**不同**的下标制造变化，下一帧撤掉覆盖落回真实值。
  // 覆盖值取"真实值以外的任意一项"：真实值是 0 就用 1，否则用 0。
  private revertGlassSelect(onKey: string, trueIndex: number): void {
    this.glassSelOverrideKey = onKey;
    this.glassSelOverride = trueIndex === 0 ? 1 : 0;
    setTimeout((): void => {
      this.glassSelOverride = -1;
      this.glassSelOverrideKey = '';
    }, 0);
  }

  // 关着时恒指向「关闭」那一项，不管底下存的档位是什么。
  private glassOptionIndex(on: boolean, level: number): number {
    if (!on) {
      return 0;
    }
    const idx: number = SURFACE_GLASS_OPTIONS.findIndex(
      (o: MaterialThicknessOption): boolean => o.value === level);
    return idx <= 0 ? 1 : idx;
  }


  private onSurfaceGlassToggled(): void {
    // **开一次 = 回到默认质感（薄纱）。**
    //
    // 「打开后默认薄纱」原来只靠 SURFACE_GLASS_LEVEL_DEFAULT 兜着，而那个默认
    // 值只在**从没存过**时生效——任何调过一次档位的用户（包括所有老用户）
    // preferences 里都躺着一个旧值，再打开开关看到的还是旧档，永远见不到默认。
    //
    // 拨开关是用户唯一明确表达"我要这个质感"的动作，把它定义成"回到默认"
    // 既解决了上面那件事，也给了一条不用清数据的复位路径：调乱了，关一下再开。
    // 想要别的档位，开着的时候再选——那次选择照旧存住，直到下次拨开关。
    // **这里不能再做"复位薄纱"**：下拉选完档位会写 on=true，@Watch 随即触发，
    // 复位就会把用户刚选的档位改回薄纱。改成下拉之后也不需要它了——"关闭"
    // 本来就是选项之一，档位不会再有"存了旧值看不到默认"那个问题。
    bumpSurfaceGlassEpoch();
  }

  private surfaceGlassLevelIndex(): number {
    const idx: number = SURFACE_GLASS_OPTIONS.findIndex(
      (o: MaterialThicknessOption): boolean => o.value === this.surfaceGlassLevel);
    return idx < 0 ? 0 : idx;
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
  @StorageProp(KEY_APP_BG_STATE_LIGHT) @Watch('rebuildSlotStates') private appBgLight: string = '';
  @StorageProp(KEY_APP_BG_STATE_DARK) @Watch('rebuildSlotStates') private appBgDark: string = '';
  // 聊天槽位换图不会动上面两个键，得盯本机壁纸的代次。本页是 router 页，从背景
  // 编辑页**弹回来不会再走 aboutToAppear**，没有这一条缩略图就一直是进来时那份。
  @StorageProp(KEY_LOCAL_BG_EPOCH) @Watch('rebuildSlotStates') private localBgEpoch: number = 0;
  private pickingAppBg: boolean = false;

  aboutToAppear(): void {
    // 四个槽位的壁纸状态算一次存下来，别在 build() 的热路径上反复解析——
    // 见 slotStates 那段说明。
    this.rebuildSlotStates();
  }
  // 非空 = 正在放大看这个槽位的壁纸。
  @State enlargedSlot: string = '';
  @State enlargedBlur: number = BG_BLUR_DEFAULT;
  @State enlargedPattern: number = BG_PATTERN_DEFAULT;
  @State enlargedDim: number = 0;

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

  // 换图/移除之后清理旧文件。**只在没有任何槽位还引用它时才删**——上传过的
  // 壁纸是共用的，同一张图可能同时给几个槽位用，无条件删会把别人的槽位弄成
  // 一个指向空路径的洞。删不掉也不该打断流程：壁纸已经换好了，残留一个文件
  // 不影响任何事。
  private removeAppBgFile(path: string): void {
    if (path === '' || wallpaperFileStillUsed(path, referencedWallpaperPaths())) {
      return;
    }
    try {
      fs.unlinkSync(path);
    } catch (error) {
      logE(`ChatSettings removeAppBgFile failed: ${error}`);
    }
  }

  // 四个槽位的缩略图规格，**算一次存下来**。
  //
  // 【第一版只缓存了状态，还是卡】那一版把 parseSnapshot 挪出了热路径，但四个取值
  // 函数每次调用仍然**新建一个渐变色标数组**——引用一变 ArkUI 就认为渐变变了，
  // 四行每帧全部重画。而且图案壁纸的文档是 .tgv 解出来的 **SVG**，在 44vp 的格子里
  // 逐帧栅格化，四张一起更顶不住。
  //
  // 现在连色标数组一起预先算好（引用稳定），并且**行内不画图案**：44vp 上一张平铺
  // 花纹本来也看不出什么，壁纸的身份由填充色承担；图案只在放大预览里画一次。
  @State private slotThumbs: Map<string, WallpaperThumb> =
    new Map<string, WallpaperThumb>();

  private rebuildSlotStates(): void {
    const next: Map<string, WallpaperThumb> = new Map<string, WallpaperThumb>();
    for (const slot of WALLPAPER_SLOTS) {
      next.set(slot, this.buildThumb(this.readSlotState(slot)));
    }
    this.slotThumbs = next;
  }

  private buildThumb(st: ChatBackgroundState | null): WallpaperThumb {
    if (st === null) {
      return { has: false, background: emptyChatBackground(), path: '', isPattern: false, angle: 180,
        colors: [[$r('app.color.surface_alt'), 0], [$r('app.color.surface_alt'), 1]] };
    }
    const cs: string[] = st.colors;
    let colors: [ResourceColor, number][];
    if (cs.length === 0) {
      colors = [[$r('app.color.surface_alt'), 0], [$r('app.color.surface_alt'), 1]];
    } else if (cs.length === 1) {
      colors = [[cs[0], 0], [cs[0], 1]];
    } else {
      const out: [ResourceColor, number][] = [];
      for (let i = 0; i < cs.length; i++) {
        out.push([cs[i], i / (cs.length - 1)]);
      }
      colors = out;
    }
    return {
      has: true,
      background: st,
      // 行内只画整图；图案留空，见上面的说明。
      path: st.isPattern ? '' : st.path,
      isPattern: st.isPattern,
      angle: st.angle,
      colors
    };
  }

  private readSlotState(slot: string): ChatBackgroundState | null {
    if (slotIsApp(slot)) {
      return parseSnapshot(AppStorage.get<string>(wallpaperSlotKeys(slot).state) ?? '');
    }
    // 聊天槽位的取值顺序必须和**真正画出来的那一套**一致，也就是
    // ChatBackgroundStore.applyDefault：本机自选壁纸 > 账号默认背景。
    //
    // 原来这里只读了后者。于是用户给「聊天浅色 / 聊天深色」传了自己的图之后，
    // 这两行的缩略图仍然是空的——账号默认背景本来就可能一片空白（真机实报：
    // "选择自己上传的壁纸，聊天浅色和深色的缩略图不展示"）。
    const local: string = AppStorage.get<string>(
      slotIsDark(slot) ? KEY_LOCAL_BG_DARK : KEY_LOCAL_BG_LIGHT) ?? '';
    if (local !== '') {
      return localWallpaperState(local);
    }
    const snap: ChatBackgroundState = defaultChatBackgroundSnapshot(slotIsDark(slot));
    return (snap.colors.length > 0 || snap.path !== '') ? snap : null;
  }

  private thumbOf(slot: string): WallpaperThumb {
    const t: WallpaperThumb | undefined = this.slotThumbs.get(slot);
    return t !== undefined ? t
      : { has: false, background: emptyChatBackground(), path: '', isPattern: false, angle: 180,
          colors: [[$r('app.color.surface_alt'), 0], [$r('app.color.surface_alt'), 1]] };
  }

  private showWallpaperPreview(slot: string): void {
    const keys = wallpaperSlotKeys(slot);
    this.enlargedBlur = AppStorage.get<number>(keys.blur) ?? BG_BLUR_DEFAULT;
    this.enlargedPattern = AppStorage.get<number>(keys.pattern) ?? BG_PATTERN_DEFAULT;
    this.enlargedDim = AppStorage.get<number>(keys.dim) ?? 0;
    this.enlargedSlot = slot;
  }

  private sliderSettled(mode: SliderChangeMode): boolean {
    return mode === SliderChangeMode.End || mode === SliderChangeMode.Click;
  }

  private setEnlargedBlur(value: number, mode: SliderChangeMode): void {
    this.enlargedBlur = Math.round(value);
    if (this.sliderSettled(mode)) {
      setNumber(wallpaperSlotKeys(this.enlargedSlot).blur, this.enlargedBlur);
    }
  }

  private setEnlargedPattern(value: number, mode: SliderChangeMode): void {
    this.enlargedPattern = Math.round(value) / 100;
    if (this.sliderSettled(mode)) {
      setNumber(wallpaperSlotKeys(this.enlargedSlot).pattern, this.enlargedPattern);
    }
  }

  private setEnlargedDim(value: number, mode: SliderChangeMode): void {
    this.enlargedDim = Math.round(value) / 100;
    if (this.sliderSettled(mode)) {
      setNumber(wallpaperSlotKeys(this.enlargedSlot).dim, this.enlargedDim);
    }
  }

  private openWallpaperSlot(slot: string): void {
    router.pushUrl({ url: 'pages/main/ChatBackgroundPage', params: { slot: slot } })
      .catch((error: Error): void => {
        logE(`ChatSettings open wallpaper slot failed: ${error.message}`);
      });
  }

  // 壁纸的画面本身。缩略图和放大浮层共用——**不用 ChatBackdrop**：那一层带栅格
  // 缓存和图案合成，为四张 44vp 的小图各起一份不值当。这里只画渐变或整图；
  // 缩略图要回答的是"这个槽位设了什么"，不需要像素级还原。
  // 行内的小缩略图。渐变打底 + 整图叠上；**图案不画**（见 slotThumbs 的说明）。
  @Builder
  wallpaperCanvas(slot: string) {
    Stack() {
      Column().width('100%').height('100%')
        .linearGradient({ angle: this.thumbOf(slot).angle, colors: this.thumbOf(slot).colors });
      if (this.thumbOf(slot).path !== '') {
        Image(`file://${this.thumbOf(slot).path}`).draggable(false)
          .width('100%').height('100%').objectFit(ImageFit.Cover);
      }
    }
    .width('100%').height('100%');
  }

  // 放大预览只有一张，可以完整画图案、模糊和深色遮罩。
  @Builder
  wallpaperCanvasLarge() {
    Stack() {
      WallpaperPreview({
        wallpaper: this.thumbOf(this.enlargedSlot).background,
        blurAmount: this.enlargedBlur,
        patternStrength: this.enlargedPattern,
        dimAmount: this.enlargedDim,
        dark: slotIsDark(this.enlargedSlot),
        previewW: Math.max(1, Math.min(520, this.appBgScreenW * 0.88)),
        previewH: Math.max(220, Math.min(420, this.appBgScreenH * 0.48))
      });
    }
    .width('100%').height('100%');
  }

  @Builder
  wallpaperSlotRow(slot: string, label: string) {
    Row({ space: 12 }) {
      Text(label).fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
      if (this.thumbOf(slot).has) {
        Stack() {
          this.wallpaperCanvas(slot);
        }
        .width(44).height(44).borderRadius(8).clip(true)
        .border({ width: 0.7, color: $r('app.color.divider') })
        // 点缩略图放大看；点整行才是进去改。两个动作分开挂，避免互相吃手势。
        .onClick((): void => { this.showWallpaperPreview(slot); });
      } else {
        Text($r('app.string.cs_wallpaper_none')).fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
      }
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16)
        .fontColor([COLOR_ICON_SECONDARY]);
    }
    .width('100%').height(60).padding({ left: 16, right: 12 })
    .onClick((): void => { this.openWallpaperSlot(slot); });
  }

  // 缩略图点开后的放大预览。原来把关闭手势挂在整层上，预览里任何交互都会先
  // 把浮层关掉；现在只保留明确的关闭按钮，三根滑杆在浮层里直接驱动同一张预览。
  @Builder
  wallpaperEnlarged() {
    Stack({ alignContent: Alignment.Center }) {
      Column().width('100%').height('100%').backgroundColor('#CC000000');
      Column({ space: 10 }) {
        Stack() {
          this.wallpaperCanvasLarge();
        }
        .width('100%').height(Math.max(220, Math.min(420, this.appBgScreenH * 0.48)))
        .borderRadius(18).clip(true);
        Column({ space: 4 }) {
          Row() {
            Text($r('app.string.cb_blur_amount')).fontSize(14).fontColor(Color.White).layoutWeight(1);
            Text(`${this.enlargedBlur}`).fontSize(13).fontColor('#BFFFFFFF');
          }.width('100%');
          Slider({
            value: this.enlargedBlur, min: BG_BLUR_MIN, max: BG_BLUR_MAX,
            step: 1, style: SliderStyle.OutSet
          })
            .width('100%').trackColor('#4DFFFFFF').selectedColor(COLOR_PRIMARY)
            .blockColor(COLOR_PRIMARY)
            .onChange((value: number, mode: SliderChangeMode): void => {
              this.setEnlargedBlur(value, mode);
            });
        }.width('100%');
        if (this.thumbOf(this.enlargedSlot).isPattern) {
          Column({ space: 4 }) {
            Row() {
              Text($r('app.string.cb_pattern_strength')).fontSize(14).fontColor(Color.White).layoutWeight(1);
              Text(`${Math.round(this.enlargedPattern * 100)}%`).fontSize(13).fontColor('#BFFFFFFF');
            }.width('100%');
            Slider({
              value: Math.round(this.enlargedPattern * 100),
              min: Math.round(BG_PATTERN_MIN * 100), max: 100,
              step: 5, style: SliderStyle.OutSet
            })
              .width('100%').trackColor('#4DFFFFFF').selectedColor(COLOR_PRIMARY)
              .blockColor(COLOR_PRIMARY)
              .onChange((value: number, mode: SliderChangeMode): void => {
                this.setEnlargedPattern(value, mode);
              });
          }.width('100%');
        }
        if (slotHasDim(this.enlargedSlot)) {
          Column({ space: 4 }) {
            Row() {
              Text($r('app.string.chat_settings_dark_dim')).fontSize(14).fontColor(Color.White).layoutWeight(1);
              Text(`${Math.round(this.enlargedDim * 100)}%`).fontSize(13).fontColor('#BFFFFFFF');
            }.width('100%');
            Slider({
              value: Math.round(this.enlargedDim * 100), min: 0,
              max: Math.round(CHAT_DIM_MAX * 100), step: 5, style: SliderStyle.OutSet
            })
              .width('100%').trackColor('#4DFFFFFF').selectedColor(COLOR_PRIMARY)
              .blockColor(COLOR_PRIMARY)
              .onChange((value: number, mode: SliderChangeMode): void => {
                this.setEnlargedDim(value, mode);
              });
          }.width('100%');
        }
      }
      .width('88%').constraintSize({ maxWidth: 520 })
      .padding({ left: 14, right: 14, top: 14, bottom: 14 })
      .borderRadius(20).backgroundColor('#E61B1B1B');
      Button() {
        SymbolGlyph($r('sys.symbol.xmark')).fontSize(19).fontColor([Color.White]);
      }
      .width(40).height(40).borderRadius(20).backgroundColor('#66000000')
      .position({ right: 18, top: this.topSafe + 12 })
      .onClick((): void => { this.enlargedSlot = ''; });
    }
    .width('100%').height('100%');
  }

  build() {
    // 放大预览要盖住整页（含标题栏），所以在最外面再包一层 Stack。
    Stack() {
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

          // ── 壁纸设置：四个独立槽位 ──────────────────────────────────────
          // APP 浅色 / APP 深色 / 聊天浅色 / 聊天深色，各有自己的壁纸和三根滑杆。
          // 右侧是该槽位当前壁纸的缩略图，点它放大看，点整行进去改。
          // 分栏下不显示 APP 那两行（用户："pad 没有这个选项"）。
          Column() {
            this.cardTitle(str('cs_wallpaper_settings'));
            if (!this.appBgSplit()) {
              this.wallpaperSlotRow(SLOT_APP_LIGHT, str('cs_slot_app_light'));
              this.wallpaperSlotRow(SLOT_APP_DARK, str('cs_slot_app_dark'));
            }
            this.wallpaperSlotRow(SLOT_CHAT_LIGHT, str('cs_slot_chat_light'));
            this.wallpaperSlotRow(SLOT_CHAT_DARK, str('cs_slot_chat_dark'));
          }
          .width('100%').backgroundColor(CARD_BG).borderRadius(CARD_RADIUS);

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
    if (this.enlargedSlot !== '') {
      this.wallpaperEnlarged();
    }
    }
    .width('100%').height('100%');
  }
}
