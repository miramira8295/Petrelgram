// 「聊天设置」里外观相关的四张卡片：气泡颜色、应用强调色、气泡材质、账号颜色。
// 各自独立成组件、各订阅自己的键，页面只负责摆位置。行的样式与聊天设置页的
// toggleRow / 选项行一致：48–52 高、左标题右控件、行间 divider。
//
// 前三张是本机设置（util/appearance.ets），改完只有自己看见；第四张发到服务端，
// 是别人看到的名字色 / 资料页色——所以单独成组、标题里写明。
import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { getAccentColorStore, getTdClient } from '../../tdkit/Globals';
import { AccentPalettes } from '../../store/AccentColorStore';
import { TdError, TdObject, TdRequest } from '../../tdkit/TdTypes';
import { AccentPreview, accentPreviewOf, profileAccentPreviewOf } from '../../util/accentPresentation';
import {
  COLOR_PRIMARY, COLOR_SURFACE, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY, darkResourceMode
} from '../../util/theme';
import {
  BUBBLE_HEX_KEYS, KEY_ACCENT_CUSTOM_ON, KEY_ACCENT_HEX, KEY_ACCENT_HEX_DARK, KEY_BUBBLE_IN_HEX,
  KEY_BUBBLE_IN_HEX_DARK, KEY_BUBBLE_MATERIAL_ON, KEY_BUBBLE_OUT_HEX, KEY_BUBBLE_OUT_HEX_DARK,
  KEY_STATUS_FOLLOW_TITLE, defaultHexFor, hexOrDefault, recomputeAppearance
} from '../../util/appearance';
import { setBoolean, setString } from '../../store/AppSettings';
import { bumpMaterialEpoch, immersiveMaterialAvailable } from '../../util/overlayMaterial';
import { ColorPickerSheet } from '../common/ColorPickerSheet';
import { str } from '../../util/strings';
import { logE } from '../../util/log';
import { APPEARANCE_EPOCH } from '../../util/appearance';

const CARD_RADIUS: number = 14;
const ROW_H: number = 48;
const DOT: number = 26;
const SWATCH: number = 44;

// ---------- 通用小件 ----------

@Builder
function cardTitle(title: ResourceStr) {
  Text(title).fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
    .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 4 });
}

// 整行可点，弹自绘取色器：拖动实时预览、「取消」恢复打开前的值、「确定」保留。
// 官方 HdsColorPicker 是封闭的旋钮（弹窗自管、没有确认/取消、整行点不到），这里不用。
function applyHex(key: string, hex: string): void {
  setString(key, hex);
  recomputeAppearance();
}

@Builder
function rowDivider() {
  Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16 });
}

// ---------- 气泡颜色 ----------

@Component
export struct BubbleColorsCard {
  @StorageProp(APPEARANCE_EPOCH) appearanceEpoch: number = 0;
  // 强调色是 theme 里的活绑定，读一次 epoch 让 ArkUI 记下依赖，用户改色后即时重绘。
  private accent(): ResourceColor {
    return this.appearanceEpoch < 0 ? Color.Transparent : COLOR_PRIMARY;
  }

  @StorageProp(KEY_BUBBLE_OUT_HEX) outLight: string = '';
  @StorageProp(KEY_BUBBLE_OUT_HEX_DARK) outDark: string = '';
  @StorageProp(KEY_BUBBLE_IN_HEX) inLight: string = '';
  @StorageProp(KEY_BUBBLE_IN_HEX_DARK) inDark: string = '';
  @State pickerOpen: boolean = false;
  @State pickerKey: string = '';

  @Styles
  rowNormal() {
    .backgroundColor(Color.Transparent)
  }

  @Styles
  rowPressed() {
    .backgroundColor($r('app.color.surface_alt'))
  }

  // 打开前的值：取消时恢复，也是取色器的初始色。
  private pickerBefore: string = '';

  private open(key: string): void {
    this.pickerKey = key;
    this.pickerBefore = hexOrDefault(AppStorage.get<string>(key), defaultHexFor(key));
    this.pickerOpen = true;
  }

