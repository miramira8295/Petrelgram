import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { getChatThemeStore } from '../../tdkit/Globals';
import { TdError, TdObject } from '../../tdkit/TdTypes';
import {
  ChatThemePreview, chatThemePreviewOf
} from '../../util/chatThemePresentation';
import {
  COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY,
  darkResourceMode
} from '../../util/theme';

const CARD_RADIUS: number = 14;
const TILE_HEIGHT: number = 128;

interface ThemePageParams {
  chatId?: number;
}

@Entry
@Component
struct ChatThemePage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State previews: ChatThemePreview[] = [];
  @State applyingName: string = '';
  private chatId: number = 0;
  private off: (() => void) | null = null;
  private active: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    const params = router.getParams() as ThemePageParams | undefined;
    this.chatId = params?.chatId ?? 0;
    const dark = darkResourceMode(getContext(this) as common.UIAbilityContext);
    getChatThemeStore().ensureLoaded();
    this.off = getChatThemeStore().subscribe((themes: TdObject[]): void => {
      const rows: ChatThemePreview[] = [];
      for (const theme of themes) {
        const preview = chatThemePreviewOf(theme, dark);
        if (preview !== null) { rows.push(preview); }
      }
      this.previews = rows;
    });
  }

  aboutToDisappear(): void {
    this.active = false;
    if (this.off !== null) {
      this.off();
      this.off = null;
    }
  }

  private apply(themeName: string): void {
    if (this.applyingName !== '' || this.chatId === 0) { return; }
    this.applyingName = themeName === '' ? 'reset' : themeName;
    getChatThemeStore().setChatTheme(this.chatId, themeName).then((): void => {
      if (!this.active) { return; }
      this.applyingName = '';
      promptAction.showToast({
        message: themeName === '' ? $r('app.string.chat_theme_reset_done') : $r('app.string.chat_theme_set_done'),
        duration: 1700
      });
    }).catch((error: TdError): void => {
      if (!this.active) { return; }
      this.applyingName = '';
      console.error(`ChatThemePage.apply failed: ${error.message}`);
      promptAction.showToast({ message: $r('app.string.chat_theme_failed'), duration: 1800 });
    });
  }

  @Builder
  header() {
    Row({ space: 8 }) {
      Button() {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([COLOR_TEXT_PRIMARY]);
      }.width(40).height(40).borderRadius(20).backgroundColor(Color.Transparent)
      .onClick((): void => { router.back(); });
      Text($r('app.string.chat_theme_title')).fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .layoutWeight(1);
      if (this.applyingName !== '') {
        LoadingProgress().width(20).height(20).color(COLOR_PRIMARY);
      }
    }.width('100%').height(52).padding({ left: 8, right: 16 }).alignItems(VerticalAlign.Center);
  }

  @Builder
  tile(preview: ChatThemePreview) {
    Column() {
      Stack({ alignContent: Alignment.Center }) {
        if (preview.backgroundColors.length > 1) {
          Column().width('100%').height('100%')
            .linearGradient({
              angle: 180,
              colors: preview.backgroundColors.map(
                (color: string, index: number): [string, number] =>
                  [color, index / (preview.backgroundColors.length - 1)])
            });
        } else {
          Column().width('100%').height('100%')
            .backgroundColor(preview.backgroundColors.length === 1
              ? preview.backgroundColors[0] : COLOR_SURFACE);
        }
        Column({ space: 5 }) {
          // Tiny bubble mock-up so the outgoing color is visible at a glance.
          Row().width(52).height(16).borderRadius(8)
            .backgroundColor(preview.bubbleColors.length > 0
              ? preview.bubbleColors[0] : preview.accent)
            .alignSelf(ItemAlign.End);
          Row().width(44).height(16).borderRadius(8)
            .backgroundColor('#E8FFFFFF')
            .alignSelf(ItemAlign.Start);
        }.width(76);
        if (this.applyingName === preview.name) {
          Column() {
            LoadingProgress().width(24).height(24).color(Color.White);
          }.width('100%').height('100%').justifyContent(FlexAlign.Center)
          .backgroundColor('#40000000');
        }
      }
      .width('100%').height(TILE_HEIGHT - 30).borderRadius(12).clip(true);
      Text(preview.name).fontSize(16).padding({ top: 5 });
    }
    .onClick((): void => this.apply(preview.name));
  }

  build() {
    Column() {
      this.header();
      if (this.previews.length === 0) {
        Column({ space: 9 }) {
          LoadingProgress().width(34).height(34).color(COLOR_PRIMARY);
          Text($r('app.string.chat_theme_waiting')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
          Text($r('app.string.chat_theme_from_server')).fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else {
        Scroll() {
          Column({ space: 12 }) {
            Row({ space: 10 }) {
              SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(17).fontColor([COLOR_PRIMARY]);
              Text($r('app.string.chat_theme_reset')).fontSize(15).fontColor(COLOR_PRIMARY).layoutWeight(1);
            }
            .width('100%').height(48).padding({ left: 14, right: 14 })
            .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS)
            .onClick((): void => this.apply(''));
            GridRow({ columns: 3, gutter: 10 }) {
              ForEach(this.previews, (preview: ChatThemePreview) => {
                GridCol({ span: 1 }) { this.tile(preview); }
              }, (preview: ChatThemePreview): string => `theme_${preview.name}`);
            }
            Text($r('app.string.chat_theme_note'))
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
