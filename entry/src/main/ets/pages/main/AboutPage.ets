import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import {
  updateChecker, UpdateInfo, STORAGE_UPDATE_AVAILABLE
} from '../../services/UpdateChecker';
import { MdBlock, MdSpan, parseMarkdownBlocks } from '../../util/markdownBlocks';
import { str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';

const CARD_BG: ResourceColor = $r('app.color.surface');
const CARD_RADIUS: number = 14;

@Entry
@Component
struct AboutPage {
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @StorageProp(STORAGE_UPDATE_AVAILABLE) hasUpdate: boolean = false;
  @State currentVersion: string = '';
  @State latestVersion: string = '';
  @State notes: string = '';
  @State checking: boolean = false;
  @State noteBlocks: MdBlock[] = [];

  aboutToAppear(): void {
    this.apply(updateChecker.snapshot());
  }

  private apply(info: UpdateInfo): void {
    this.currentVersion = info.currentVersion;
    this.latestVersion = info.latestVersion;
    this.notes = info.notes;
    this.noteBlocks = parseMarkdownBlocks(info.notes);
  }

  private checkNow(): void {
    if (this.checking) {
      return;
    }
    this.checking = true;
    updateChecker.check(true).then((info: UpdateInfo): void => {
      this.checking = false;
      this.apply(info);
      if (!info.hasUpdate) {
        promptAction.showToast({
          message: info.latestVersion === ''
            ? $r('app.string.about_update_unreachable') : $r('app.string.about_up_to_date'),
          duration: 1600
        });
      }
    }).catch((): void => {
      this.checking = false;
    });
  }

  private openReleasePage(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    context.startAbility({
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: updateChecker.getReleaseUrl()
    }).catch((e: Object): void => {
      console.error(`AboutPage.openReleasePage failed: ${JSON.stringify(e)}`);
      promptAction.showToast({ message: $r('app.string.about_browser_failed'), duration: 1600 });
    });
  }

  // 圆角方块图标 + 标题/副标题的通用行，和设置页的观感保持一致。
  @Builder
  iconRow(symbol: string, bg: string, title: ResourceStr, subtitle: ResourceStr,
    accent: boolean, busy: boolean, onTap: () => void) {
    Row({ space: 14 }) {
      Stack({ alignContent: Alignment.Center }) {
        if (busy) {
          LoadingProgress().width(18).height(18).color(Color.White);
        } else {
          SymbolGlyph($r(symbol)).fontSize(18).fontColor([Color.White]);
        }
      }
      .width(34).height(34).borderRadius(9).backgroundColor(bg);
      Column({ space: 3 }) {
        Text(title)
          .fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor(accent ? COLOR_PRIMARY : COLOR_TEXT_PRIMARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(subtitle)
          .fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16).fontColor([COLOR_TEXT_SECONDARY]);
    }
    .width('100%').height(62)
    .padding({ left: 14, right: 14 })
    .onClick(onTap);
  }

  // 发布说明按块渲染。整段纯文本会把 ## 和 ** 原样显示出来，很难看。
  @Builder
  noteBlock(block: MdBlock) {
    if (block.kind === 'bullet') {
      Row({ space: 8 }) {
        Circle({ width: 4, height: 4 })
          .fill(COLOR_TEXT_SECONDARY).margin({ top: 7 });
        Text() {
          ForEach(block.spans, (s: MdSpan): void => {
            Span(s.text)
              .fontWeight(s.bold ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(s.code ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY);
          });
        }
        .fontSize(13).lineHeight(20).layoutWeight(1);
      }
      .width('100%').alignItems(VerticalAlign.Top);
    } else {
      Text() {
        ForEach(block.spans, (s: MdSpan): void => {
          Span(s.text)
            .fontWeight(block.kind === 'heading' || s.bold
              ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(s.code ? COLOR_PRIMARY
              : (block.kind === 'heading' ? COLOR_TEXT_PRIMARY : COLOR_TEXT_SECONDARY));
        });
      }
      .fontSize(block.kind === 'heading' ? 14 : 13)
      .lineHeight(block.kind === 'heading' ? 22 : 20)
      .width('100%')
      .margin({ top: block.kind === 'heading' ? 6 : 0 });
    }
  }

  @Builder
  header() {
    Row() {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(22).fontColor([COLOR_TEXT_PRIMARY]);
      }
      .width(40).height(40).justifyContent(FlexAlign.Center)
      .accessibilityText($r('app.string.back'))
      .onClick((): void => { router.back(); });
      Text($r('app.string.settings_about')).fontSize(18).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
      Blank().layoutWeight(1);
    }
    .width('100%').height(56)
    .padding({ left: 8, right: 16 })
    .alignItems(VerticalAlign.Center);
  }

  build() {
    Column() {
      this.header();
      Scroll() {
        Column({ space: 12 }) {
          Column({ space: 6 }) {
            // layered_image.json 只是指向 background/foreground 两层的描述文件，
            // Image 渲染不了；这里自己把两层叠出来，等同桌面上的图标。
            Stack() {
              Image($r('app.media.background')).width(72).height(72).draggable(false);
              Image($r('app.media.foreground')).width(72).height(72).draggable(false);
            }
            .width(72).height(72).borderRadius(16).clip(true);
            Text($r('app.string.app_name'))
              .fontSize(17).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
            Text(this.currentVersion !== '' ? str('about_version', this.currentVersion) : $r('app.string.about_version_loading'))
              .fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
          }
          .width('100%')
          .padding({ top: 24, bottom: 12 });

          Column() {
            this.iconRow(
              this.hasUpdate ? 'sys.symbol.arrow_down_circle' : 'sys.symbol.arrow_clockwise',
              this.hasUpdate ? '#FF3B30' : '#34C759',
              this.hasUpdate ? str('about_update_available', this.latestVersion) : $r('app.string.about_check_update'),
              this.latestVersion !== '' ? str('about_latest_release', this.latestVersion) : $r('app.string.about_no_release_info'),
              this.hasUpdate, this.checking,
              (): void => { this.checkNow(); });
            if (this.hasUpdate) {
              Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 62 });
              this.iconRow('sys.symbol.arrow_down_to_line', '#007AFF',
                $r('app.string.about_download'), $r('app.string.about_open_release_page'), true, false,
                (): void => { this.openReleasePage(); });
            }
            Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 62 });
            this.iconRow('sys.symbol.link', '#5856D6',
              $r('app.string.about_repository'), $r('app.string.about_repository_sub'), false, false,
              (): void => { this.openReleasePage(); });
          }
          .width('100%')
          .backgroundColor(CARD_BG).borderRadius(CARD_RADIUS);

          if (this.noteBlocks.length > 0) {
            Column({ space: 7 }) {
              Row({ space: 8 }) {
                SymbolGlyph($r('sys.symbol.doc_text')).fontSize(15).fontColor([COLOR_PRIMARY]);
                Text(str('about_release_notes', this.latestVersion))
                  .fontSize(13).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY)
                  .layoutWeight(1);
              }
              .width('100%').alignItems(VerticalAlign.Center);
              ForEach(this.noteBlocks, (block: MdBlock): void => {
                this.noteBlock(block);
              });
            }
            .width('100%')
            .padding(14)
            .backgroundColor(CARD_BG).borderRadius(CARD_RADIUS);
          }

          Text($r('app.string.about_disclaimer'))
            .fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
            .width('100%').textAlign(TextAlign.Center)
            .padding({ top: 8 });
        }
        .width('100%')
        .padding({ left: 12, right: 12, bottom: this.bottomSafe + 24 });
      }
      .layoutWeight(1).width('100%').align(Alignment.Top)
      .scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring);
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.page_bg'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .padding({ top: this.topSafe });
  }
}