  // @Builder 的值参数在调用时冻结，色点必须在 builder 里按键名读状态才会跟着变。
  private hexFor(key: string): string {
    switch (key) {
      case KEY_BUBBLE_OUT_HEX: return this.outLight;
      case KEY_BUBBLE_OUT_HEX_DARK: return this.outDark;
      case KEY_BUBBLE_IN_HEX: return this.inLight;
      default: return this.inDark;
    }
  }

  private reset(): void {
    for (const key of BUBBLE_HEX_KEYS) {
      setString(key, '');
    }
    recomputeAppearance();
  }

  @Builder
  sheet() {
    ColorPickerSheet({
      initialHex: this.pickerBefore,
      onChange: (hex: string): void => applyHex(this.pickerKey, hex),
      onPick: (hex: string): void => {
        this.pickerBefore = hex;
        applyHex(this.pickerKey, hex);
      },
      onCancel: (): void => applyHex(this.pickerKey, this.pickerBefore),
      onClose: (): void => {
        this.pickerOpen = false;
      }
    })
  }

  @Builder
  colorRow(label: string, key: string) {
    Row({ space: 12 }) {
      Text(label).fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
      Column().width(DOT).height(DOT).borderRadius(DOT / 2)
        .backgroundColor(hexOrDefault(this.hexFor(key), defaultHexFor(key)))
        .border({ width: 1, color: '#22000000' });
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).fontColor([COLOR_TEXT_SECONDARY]);
    }
    .width('100%').height(ROW_H).padding({ left: 16, right: 12 })
    .stateStyles({ normal: this.rowNormal, pressed: this.rowPressed })
    .onClick((): void => this.open(key));
  }

  build() {
    Column() {
      cardTitle($r('app.string.appearance_bubbles'));
      this.colorRow(`${str('appearance_bubble_out')} · ${str('appearance_mode_light')}`,
        KEY_BUBBLE_OUT_HEX);
      rowDivider();
      this.colorRow(`${str('appearance_bubble_out')} · ${str('appearance_mode_dark')}`,
        KEY_BUBBLE_OUT_HEX_DARK);
      rowDivider();
      this.colorRow(`${str('appearance_bubble_in')} · ${str('appearance_mode_light')}`,
        KEY_BUBBLE_IN_HEX);
      rowDivider();
      this.colorRow(`${str('appearance_bubble_in')} · ${str('appearance_mode_dark')}`,
        KEY_BUBBLE_IN_HEX_DARK);
      rowDivider();
      Row() {
        Text($r('app.string.appearance_reset')).fontSize(16).fontColor(this.accent());
      }
      .width('100%').height(ROW_H).padding({ left: 16, right: 16 })
      .stateStyles({ normal: this.rowNormal, pressed: this.rowPressed })
      .onClick((): void => this.reset());
    }
    .width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS)
    .bindSheet($$this.pickerOpen, this.sheet(), {
      height: SheetSize.FIT_CONTENT, showClose: false, dragBar: true,
      backgroundColor: COLOR_SURFACE,
      // 滑掉面板视同取消。确定/取消按钮先把 pickerBefore 同步成最终值，这里恢复就是空操作。
      onDisappear: (): void => {
        this.pickerOpen = false;
        applyHex(this.pickerKey, this.pickerBefore);
      }
    });
  }
}

// ---------- 应用强调色 ----------

@Component
export struct AccentColorCard {
  @StorageProp(APPEARANCE_EPOCH) appearanceEpoch: number = 0;
  // 强调色是 theme 里的活绑定，读一次 epoch 让 ArkUI 记下依赖，用户改色后即时重绘。
  private accent(): ResourceColor {
    return this.appearanceEpoch < 0 ? Color.Transparent : COLOR_PRIMARY;
  }

  @StorageProp(KEY_ACCENT_CUSTOM_ON) accentOn: boolean = false;
  @StorageProp(KEY_STATUS_FOLLOW_TITLE) statusFollowTitle: boolean = false;
  @StorageProp(KEY_ACCENT_HEX) hexLight: string = '';
  @StorageProp(KEY_ACCENT_HEX_DARK) hexDark: string = '';
  @State pickerOpen: boolean = false;
  @State pickerKey: string = '';

