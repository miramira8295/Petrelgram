import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { getAccentColorStore, getTdClient } from '../../tdkit/Globals';
import { AccentPalettes } from '../../store/AccentColorStore';
import { TdError, TdObject, TdRequest } from '../../tdkit/TdTypes';
import {
  AccentPreview, accentPreviewOf, profileAccentPreviewOf
} from '../../util/accentPresentation';
import {
  COLOR_BUBBLE_IN, COLOR_BUBBLE_OUT, COLOR_CHAT_BG, COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE,
  COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY, KEY_APP_DARK, bubbleTextFor, darkResourceMode
} from '../../util/theme';
import {
  APPEARANCE_EPOCH, BUBBLE_HEX_KEYS, KEY_ACCENT_CUSTOM_ON, KEY_ACCENT_HEX, KEY_ACCENT_HEX_DARK,
  KEY_BUBBLE_IN_HEX, KEY_BUBBLE_IN_HEX_DARK, KEY_BUBBLE_MATERIAL_ON, KEY_BUBBLE_OUT_HEX,
  KEY_BUBBLE_OUT_HEX_DARK, defaultHexFor, hexOrDefault, recomputeAppearance
} from '../../util/appearance';
import { setBoolean, setString } from '../../store/AppSettings';
import { bumpMaterialEpoch, immersiveMaterialAvailable } from '../../util/overlayMaterial';
import { ColorPickerSheet } from '../common/ColorPickerSheet';
import { str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { logE } from '../../util/log';
import { HdsSubDestination } from '../common/HdsSubDestination';

const CARD_RADIUS: number = 14;
const SWATCH: number = 44;

// 「外观」：上半是本机设置（应用强调色、气泡颜色、气泡材质），下半是账号颜色
// （名字色、资料页色，发到服务端、别人看的）。原 AccentColorPage 的两块色板搬到
// 这里，页面只剩一个入口，「强调色」和「名字颜色」从此分开。
//
// 路由表（router_map.json）的 buildFunction 指向这里。系统在跳转时动态加载本模块
// 并调用它，页面因此不再进 main_pages.json——一个页面不能同时是 router 页和
// NavDestination。
@Builder
export function AppearancePageBuilder(): void {
  AppearancePage();
}

@Component
export struct AppearancePage {
  private hdsScroller: Scroller = new Scroller();
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State namePreviews: AccentPreview[] = [];
  @State profilePreviews: AccentPreview[] = [];
  @State currentNameId: number = -1;
  @State currentProfileId: number = -1;
  @State busy: boolean = false;
  @State myName: string = '';
  // 本机外观设置。六个 hex 键各自订阅，色块才会在取色器写入后立刻更新。
  @StorageProp(APPEARANCE_EPOCH) epoch: number = 0;
  @StorageProp(KEY_APP_DARK) isDark: boolean = false;
  @StorageProp(KEY_ACCENT_CUSTOM_ON) accentOn: boolean = false;
  @StorageProp(KEY_BUBBLE_MATERIAL_ON) bubbleMaterialOn: boolean = false;
  @StorageProp(KEY_ACCENT_HEX) accentHexLight: string = '';
  @StorageProp(KEY_ACCENT_HEX_DARK) accentHexDark: string = '';
  @StorageProp(KEY_BUBBLE_OUT_HEX) bubbleOutLight: string = '';
  @StorageProp(KEY_BUBBLE_OUT_HEX_DARK) bubbleOutDark: string = '';
  @StorageProp(KEY_BUBBLE_IN_HEX) bubbleInLight: string = '';
  @StorageProp(KEY_BUBBLE_IN_HEX_DARK) bubbleInDark: string = '';
  @State pickerOpen: boolean = false;
  @State pickerKey: string = '';
  private off: (() => void) | null = null;
  private active: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    const dark = darkResourceMode(getContext(this) as common.UIAbilityContext);
    this.off = getAccentColorStore().subscribe((palettes: AccentPalettes): void => {
      this.namePreviews = this.orderPreviews(
        palettes.nameColors.map((c: TdObject): AccentPreview | null => accentPreviewOf(c, dark)),
        palettes.nameIds
      );
      this.profilePreviews = this.orderPreviews(
        palettes.profileColors.map(
          (c: TdObject): AccentPreview | null => profileAccentPreviewOf(c, dark)),
        palettes.profileIds
      );
    });
    this.refreshSelection();
  }

  aboutToDisappear(): void {
    this.active = false;
    if (this.off !== null) {
      this.off();
      this.off = null;
    }
  }

  // available_accent_color_ids defines the server's display order and may
  // reference built-in ids that have no palette entry of their own.
  private orderPreviews(
    mapped: (AccentPreview | null)[], availableIds: number[]
  ): AccentPreview[] {
    const byId = new Map<number, AccentPreview>();
    for (const preview of mapped) {
      if (preview !== null) { byId.set(preview.id, preview); }
    }
    const rows: AccentPreview[] = [];
    for (const id of availableIds) {
      const known = byId.get(id);
      if (known !== undefined) {
        rows.push(known);
      } else {
        const builtin = accentPreviewOf(
          { '@type': 'accentColor', 'id': id, 'built_in_accent_color_id': id } as TdObject, false
        );
        if (builtin !== null) { rows.push(builtin); }
      }
    }
    return rows;
  }

  private refreshSelection(): void {
    getAccentColorStore().currentSelection().then((ids: [number, number]): void => {
      if (!this.active) { return; }
      this.currentNameId = ids[0];
      this.currentProfileId = ids[1];
    }).catch((error: TdError): void => {
      logE(`AppearancePage.selection failed: ${error.message}`);
    });
    getTdClient().send({ '@type': 'getMe' } as TdRequest).then((me: TdObject): void => {
      if (!this.active) { return; }
      const first = (me['first_name'] as string | undefined) ?? '';
      const last = (me['last_name'] as string | undefined) ?? '';
      this.myName = `${first} ${last}`.trim();
    }).catch((): void => {});
  }

  // Live preview: your own message color is what OTHERS see in groups — your
  // outgoing bubbles never carry a name, so the page shows it here instead.
  private previewNameColor(): string {
    const hex = getAccentColorStore().nameColorHex(
      this.currentNameId, darkResourceMode(getContext(this) as common.UIAbilityContext));
    return hex !== '' ? hex : '#3390EC';
  }

  private errorText(error: TdError): string {
    return error.message.indexOf('PREMIUM') >= 0 || error.message.indexOf('premium') >= 0
      ? str('accent_needs_premium') : str('apply_failed_retry');
  }

  private applyName(id: number): void {
    if (this.busy) { return; }
    this.busy = true;
    getAccentColorStore().setNameAccentColor(id).then((): void => {
      if (!this.active) { return; }
      this.busy = false;
      this.currentNameId = id;
      promptAction.showToast({ message: $r('app.string.accent_name_updated'), duration: 1500 });
    }).catch((error: TdError): void => {
      if (!this.active) { return; }
      this.busy = false;
      promptAction.showToast({ message: this.errorText(error), duration: 1800 });
    });
  }

  private applyProfile(id: number): void {
    if (this.busy) { return; }
    this.busy = true;
    getAccentColorStore().setProfileAccentColor(id).then((): void => {
      if (!this.active) { return; }
      this.busy = false;
      this.currentProfileId = id;
      promptAction.showToast({
        message: $r('app.string.accent_profile_updated'), duration: 2200
      });
    }).catch((error: TdError): void => {
      if (!this.active) { return; }
      this.busy = false;
      promptAction.showToast({ message: this.errorText(error), duration: 1800 });
    });
  }

  private isSelected(preview: AccentPreview, forProfile: boolean): boolean {
    return (forProfile ? this.currentProfileId : this.currentNameId) === preview.id;
  }

  // Selection is read from @State INSIDE the builder: @Builder value params
  // are frozen at call time and would never show the asynchronously fetched
  // current color.
  @Builder
  swatch(preview: AccentPreview, forProfile: boolean, onTap: () => void) {
    Stack({ alignContent: Alignment.Center }) {
      if (preview.colors.length > 1) {
        Column().width(SWATCH).height(SWATCH).borderRadius(SWATCH / 2)
          .linearGradient({
            angle: 135,
            colors: preview.colors.map((color: string, index: number): [string, number] =>
              [color, index / (preview.colors.length - 1)])
          });
      } else {
        Column().width(SWATCH).height(SWATCH).borderRadius(SWATCH / 2)
          .backgroundColor(preview.colors.length === 1 ? preview.colors[0] : COLOR_SURFACE);
      }
      if (this.isSelected(preview, forProfile)) {
        SymbolGlyph($r('sys.symbol.checkmark')).fontSize(18).fontColor([Color.White]);
      }
    }
    .width(SWATCH + 8).height(SWATCH + 8)
    .borderRadius((SWATCH + 8) / 2)
    .border({
      width: this.isSelected(preview, forProfile) ? 2 : 0,
      color: COLOR_PRIMARY
    })
    .onClick(onTap);
  }

  private pickerInitial(): string {
    return hexOrDefault(AppStorage.get<string>(this.pickerKey), defaultHexFor(this.pickerKey));
  }

  private openPicker(key: string): void {
    this.pickerKey = key;
    this.pickerOpen = true;
  }

  private resetBubbles(): void {
    for (const key of BUBBLE_HEX_KEYS) {
      setString(key, '');
    }
    recomputeAppearance();
  }

  // 预览读 this.epoch 只是为了让 ArkUI 记下依赖：theme 里的活绑定本身不是状态。
  private previewOut(): ResourceColor {
    return this.epoch < 0 ? Color.Transparent : COLOR_BUBBLE_OUT;
  }

  private previewIn(): ResourceColor {
    return this.epoch < 0 ? Color.Transparent : COLOR_BUBBLE_IN;
  }

  private previewPrimary(): ResourceColor {
    return this.epoch < 0 ? Color.Transparent : COLOR_PRIMARY;
  }

  @Builder
  pickerSheet() {
    ColorPickerSheet({
      initialHex: this.pickerInitial(),
      onPick: (hex: string): void => {
        setString(this.pickerKey, hex);
        recomputeAppearance();
      },
      onClose: (): void => {
        this.pickerOpen = false;
      }
    })
  }

  @Builder
  colorCell(value: string, key: string, label: ResourceStr) {
    Column({ space: 4 }) {
      Column().width(40).height(40).borderRadius(10)
        .backgroundColor(hexOrDefault(value, defaultHexFor(key)))
        .border({ width: 1, color: '#22000000' })
        .onClick((): void => this.openPicker(key));
      Text(label).fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
    }.alignItems(HorizontalAlign.Center);
  }

  @Builder
  switchRow(title: ResourceStr, isOn: boolean, onChange: (v: boolean) => void) {
    Row() {
      Text(title).fontSize(15).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .selectedColor(COLOR_PRIMARY)
        .onChange((v: boolean): void => onChange(v));
    }.width('100%').alignItems(VerticalAlign.Center);
  }

  @Builder
  preview() {
    Column({ space: 8 }) {
      Row() {
        Text($r('app.string.appearance_preview_in')).fontSize(14).fontColor(bubbleTextFor(false))
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor(this.previewIn()).borderRadius(14);
      }.width('100%').justifyContent(FlexAlign.Start);
      Row() {
        Text($r('app.string.appearance_preview_out')).fontSize(14).fontColor(bubbleTextFor(true))
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor(this.previewOut()).borderRadius(14);
      }.width('100%').justifyContent(FlexAlign.End);
      Row() {
        Button($r('app.string.color_picker_done')).height(34).fontSize(13)
          .backgroundColor(this.previewPrimary());
      }.width('100%').justifyContent(FlexAlign.Center);
    }.width('100%').padding(14).backgroundColor(COLOR_CHAT_BG).borderRadius(CARD_RADIUS);
  }

  @Builder
  accentCard() {
    Column({ space: 12 }) {
      this.section($r('app.string.appearance_accent'), $r('app.string.appearance_accent_sub'));
      this.switchRow($r('app.string.appearance_accent_custom'), this.accentOn, (v: boolean): void => {
        setBoolean(KEY_ACCENT_CUSTOM_ON, v);
        recomputeAppearance();
      });
      if (this.accentOn) {
        Row({ space: 20 }) {
          this.colorCell(this.accentHexLight, KEY_ACCENT_HEX, $r('app.string.appearance_mode_light'));
          this.colorCell(this.accentHexDark, KEY_ACCENT_HEX_DARK, $r('app.string.appearance_mode_dark'));
        }.width('100%');
      }
    }
    .width('100%').padding(14).backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
  }

  @Builder
  bubblesCard() {
    Column({ space: 12 }) {
      this.section($r('app.string.appearance_bubbles'), $r('app.string.appearance_accent_sub'));
      Row({ space: 20 }) {
        Text($r('app.string.appearance_bubble_out')).fontSize(13).fontColor(COLOR_TEXT_PRIMARY).width(52);
        this.colorCell(this.bubbleOutLight, KEY_BUBBLE_OUT_HEX, $r('app.string.appearance_mode_light'));
        this.colorCell(this.bubbleOutDark, KEY_BUBBLE_OUT_HEX_DARK, $r('app.string.appearance_mode_dark'));
      }.width('100%').alignItems(VerticalAlign.Top);
      Row({ space: 20 }) {
        Text($r('app.string.appearance_bubble_in')).fontSize(13).fontColor(COLOR_TEXT_PRIMARY).width(52);
        this.colorCell(this.bubbleInLight, KEY_BUBBLE_IN_HEX, $r('app.string.appearance_mode_light'));
        this.colorCell(this.bubbleInDark, KEY_BUBBLE_IN_HEX_DARK, $r('app.string.appearance_mode_dark'));
      }.width('100%').alignItems(VerticalAlign.Top);
      Row() {
        Button($r('app.string.appearance_reset'), { type: ButtonType.Capsule })
          .fontSize(13).height(32).backgroundColor(COLOR_PAGE_BG).fontColor(COLOR_PRIMARY)
          .onClick((): void => this.resetBubbles());
      }.width('100%').justifyContent(FlexAlign.End);
    }
    .width('100%').padding(14).backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
  }

  @Builder
  materialCard() {
    Column({ space: 12 }) {
      this.section($r('app.string.appearance_bubble_material'), $r('app.string.appearance_bubble_material_sub'));
      this.switchRow($r('app.string.appearance_bubble_material'), this.bubbleMaterialOn, (v: boolean): void => {
        setBoolean(KEY_BUBBLE_MATERIAL_ON, v);
        bumpMaterialEpoch();
        recomputeAppearance();
      });
      if (!immersiveMaterialAvailable()) {
        Text($r('app.string.appearance_bubble_material_glass_only'))
          .fontSize(11).fontColor(COLOR_TEXT_SECONDARY).width('100%');
      }
    }
    .width('100%').padding(14).backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
  }

  @Builder
  section(title: ResourceStr, subtitle: ResourceStr) {
    Column({ space: 3 }) {
      Text(title).fontSize(15).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY)
        .width('100%');
      Text(subtitle).fontSize(11).fontColor(COLOR_TEXT_SECONDARY).width('100%');
    }
  }

  build() {
    Column() {
    // 整个分支结构一起包进来，而不是只包 Scroll 那一支——加载态也要有标题栏。
    HdsSubDestination({
      title: $r('app.string.settings_appearance'),
      pageBackground: COLOR_PAGE_BG,
      scroller: this.hdsScroller
    }) {
      Column() {
        Scroll(this.hdsScroller) {
          Column({ space: 14 }) {
            this.preview();
            this.accentCard();
            this.bubblesCard();
            this.materialCard();
            this.section($r('app.string.appearance_account_group'),
              $r('app.string.appearance_account_group_sub'));
            if (this.namePreviews.length === 0 && this.profilePreviews.length === 0) {
              Column({ space: 9 }) {
                LoadingProgress().width(34).height(34).color(COLOR_PRIMARY);
                Text($r('app.string.accent_waiting_palette')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
                Text($r('app.string.accent_palette_from_server')).fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
              }.width('100%').padding(20);
            }
            Column({ space: 12 }) {
              this.section($r('app.string.accent_name_colour'), $r('app.string.accent_name_colour_sub'));
              Column({ space: 4 }) {
                Text(this.myName !== '' ? this.myName : $r('app.string.accent_your_name'))
                  .fontSize(14).fontWeight(FontWeight.Medium)
                  .fontColor(this.previewNameColor());
                Text($r('app.string.accent_preview_note'))
                  .fontSize(12).fontColor(COLOR_TEXT_PRIMARY);
              }
              .width('100%').alignItems(HorizontalAlign.Start)
              .padding(10).borderRadius(10).backgroundColor(COLOR_PAGE_BG);
              Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                ForEach(this.namePreviews, (preview: AccentPreview) => {
                  Column() {
                    this.swatch(preview, false, (): void => this.applyName(preview.id));
                  }.padding(4);
                }, (preview: AccentPreview): string => `name_${preview.id}`);
              }
            }
            .width('100%').padding(14).backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);

            Column({ space: 12 }) {
              this.section($r('app.string.accent_profile_colour'), $r('app.string.accent_profile_colour_sub'));
              Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                ForEach(this.profilePreviews, (preview: AccentPreview) => {
                  Column() {
                    this.swatch(preview, true, (): void => this.applyProfile(preview.id));
                  }.padding(4);
                }, (preview: AccentPreview): string => `profile_${preview.id}`);
              }
            }
            .width('100%').padding(14).backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);

            Text($r('app.string.accent_premium_note'))
              .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).lineHeight(18).width('100%');
          }.width('100%').padding({ left: 12, right: 12, bottom: this.bottomSafe + 24 });
        }
        .align(Alignment.Top)
        .layoutWeight(1).width('100%').scrollBar(BarState.Off)
        // 不裁剪，内容才能穿到标题栏底下——渐变模糊模糊的正是这部分。
        .clip(false);
      }.width('100%').height('100%');
    }
    }
    .width('100%').height('100%')
    .bindSheet($$this.pickerOpen, this.pickerSheet(), {
      height: SheetSize.FIT_CONTENT,
      showClose: false,
      dragBar: true,
      backgroundColor: COLOR_SURFACE,
      onDisappear: (): void => {
        this.pickerOpen = false;
      }
    });
  }
}
