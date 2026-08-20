import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { getAccentColorStore, getTdClient } from '../../tdkit/Globals';
import { AccentPalettes } from '../../store/AccentColorStore';
import { TdError, TdObject, TdRequest } from '../../tdkit/TdTypes';
import {
  AccentPreview, accentPreviewOf, profileAccentPreviewOf
} from '../../util/accentPresentation';
import { syncAccentPrimary } from '../../util/accentTheme';
import {
  COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY,
  darkResourceMode
} from '../../util/theme';
import { str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';

const CARD_RADIUS: number = 14;
const SWATCH: number = 44;

@Entry
@Component
struct AccentColorPage {
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
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
      console.error(`AccentColorPage.selection failed: ${error.message}`);
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
      syncAccentPrimary(getContext(this) as common.UIAbilityContext);
      promptAction.showToast({
        message: $r('app.string.accent_profile_updated'), duration: 2200
      });
    }).catch((error: TdError): void => {
      if (!this.active) { return; }
      this.busy = false;
      promptAction.showToast({ message: this.errorText(error), duration: 1800 });
    });
  }

  @Builder
  header() {
    Row({ space: 8 }) {
      Button() {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([COLOR_TEXT_PRIMARY]);
      }.width(40).height(40).borderRadius(20).backgroundColor(Color.Transparent)
      .onClick((): void => { router.back(); });
      Text($r('app.string.settings_accent')).fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .layoutWeight(1);
      if (this.busy) { LoadingProgress().width(20).height(20).color(COLOR_PRIMARY); }
    }.width('100%').height(52).padding({ left: 8, right: 16 }).alignItems(VerticalAlign.Center);
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
      this.header();
      if (this.namePreviews.length === 0 && this.profilePreviews.length === 0) {
        Column({ space: 9 }) {
          LoadingProgress().width(34).height(34).color(COLOR_PRIMARY);
          Text($r('app.string.accent_waiting_palette')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
          Text($r('app.string.accent_palette_from_server')).fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else {
        Scroll() {
          Column({ space: 14 }) {
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
        }.layoutWeight(1).width('100%').scrollBar(BarState.Off);
      }
    }
    .width('100%').height('100%').backgroundColor(COLOR_PAGE_BG)
    // 没有这一行时页面的布局区停在安全区边界，状态栏那一条不归页面画，
    // 露出的是窗口底色。padding 只负责把内容让开，铺满是另一回事。
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .padding({ top: this.topSafe });
  }
}