  @Styles
  rowNormal() {
    .backgroundColor(Color.Transparent)
  }

  @Styles
  rowPressed() {
    .backgroundColor($r('app.color.surface_alt'))
  }

  private setOn(v: boolean): void {
    setBoolean(KEY_ACCENT_CUSTOM_ON, v);
    recomputeAppearance();
  }

  // 打开前的值：取消时恢复，也是取色器的初始色。
  private pickerBefore: string = '';

  private open(key: string): void {
    this.pickerKey = key;
    this.pickerBefore = hexOrDefault(AppStorage.get<string>(key), defaultHexFor(key));
    this.pickerOpen = true;
  }

  private hexFor(key: string): string {
    return key === KEY_ACCENT_HEX ? this.hexLight : this.hexDark;
  }

  @Builder
  sheet() {
    ColorPickerSheet({
      initialHex: this.pickerBefore,
      onChange: (hex: string): void => applyHex(this.pickerKey, hex),
      onPick: (hex: string): void => {
        this.pickerBefore = hex;
        applyHex(this.pickerKey, hex);
      },
      onCancel: (): void => applyHex(this.pickerKey, this.pickerBefore),
      onClose: (): void => {
        this.pickerOpen = false;
      }
    })
  }

  @Builder
  colorRow(label: ResourceStr, key: string) {
    Row({ space: 12 }) {
      Text(label).fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
      Column().width(DOT).height(DOT).borderRadius(DOT / 2)
        .backgroundColor(hexOrDefault(this.hexFor(key), defaultHexFor(key)))
        .border({ width: 1, color: '#22000000' });
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).fontColor([COLOR_TEXT_SECONDARY]);
    }
    .width('100%').height(ROW_H).padding({ left: 16, right: 12 })
    .stateStyles({ normal: this.rowNormal, pressed: this.rowPressed })
    .onClick((): void => this.open(key));
  }

  build() {
    Column() {
      Row({ space: 12 }) {
        Column({ space: 2 }) {
          Text($r('app.string.appearance_accent_custom')).fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
          Text($r('app.string.appearance_accent_sub')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
        }
        .layoutWeight(1).alignItems(HorizontalAlign.Start).justifyContent(FlexAlign.Center).height(52)
        .stateStyles({ normal: this.rowNormal, pressed: this.rowPressed })
        .onClick((): void => this.setOn(!this.accentOn));
        Toggle({ type: ToggleType.Switch, isOn: this.accentOn })
          .selectedColor(this.accent())
          .onChange((v: boolean): void => this.setOn(v));
      }
      .width('100%').height(64).padding({ left: 16, right: 13 }).alignItems(VerticalAlign.Center);
      if (this.accentOn) {
        rowDivider();
        this.colorRow($r('app.string.appearance_mode_light'), KEY_ACCENT_HEX);
        rowDivider();
        this.colorRow($r('app.string.appearance_mode_dark'), KEY_ACCENT_HEX_DARK);
      }
      rowDivider();
      Row({ space: 12 }) {
        Text($r('app.string.appearance_status_follow_title')).fontSize(16)
          .fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
        Toggle({ type: ToggleType.Switch, isOn: this.statusFollowTitle })
          .selectedColor(COLOR_PRIMARY)
          .onChange((v: boolean): void => {
            setBoolean(KEY_STATUS_FOLLOW_TITLE, v);
            recomputeAppearance();
          });
      }
      .width('100%').height(ROW_H).padding({ left: 16, right: 13 })
      .alignItems(VerticalAlign.Center);
    }
    .width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS)
    .bindSheet($$this.pickerOpen, this.sheet(), {
      height: SheetSize.FIT_CONTENT, showClose: false, dragBar: true,
      backgroundColor: COLOR_SURFACE,
      // 滑掉面板视同取消。确定/取消按钮先把 pickerBefore 同步成最终值，这里恢复就是空操作。
      onDisappear: (): void => {
        this.pickerOpen = false;
        applyHex(this.pickerKey, this.pickerBefore);
      }
    });
  }
}

