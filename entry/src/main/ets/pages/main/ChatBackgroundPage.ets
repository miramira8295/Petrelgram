import { router, promptAction } from '@kit.ArkUI';
import { TdError, TdObject } from '../../tdkit/TdTypes';
import {
  applyChatBackground, applyRemoteBackground, clearChatBackground,
  downloadFileToPath, listBackgrounds, resetDefaultBackground
} from '../../store/BackgroundApi';
import {
  BackgroundPreview, backgroundPreviewOf, backgroundThumbnailFile
} from '../../util/backgroundPresentation';
import { defaultChatBackgroundSnapshot, invalidateDefaultSnapshot } from '../../store/ChatBackgroundStore';
import {
  COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';
import {
  BG_BLUR_DEFAULT, BG_BLUR_MAX, BG_BLUR_MIN, BG_PATTERN_DEFAULT, BG_PATTERN_MIN,
  CHAT_DIM_MAX, KEY_BG_BLUR, KEY_BG_PATTERN, KEY_BG_PATTERN_DARK, KEY_CHAT_DIM,
  patternStrengthKey, setNumber
} from '../../store/AppSettings';

const CARD_RADIUS: number = 14;
const TILE_HEIGHT: number = 118;

interface GalleryRow {
  preview: BackgroundPreview;
  raw: TdObject;
}

interface BackgroundPageParams {
  chatId?: number;
}

@Entry
@Component
struct ChatBackgroundPage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @StorageProp(KEY_BG_BLUR) bgBlur: number = BG_BLUR_DEFAULT;
  @State loadState: string = 'loading';
  @State rows: GalleryRow[] = [];
  @State forDark: boolean = false;
  @StorageProp(KEY_BG_PATTERN) bgPatternLight: number = BG_PATTERN_DEFAULT;
  @StorageProp(KEY_BG_PATTERN_DARK) bgPatternDark: number = BG_PATTERN_DEFAULT;
  // 深色遮罩强度（0..CHAT_DIM_MAX）。滑杆按百分比显示，存的是 0..1 的小数。
  @StorageLink(KEY_CHAT_DIM) chatDim: number = 0;
  @State applyingId: string = '';
  @State thumbPaths: Map<string, string> = new Map();
  // 0 = account default mode; non-zero = one chat only. Group/channel chat
  // ids are NEGATIVE — never gate the per-chat branch on chatId > 0.
  private chatId: number = 0;
  private active: boolean = false;
  private sequence: number = 0;

  aboutToAppear(): void {
    this.active = true;
    const params = router.getParams() as BackgroundPageParams | undefined;
    this.chatId = params?.chatId ?? 0;
    this.load();
  }

  aboutToDisappear(): void {
    this.active = false;
    this.sequence++;
  }

  private load(): void {
    const sequence = ++this.sequence;
    this.loadState = 'loading';
    listBackgrounds(this.forDark).then((backgrounds: TdObject[]): void => {
      if (!this.active || sequence !== this.sequence) { return; }
      const rows: GalleryRow[] = [];
      for (const raw of backgrounds) {
        const preview = backgroundPreviewOf(raw);
        if (preview !== null && (preview.colors.length > 0 || preview.kind === 'wallpaper')) {
          rows.push({ preview, raw });
        }
      }
      this.rows = rows;
      this.loadState = 'ready';
      this.loadThumbnails(rows, sequence);
    }).catch((error: TdError): void => {
      if (!this.active || sequence !== this.sequence) { return; }
      console.error(`ChatBackgroundPage.load failed: ${error.message}`);
      this.loadState = 'error';
    });
  }

  // Photo wallpapers can't be drawn from colors — fetch their small document
  // thumbnails after the grid is already on screen.
  private loadThumbnails(rows: GalleryRow[], sequence: number): void {
    for (const row of rows) {
      if (row.preview.kind !== 'wallpaper') { continue; }
      const file = backgroundThumbnailFile(row.raw);
      const fileId = file !== null ? ((file['id'] as number | undefined) ?? 0) : 0;
      if (fileId <= 0) { continue; }
      downloadFileToPath(fileId).then((path: string): void => {
        if (!this.active || sequence !== this.sequence || path === '') { return; }
        const next = new Map(this.thumbPaths);
        next.set(row.preview.backgroundId, path);
        this.thumbPaths = next;
      }).catch((error: TdError): void => {
        console.error(`ChatBackgroundPage.thumb ${fileId} failed: ${error.message}`);
      });
    }
  }

  private setForDark(value: boolean): void {
    if (this.forDark === value) { return; }
    this.forDark = value;
    this.thumbPaths = new Map();
    this.load();
  }

  // 账号默认背景变了：作废持久化快照，否则冷启动后第一个会话会先画出旧背景。
  private invalidateSnapshotIfDefault(): void {
    if (this.chatId === 0) {
      invalidateDefaultSnapshot(this.forDark);
    }
  }

  private apply(row: GalleryRow): void {
    if (this.applyingId !== '') { return; }
    this.applyingId = row.preview.backgroundId;
    this.invalidateSnapshotIfDefault();
    const task: Promise<void> = this.chatId !== 0
      ? applyChatBackground(this.chatId, row.raw, true)
      : applyRemoteBackground(row.raw, this.forDark);
    task.then((): void => {
      if (!this.active) { return; }
      this.applyingId = '';
      promptAction.showToast({
        message: this.chatId !== 0
          ? $r('app.string.cb_chat_set')
          : (this.forDark ? $r('app.string.cb_dark_set') : $r('app.string.cb_light_set')),
        duration: 1600
      });
    }).catch((error: TdError): void => {
      if (!this.active) { return; }
      this.applyingId = '';
      console.error(`ChatBackgroundPage.apply failed: ${error.message}`);
      const text = error.message.indexOf('BOOST') >= 0 || error.message.indexOf('boost') >= 0
        ? $r('app.string.cb_boost_required')
        : (error.message.indexOf('ADMIN') >= 0 || error.message.indexOf('rights') >= 0
          ? $r('app.string.cb_admin_required')
          : $r('app.string.cb_set_failed'));
      promptAction.showToast({ message: text, duration: 2000 });
    });
  }

  private setBlur(value: number, mode: SliderChangeMode): void {
    if (mode !== SliderChangeMode.End) {
      return;
    }
    setNumber(KEY_BG_BLUR, Math.round(value));
  }

  private reset(): void {
    if (this.applyingId !== '') { return; }
    this.applyingId = 'reset';
    this.invalidateSnapshotIfDefault();
    const task: Promise<void> = this.chatId !== 0
      ? clearChatBackground(this.chatId)
      : resetDefaultBackground(this.forDark);
    task.then((): void => {
      if (!this.active) { return; }
      this.applyingId = '';
      promptAction.showToast({
        message: this.chatId !== 0 ? $r('app.string.cb_reset_to_global') : $r('app.string.cb_reset_done'), duration: 1500
      });
    }).catch((error: TdError): void => {
      if (!this.active) { return; }
      this.applyingId = '';
      console.error(`ChatBackgroundPage.reset failed: ${error.message}`);
      promptAction.showToast({ message: $r('app.string.cb_reset_failed'), duration: 1800 });
    });
  }

  @Builder
  header() {
    Row({ space: 8 }) {
      Button() {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([COLOR_TEXT_PRIMARY]);
      }.width(40).height(40).borderRadius(20).backgroundColor(Color.Transparent)
      .onClick((): void => { router.back(); });
      Text(this.chatId !== 0 ? $r('app.string.cb_chat_title') : $r('app.string.chat_settings_background'))
        .fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .layoutWeight(1);
      if (this.applyingId !== '') { LoadingProgress().width(20).height(20).color(COLOR_PRIMARY); }
    }.width('100%').height(52).padding({ left: 8, right: 16 }).alignItems(VerticalAlign.Center);
  }

  @Builder
  modeSwitch() {
    Row() {
      Text($r('app.string.cb_light_theme')).fontSize(14)
        .fontColor(!this.forDark ? Color.White : COLOR_TEXT_SECONDARY)
        .height(34).padding({ left: 18, right: 18 }).borderRadius(17)
        .backgroundColor(!this.forDark ? COLOR_PRIMARY : Color.Transparent)
        .onClick((): void => this.setForDark(false));
      Text($r('app.string.cb_dark_theme')).fontSize(14)
        .fontColor(this.forDark ? Color.White : COLOR_TEXT_SECONDARY)
        .height(34).padding({ left: 18, right: 18 }).borderRadius(17)
        .backgroundColor(this.forDark ? COLOR_PRIMARY : Color.Transparent)
        .onClick((): void => this.setForDark(true));
    }
    .padding(3).borderRadius(20).backgroundColor(COLOR_SURFACE);
  }

  // 深色遮罩。原来在「聊天设置 → 夜间模式」那张卡里，但它调的是背景的明暗，
  // 归到背景页的深色一侧才找得着。只在深色页签下出现——它本来就只在深色模式
  // 生效，挂在浅色页签上会让人以为浅色也起作用。
  //
  // 全局设置：单个会话的背景页没有浅/深切换（chatId !== 0 时不显示），
  // 遮罩也就不在那里露面。
  @Builder
  darkDimCard() {
    Column({ space: 8 }) {
      Row() {
        Text($r('app.string.chat_settings_dark_dim')).fontSize(15)
          .fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
        Text(`${Math.round(this.chatDim * 100)}%`).fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
      }.width('100%');
      Text($r('app.string.chat_settings_dark_dim_sub'))
        .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).width('100%');
      Slider({
        value: Math.round(this.chatDim * 100),
        min: 0,
        max: Math.round(CHAT_DIM_MAX * 100),
        step: 5,
        style: SliderStyle.OutSet
      })
        .width('100%')
        .trackColor($r('app.color.divider'))
        .selectedColor(COLOR_PRIMARY)
        .blockColor(COLOR_PRIMARY)
        .onChange((value: number): void => {
          const next: number = Math.round(value) / 100;
          this.chatDim = next;
          setNumber(KEY_CHAT_DIM, next);
        });
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
  }

  // 图案线条太重时压一档。乘在壁纸自带的 intensity 上，不改壁纸本身，
  // 所以换一张图案后这个设置仍然生效。整图壁纸没有图案可言，滑块不出现。
  private patternValue(): number {
    return this.forDark ? this.bgPatternDark : this.bgPatternLight;
  }

  // 当前生效的背景是不是图案。整图壁纸没有图案可言，滑块不该出现。
  // 读的是全局那份快照——这个页面自己只管"能选哪些"，不持有当前状态。
  private currentIsPattern(): boolean {
    return defaultChatBackgroundSnapshot(this.forDark).isPattern;
  }

  @Builder
  patternCard() {
    Column({ space: 8 }) {
      Row() {
        Text($r('app.string.cb_pattern_strength')).fontSize(15)
          .fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
        Text(`${Math.round(this.patternValue() * 100)}%`).fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
      }.width('100%');
      Slider({
        value: Math.round(this.patternValue() * 100),
        min: Math.round(BG_PATTERN_MIN * 100),
        max: 100,
        step: 5,
        style: SliderStyle.OutSet
      })
        .width('100%')
        .trackColor($r('app.color.divider'))
        .selectedColor(COLOR_PRIMARY)
        .blockColor(COLOR_PRIMARY)
        .onChange((value: number): void => {
          const next: number = Math.round(value) / 100;
          // 写到当前页签对应的那一份：浅色页签调浅色，深色页签调深色。
          if (this.forDark) {
            this.bgPatternDark = next;
          } else {
            this.bgPatternLight = next;
          }
          setNumber(patternStrengthKey(this.forDark), next);
        });
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
  }

  @Builder
  blurCard() {
    Column({ space: 8 }) {
      Row() {
        Text($r('app.string.cb_blur_amount')).fontSize(15).fontColor(COLOR_TEXT_PRIMARY)
          .layoutWeight(1);
        Text(`${this.bgBlur}`).fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
      }.width('100%');
      Slider({
        value: this.bgBlur,
        min: BG_BLUR_MIN,
        max: BG_BLUR_MAX,
        step: 1,
        style: SliderStyle.OutSet
      })
        .width('100%')
        .trackColor($r('app.color.divider'))
        .selectedColor(COLOR_PRIMARY)
        .blockColor(COLOR_PRIMARY)
        .onChange((value: number, mode: SliderChangeMode): void => { this.setBlur(value, mode); });
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
  }

  @Builder
  tile(row: GalleryRow) {
    Stack({ alignContent: Alignment.BottomStart }) {
      if (row.preview.kind === 'wallpaper') {
        if ((this.thumbPaths.get(row.preview.backgroundId) ?? '') !== '') {
          Image(`file://${this.thumbPaths.get(row.preview.backgroundId)}`).draggable(false)
            .width('100%').height('100%').objectFit(ImageFit.Cover);
        } else {
          Column() {
            LoadingProgress().width(22).height(22).color(COLOR_TEXT_SECONDARY);
          }.width('100%').height('100%').justifyContent(FlexAlign.Center)
          .backgroundColor(COLOR_SURFACE);
        }
      } else if (row.preview.colors.length === 1) {
        Column().width('100%').height('100%').backgroundColor(row.preview.colors[0]);
      } else {
        Column().width('100%').height('100%')
          .linearGradient({
            angle: row.preview.angle,
            colors: row.preview.colors.map((color: string, index: number): [string, number] =>
              [color, row.preview.colors.length > 1 ? index / (row.preview.colors.length - 1) : 0])
          });
      }
      if (row.preview.kind === 'pattern') {
        Text($r('app.string.cb_pattern')).fontSize(10).fontColor('#D9FFFFFF')
          .padding({ left: 7, right: 7, top: 2, bottom: 2 })
          .borderRadius(9).backgroundColor('#59000000').margin(7);
      }
      if (this.applyingId === row.preview.backgroundId) {
        Column() {
          LoadingProgress().width(26).height(26).color(Color.White);
        }.width('100%').height('100%').justifyContent(FlexAlign.Center)
        .backgroundColor('#40000000');
      }
    }
    .width('100%').height(TILE_HEIGHT).borderRadius(12).clip(true)
    .onClick((): void => this.apply(row));
  }

  build() {
    Column() {
      this.header();
      if (this.chatId === 0) {
        Row() { this.modeSwitch(); }.width('100%').justifyContent(FlexAlign.Center)
          .padding({ top: 2, bottom: 10 });
      }
      if (this.loadState === 'loading') {
        Column({ space: 9 }) {
          LoadingProgress().width(34).height(34).color(COLOR_PRIMARY);
          Text($r('app.string.cb_loading')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else if (this.loadState === 'error') {
        Column({ space: 10 }) {
          Text($r('app.string.cb_load_failed')).fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
          Button($r('app.string.settings_reload')).onClick((): void => this.load());
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else {
        Scroll() {
          Column({ space: 12 }) {
            Row({ space: 10 }) {
              SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(17).fontColor([COLOR_PRIMARY]);
              Text(this.chatId !== 0 ? $r('app.string.cb_reset_to_global_action') : $r('app.string.cb_reset_action'))
                .fontSize(15).fontColor(COLOR_PRIMARY).layoutWeight(1);
            }
            .width('100%').height(48).padding({ left: 14, right: 14 })
            .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS)
            .onClick((): void => this.reset());
            this.blurCard();
            if (this.currentIsPattern()) {
              this.patternCard();
            }
            if (this.forDark && this.chatId === 0) {
              this.darkDimCard();
            }
            GridRow({ columns: 3, gutter: 10 }) {
              ForEach(this.rows, (row: GalleryRow) => {
                GridCol({ span: 1 }) { this.tile(row); }
              }, (row: GalleryRow): string => `bg_${row.preview.backgroundId}`);
            }
            Text(this.chatId !== 0
              ? $r('app.string.cb_chat_note')
              : $r('app.string.cb_global_note'))
              .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).lineHeight(18).width('100%');
          }.width('100%').padding({ left: 12, right: 12, bottom: this.bottomSafe + 24 });
        }.layoutWeight(1).width('100%').scrollBar(BarState.Off);
      }
    }
    .width('100%').height('100%').backgroundColor(COLOR_PAGE_BG)
    .padding({ top: this.topSafe });
  }
}
