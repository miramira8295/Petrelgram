import { router, promptAction } from '@kit.ArkUI';
import {
  DetailedStorageUsage, StorageCategory, ChatStorageUsage, formatBytes,
  getDetailedStorageUsage, clearCacheSelection
} from '../../store/StorageApi';
import { getChatStore } from '../../tdkit/Globals';
import { ChatEntry } from '../../store/ChatEntry';
import { TdError } from '../../tdkit/TdTypes';
import {
  COLOR_DIVIDER, COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE,
  COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY, COLOR_ON_PRIMARY
} from '../../util/theme';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import { plural, str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { logE } from '../../util/log';
import { readableContentWidth } from '../../util/contentWidth';
import { KeyedListDataSource } from '../common/KeyedListDataSource';
import { guardKey } from '../../util/keyGuard';

const CARD_RADIUS: number = 14;
const DANGER: string = '#E64646';
const SIDE_PADDING: number = 12;

// 按会话占用的一行显示数据：标题 / 缩写在同步时向 ChatStore 解析好。
interface StorageChatItem {
  chatId: number;
  title: string;
  initials: string;
  size: number;
  count: number;
}

function storageChatKey(item: StorageChatItem): string {
  return `${item.chatId}_${item.size}_${item.count}_${item.title}_${item.initials}`;
}

@Entry
@Component
struct StorageUsagePage {
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  // 窗口宽（不是屏幕宽），限宽用。平板上把一列拉满 2880px 眼睛要横扫一行。
  @StorageProp('screenWidthVp') screenW: number = 360;
  @State @Watch('syncChatsData') usage: DetailedStorageUsage | null = null;
  @State loading: boolean = true;
  @State refreshing: boolean = false;
  @State loadError: string = '';
  @State syncWarning: string = '';
  @State actionKey: string = '';
  private active: boolean = false;
  private sequence: number = 0;
  // 按会话那张卡的 LazyForEach 数据源（见 syncChatsData）。
  private chatsData: KeyedListDataSource<StorageChatItem> = new KeyedListDataSource<StorageChatItem>('storage-chats');

  @Styles
  actionNormalStyle() {
    .backgroundColor(Color.Transparent).opacity(1).scale({ x: 1, y: 1 })
  }

  @Styles
  actionPressedStyle() {
    .backgroundColor($r('app.color.surface_alt')).opacity(0.74).scale({ x: 0.94, y: 0.94 })
  }

  @Styles
  rowNormalStyle() {
    .backgroundColor(COLOR_SURFACE).scale({ x: 1, y: 1 })
  }

  @Styles
  rowPressedStyle() {
    .backgroundColor($r('app.color.surface_alt')).scale({ x: 0.99, y: 0.99 })
  }

  aboutToAppear(): void {
    this.active = true;
    this.load(true);
  }

  aboutToDisappear(): void {
    this.active = false;
    this.sequence++;
  }

  private duration(value: number): number {
    return powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, value);
  }

  private load(initial: boolean): void {
    const current = ++this.sequence;
    if (initial && this.usage === null) { this.loading = true; this.loadError = ''; }
    else { this.refreshing = true; this.syncWarning = ''; }
    getDetailedStorageUsage(30).then((value: DetailedStorageUsage): void => {
      if (!this.active || current !== this.sequence) { return; }
      this.usage = value;
      this.loading = false;
      this.refreshing = false;
      this.loadError = '';
      this.syncWarning = '';
    }).catch((error: TdError): void => {
      if (!this.active || current !== this.sequence) { return; }
      this.loading = false;
      this.refreshing = false;
      if (this.usage === null) { this.loadError = str('storage_unreadable'); }
      else { this.syncWarning = str('storage_refresh_failed'); }
      logE(`StorageUsagePage.load failed: ${error.message}`);
    });
  }

  private titleOf(chatId: number): string {
    if (chatId === 0) { return str('storage_other_chats'); }
    const entry: ChatEntry | undefined = getChatStore().entryOf(chatId);
    return entry !== undefined && entry.title !== '' ? entry.title : str('storage_untitled_chat');
  }

  private initialsOf(chatId: number): string {
    if (chatId === 0) { return str('storage_other_initials'); }
    const entry: ChatEntry | undefined = getChatStore().entryOf(chatId);
    return entry !== undefined ? entry.initials : '?';
  }

  // 占用数据换了（加载、清理后刷新）：交给 LazyForEach。
  private syncChatsData(): void {
    const chats: ChatStorageUsage[] = this.usage !== null ? this.usage.chats : [];
    const items: StorageChatItem[] = chats.map((c: ChatStorageUsage): StorageChatItem => {
      const item: StorageChatItem = {
        chatId: c.chatId, title: this.titleOf(c.chatId), initials: this.initialsOf(c.chatId),
        size: c.size, count: c.count
      };
      return item;
    });
    this.chatsData.update(items,
      items.map((i: StorageChatItem): string => `${i.chatId}`),
      items.map((i: StorageChatItem): string => storageChatKey(i)));
  }

  // 卡片最宽 = 可读宽度减去 List 两侧内边距（原来是限宽内容列里再留 12）。
  private cardMaxWidth(): number {
    return readableContentWidth(this.screenW) - SIDE_PADDING * 2;
  }

  private share(size: number): number {
    const total = this.usage !== null ? this.usage.size : 0;
    return total > 0 ? Math.max(0.02, Math.min(1, size / total)) : 0;
  }

  private confirmClear(key: string, title: string, message: string,
    category: string, chatId: number): void {
    if (this.actionKey !== '') { return; }
    promptAction.showDialog({
      title, message,
      buttons: [
        { text: $r('app.string.cancel'), color: COLOR_TEXT_SECONDARY as string },
        { text: $r('app.string.clear'), color: DANGER }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse): void => {
      if (result.index !== 1 || this.actionKey !== '') { return; }
      this.actionKey = key;
      clearCacheSelection(category, chatId).then((): void => {
        this.actionKey = '';
        promptAction.showToast({ message: $r('app.string.storage_clear_done'), duration: 1500 });
        this.load(false);
      }).catch((error: TdError): void => {
        this.actionKey = '';
        logE(`StorageUsagePage.clear failed: ${error.message}`);
        promptAction.showToast({ message: $r('app.string.clear_failed_retry'), duration: 1700 });
      });
    });
  }

  @Builder
  header() {
    Row({ space: 8 }) {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(25).fontColor([COLOR_TEXT_PRIMARY]);
      }.width(44).height(44).borderRadius(22).justifyContent(FlexAlign.Center)
      .stateStyles({ normal: this.actionNormalStyle, pressed: this.actionPressedStyle })
      .onClick((): void => router.back());
      Text($r('app.string.storage_title')).fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .layoutWeight(1);
      Row() {
        if (this.refreshing) { LoadingProgress().width(18).height(18).color(COLOR_PRIMARY); }
        else { SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(20).fontColor([COLOR_PRIMARY]); }
      }.width(44).height(44).borderRadius(22).justifyContent(FlexAlign.Center)
      .enabled(!this.loading && !this.refreshing && this.actionKey === '')
      .stateStyles({ normal: this.actionNormalStyle, pressed: this.actionPressedStyle })
      .onClick((): void => this.load(false));
    }.width('100%').height(56).padding({ left: 8, right: 8 }).alignItems(VerticalAlign.Center);
  }

  @Builder
  loadingState() {
    Column({ space: 12 }) {
      LoadingProgress().width(34).height(34).color(COLOR_PRIMARY);
      Text($r('app.string.storage_loading')).fontSize(15).fontColor(COLOR_TEXT_PRIMARY);
      Text($r('app.string.storage_loading_sub')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
    }.width('100%').padding({ top: 72, bottom: 72 }).backgroundColor(COLOR_SURFACE)
      .borderRadius(CARD_RADIUS);
  }

  @Builder
  errorState() {
    Column({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle')).fontSize(34).fontColor([DANGER]);
      Text($r('app.string.storage_load_failed')).fontSize(18).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
      Text(this.loadError).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
      Text($r('app.string.settings_reload')).fontSize(14).fontColor(COLOR_ON_PRIMARY).padding({ left: 17, right: 17, top: 10, bottom: 10 })
        .backgroundColor(COLOR_PRIMARY).borderRadius(20).onClick((): void => this.load(true));
    }.width('100%').padding({ top: 54, bottom: 54 }).backgroundColor(COLOR_SURFACE)
      .borderRadius(CARD_RADIUS);
  }

  @Builder
  summaryCard() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 3 }) {
          Text($r('app.string.storage_clearable')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
          Text(this.usage !== null ? formatBytes(this.usage.size) : '—')
            .fontSize(30).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
        }.layoutWeight(1).alignItems(HorizontalAlign.Start);
        Text(this.usage !== null ? plural('storage_file_count', this.usage.count, this.usage.count) : '')
          .fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
      }.width('100%');
      Text($r('app.string.storage_note'))
        .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).width('100%');
    }.width('100%').padding(16).backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
  }

  @Builder
  categoryRow(item: StorageCategory) {
    Column({ space: 7 }) {
      Row() {
        Text(item.label).fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
        if (this.actionKey === `category_${item.key}`) {
          LoadingProgress().width(17).height(17).color(COLOR_PRIMARY).margin({ right: 10 });
        }
        Text(formatBytes(item.size)).fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
        Text($r('app.string.clear')).fontSize(13).fontColor(COLOR_PRIMARY).margin({ left: 12 });
      }.width('100%');
      Stack({ alignContent: Alignment.Start }) {
        Row().width('100%').height(5).borderRadius(3).backgroundColor($r('app.color.surface_alt'));
        Row().width(`${Math.round(this.share(item.size) * 100)}%`).height(5).borderRadius(3)
          .backgroundColor(COLOR_PRIMARY);
      }.width('100%').height(5);
      Text(plural('storage_file_count', item.count, item.count)).fontSize(11).fontColor(COLOR_TEXT_SECONDARY).width('100%');
    }
    .width('100%').padding({ left: 14, right: 14, top: 11, bottom: 11 })
    .enabled(this.actionKey === '')
    .stateStyles({ normal: this.rowNormalStyle, pressed: this.rowPressedStyle })
    .onClick((): void => this.confirmClear(`category_${item.key}`, str('storage_clear_category', item.label),
      str('storage_clear_category_confirm', formatBytes(item.size), item.label), item.key, 0));
  }

  @Builder
  categoriesCard() {
    Column() {
      Text($r('app.string.network_by_type')).fontSize(14).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY)
        .width('100%').padding({ left: 14, right: 14, top: 12, bottom: 6 });
      if (this.usage !== null) {
        ForEach(this.usage.categories, (item: StorageCategory, index: number) => {
          if (index > 0) { Divider().strokeWidth(0.5).color(COLOR_DIVIDER).margin({ left: 14 }); }
          this.categoryRow(item);
        }, (item: StorageCategory): string => item.key);
      }
    }.width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS).clip(true);
  }

  @Builder
  chatsHeader() {
    Text($r('app.string.storage_by_chat')).fontSize(14).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY)
      .width('100%').padding({ left: 14, right: 14, top: 12, bottom: 6 });
  }

  // 按会话占用：ListItemGroup + LazyForEach + 复用行（StorageChatRow）。分隔线交给组的
  // divider：原来按 index > 0 在行内插 Divider，LazyForEach 下删掉第一行后，新的第一行
  // 沿用旧节点，顶上会多一条线。点击、禁用、按压态挂在 ListItem 上，闭包随行 key 重建。
  @Builder
  chatsCard() {
    ListItemGroup({ header: this.chatsHeader() }) {
      LazyForEach(this.chatsData, (item: StorageChatItem) => {
        ListItem() {
          StorageChatRow({
            title: item.title, initials: item.initials, sizeBytes: item.size, fileCount: item.count,
            busy: this.actionKey === `chat_${item.chatId}`
          });
        }
        .enabled(this.actionKey === '' && item.chatId !== 0)
        .opacity(item.chatId === 0 ? 0.72 : 1)
        .stateStyles({ normal: this.rowNormalStyle, pressed: this.rowPressedStyle })
        .onClick((): void => {
          if (item.chatId !== 0) {
            this.confirmClear(`chat_${item.chatId}`, str('storage_clear_chat', item.title),
              str('storage_clear_chat_confirm', formatBytes(item.size)), '', item.chatId);
          }
        });
      }, (item: StorageChatItem, index: number): string =>
        guardKey(this.chatsData.keyTableId, index, storageChatKey(item)));
    }
    .divider({ strokeWidth: 0.5, color: COLOR_DIVIDER, startMargin: 62 })
    .width('100%').constraintSize({ maxWidth: this.cardMaxWidth() })
    .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS).clip(true);
  }

  @Builder
  emptyState() {
    Column({ space: 9 }) {
      SymbolGlyph($r('sys.symbol.checkmark_circle')).fontSize(38).fontColor([COLOR_PRIMARY]);
      Text($r('app.string.storage_empty')).fontSize(18).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
      Text($r('app.string.storage_empty_sub'))
        .fontSize(13).fontColor(COLOR_TEXT_SECONDARY).textAlign(TextAlign.Center);
    }.width('100%').padding({ top: 52, bottom: 52 }).backgroundColor(COLOR_SURFACE)
      .borderRadius(CARD_RADIUS);
  }

  build() {
    Column() {
      this.header();
      // 每张卡片占一项，按会话那张是 ListItemGroup（见 chatsCard）。限宽改由每一项自己的
      // constraintSize + alignListItem 居中：List 仍铺满窗口，边缘回弹不跟着缩进来，侧边
      // 留白也还在它的命中区里。分类占比条按父宽的百分比算，跟着卡片一起收窄。
      List({ space: 12 }) {
        if (this.syncWarning !== '') {
          ListItem() {
            Text(this.syncWarning).fontSize(12).fontColor('#FF9500').width('100%')
              .padding(10).backgroundColor('#12FF9500').borderRadius(10);
          }
          .width('100%').constraintSize({ maxWidth: this.cardMaxWidth() });
        }
        if (this.loading && this.usage === null) {
          ListItem() {
            this.loadingState();
          }
          .width('100%').constraintSize({ maxWidth: this.cardMaxWidth() });
        } else if (this.loadError !== '' && this.usage === null) {
          ListItem() {
            this.errorState();
          }
          .width('100%').constraintSize({ maxWidth: this.cardMaxWidth() });
        } else if (this.usage !== null && this.usage.size <= 0) {
          ListItem() {
            this.emptyState();
          }
          .width('100%').constraintSize({ maxWidth: this.cardMaxWidth() });
        } else if (this.usage !== null) {
          ListItem() {
            this.summaryCard();
          }
          .width('100%').constraintSize({ maxWidth: this.cardMaxWidth() });
          if (this.usage.categories.length > 0) {
            ListItem() {
              this.categoriesCard();
            }
            .width('100%').constraintSize({ maxWidth: this.cardMaxWidth() });
          }
          if (this.usage.chats.length > 0) {
            this.chatsCard();
          }
        }
      }
      .layoutWeight(1).width('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
      .cachedCount(4)
      .alignListItem(ListItemAlign.Center)
      .padding({ left: SIDE_PADDING, right: SIDE_PADDING })
      // 上下留白原来是内容列的 padding（随内容滚动），在 List 上对应两个 contentOffset。
      .contentStartOffset(6)
      .contentEndOffset(this.bottomSafe + 24);
    }.width('100%').height('100%').backgroundColor(COLOR_PAGE_BG)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .padding({ top: this.topSafe });
  }
}

// 按会话占用的一行（原 chatRow）。复用组件；只画，交互在页面的 ListItem 上。
@Reusable
@Component
struct StorageChatRow {
  @Prop title: string = '';
  @Prop initials: string = '';
  @Prop sizeBytes: number = 0;
  @Prop fileCount: number = 0;
  @Prop busy: boolean = false;

  build() {
    Row({ space: 11 }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle({ width: 40, height: 40 }).fill('#173478F6');
        Text(this.initials).fontSize(16).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY);
      }
      Column({ space: 3 }) {
        Text(this.title).fontSize(15).fontColor(COLOR_TEXT_PRIMARY).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(plural('storage_file_count', this.fileCount, this.fileCount)).fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      if (this.busy) {
        LoadingProgress().width(17).height(17).color(COLOR_PRIMARY);
      } else {
        Text(formatBytes(this.sizeBytes)).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
      }
    }
    .width('100%').height(62).padding({ left: 12, right: 14 });
  }
}