// ---------- 气泡材质 ----------

@Component
export struct BubbleMaterialCard {
  @StorageProp(APPEARANCE_EPOCH) appearanceEpoch: number = 0;
  // 强调色是 theme 里的活绑定，读一次 epoch 让 ArkUI 记下依赖，用户改色后即时重绘。
  private accent(): ResourceColor {
    return this.appearanceEpoch < 0 ? Color.Transparent : COLOR_PRIMARY;
  }

  @StorageProp(KEY_BUBBLE_MATERIAL_ON) on: boolean = false;

  private setOn(v: boolean): void {
    if (v === this.on) {
      return;
    }
    setBoolean(KEY_BUBBLE_MATERIAL_ON, v);
    bumpMaterialEpoch();
    recomputeAppearance();
  }

  private options(): SelectOption[] {
    return [
      { value: str('bubble_material_standard') } as SelectOption,
      { value: str('bubble_material_glass') } as SelectOption
    ];
  }

  build() {
    Column() {
      Row({ space: 12 }) {
        Column({ space: 2 }) {
          Text($r('app.string.appearance_bubble_material')).fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
          Text(immersiveMaterialAvailable()
            ? $r('app.string.appearance_bubble_material_sub')
            : $r('app.string.appearance_bubble_material_glass_only'))
            .fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
        }
        .layoutWeight(1).alignItems(HorizontalAlign.Start).justifyContent(FlexAlign.Center);
        Select(this.options())
          .selected(this.on ? 1 : 0)
          .value(this.on ? str('bubble_material_glass') : str('bubble_material_standard'))
          .font({ size: 15 }).fontColor(this.accent())
          .onSelect((index: number): void => this.setOn(index === 1));
      }
      .width('100%').padding({ left: 16, right: 8, top: 10, bottom: 10 }).alignItems(VerticalAlign.Center);
    }
    .width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
  }
}

// ---------- 账号颜色（名字色 / 资料页色，原 AccentColorPage）----------

@Component
export struct AccountColorsCard {
  @StorageProp(APPEARANCE_EPOCH) appearanceEpoch: number = 0;
  // 强调色是 theme 里的活绑定，读一次 epoch 让 ArkUI 记下依赖，用户改色后即时重绘。
  private accent(): ResourceColor {
    return this.appearanceEpoch < 0 ? Color.Transparent : COLOR_PRIMARY;
  }

  @State namePreviews: AccentPreview[] = [];
  @State profilePreviews: AccentPreview[] = [];
  @State currentNameId: number = -1;
  @State currentProfileId: number = -1;
  @State busy: boolean = false;
  @State myName: string = '';
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

  // available_accent_color_ids 决定服务端的展示顺序，可能引用没有色板项的内置 id。
  private orderPreviews(mapped: (AccentPreview | null)[], availableIds: number[]): AccentPreview[] {
    const byId = new Map<number, AccentPreview>();
    for (const preview of mapped) {
      if (preview !== null) {
        byId.set(preview.id, preview);
      }
    }
    const rows: AccentPreview[] = [];
    for (const id of availableIds) {
      const known = byId.get(id);
      if (known !== undefined) {
        rows.push(known);
      } else {
        const builtin = accentPreviewOf(
          { '@type': 'accentColor', 'id': id, 'built_in_accent_color_id': id } as TdObject, false);
        if (builtin !== null) {
          rows.push(builtin);
        }
      }
    }
    return rows;
  }

  private refreshSelection(): void {
    getAccentColorStore().currentSelection().then((ids: [number, number]): void => {
      if (!this.active) {
        return;
      }
      this.currentNameId = ids[0];
      this.currentProfileId = ids[1];
    }).catch((error: TdError): void => {
      logE(`AccountColorsCard.selection failed: ${error.message}`);
    });
    getTdClient().send({ '@type': 'getMe' } as TdRequest).then((me: TdObject): void => {
      if (!this.active) {
        return;
      }
      const first = (me['first_name'] as string | undefined) ?? '';
      const last = (me['last_name'] as string | undefined) ?? '';
      this.myName = `${first} ${last}`.trim();
    }).catch((): void => {});
  }

  // 你自己的名字色是**别人**在群里看到的——自己的发出气泡从不带名字，所以放这儿预览。
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
    if (this.busy) {
      return;
    }
    this.busy = true;
    getAccentColorStore().setNameAccentColor(id).then((): void => {
      if (!this.active) {
        return;
      }
      this.busy = false;
      this.currentNameId = id;
      promptAction.showToast({ message: $r('app.string.accent_name_updated'), duration: 1500 });
    }).catch((error: TdError): void => {
      if (!this.active) {
        return;
      }
      this.busy = false;
      promptAction.showToast({ message: this.errorText(error), duration: 1800 });
    });
  }

  private applyProfile(id: number): void {
    if (this.busy) {
      return;
    }
    this.busy = true;
    getAccentColorStore().setProfileAccentColor(id).then((): void => {
      if (!this.active) {
        return;
      }
      this.busy = false;
      this.currentProfileId = id;
      promptAction.showToast({ message: $r('app.string.accent_profile_updated'), duration: 2200 });
    }).catch((error: TdError): void => {
      if (!this.active) {
        return;
      }
      this.busy = false;
      promptAction.showToast({ message: this.errorText(error), duration: 1800 });
    });
  }

  private isSelected(preview: AccentPreview, forProfile: boolean): boolean {
    return (forProfile ? this.currentProfileId : this.currentNameId) === preview.id;
  }

  // 选中态在 builder 里读 @State：@Builder 的值参数在调用时冻结，拿不到异步回来的当前色。
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
    .border({ width: this.isSelected(preview, forProfile) ? 2 : 0, color: this.accent() })
    .onClick(onTap);
  }

  @Builder
  subTitle(title: ResourceStr, subtitle: ResourceStr) {
    Column({ space: 3 }) {
      Text(title).fontSize(15).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY).width('100%');
      Text(subtitle).fontSize(11).fontColor(COLOR_TEXT_SECONDARY).width('100%');
    }.padding({ left: 16, right: 16 });
  }

  build() {
    Column({ space: 12 }) {
      cardTitle($r('app.string.appearance_account_group'));
      Text($r('app.string.appearance_account_group_sub')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
        .width('100%').padding({ left: 16, right: 16 });
      if (this.namePreviews.length === 0 && this.profilePreviews.length === 0) {
        Column({ space: 9 }) {
          LoadingProgress().width(34).height(34).color(this.accent());
          Text($r('app.string.accent_waiting_palette')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
        }.width('100%').padding(20);
      } else {
        this.subTitle($r('app.string.accent_name_colour'), $r('app.string.accent_name_colour_sub'));
        Column({ space: 4 }) {
          Text(this.myName !== '' ? this.myName : $r('app.string.accent_your_name'))
            .fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.previewNameColor());
          Text($r('app.string.accent_preview_note')).fontSize(12).fontColor(COLOR_TEXT_PRIMARY);
        }
        .alignItems(HorizontalAlign.Start).padding(10).borderRadius(10)
        .backgroundColor($r('app.color.page_bg')).margin({ left: 16, right: 16 });
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach(this.namePreviews, (preview: AccentPreview) => {
            Column() {
              this.swatch(preview, false, (): void => this.applyName(preview.id));
            }.padding(4);
          }, (preview: AccentPreview): string => `name_${preview.id}`);
        }.padding({ left: 12, right: 12 });
        rowDivider();
        this.subTitle($r('app.string.accent_profile_colour'), $r('app.string.accent_profile_colour_sub'));
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach(this.profilePreviews, (preview: AccentPreview) => {
            Column() {
              this.swatch(preview, true, (): void => this.applyProfile(preview.id));
            }.padding(4);
          }, (preview: AccentPreview): string => `profile_${preview.id}`);
        }.padding({ left: 12, right: 12 });
        Text($r('app.string.accent_premium_note'))
          .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).lineHeight(18).width('100%')
          .padding({ left: 16, right: 16, bottom: 14 });
      }
    }
    .width('100%').alignItems(HorizontalAlign.Start)
    .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
  }
}
