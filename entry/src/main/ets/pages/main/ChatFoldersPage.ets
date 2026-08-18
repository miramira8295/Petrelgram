import { promptAction, router } from '@kit.ArkUI';
import { TdError } from '../../tdkit/TdTypes';
import { getFolderStore } from '../../tdkit/Globals';
import { FolderInfo } from '../../store/FolderStore';
import {
  FolderChatSummary, FolderData, FolderLimits, RecommendedFolder,
  deleteFolder, folderChatCount, getFolder, getFolderChatsToLeave,
  getFolderChatSummaries, getFolderLimits, getRecommendedFolders,
  reorderFolders, saveFolder, setFolderTagsEnabled
} from '../../store/FolderApi';
import { FolderEditParams } from './FolderEditPage';
import { AvatarView } from '../chatlist/AvatarView';
import {
  KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration
} from '../../store/AppSettings';
import { folderColor, folderSymbol } from '../../util/FolderVisuals';
import {
  COLOR_DIVIDER, COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE,
  COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';
import { plural, str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { overlayBlur, overlayMaterial } from '../../util/overlayMaterial';

const CARD_RADIUS: number = 14;
const DANGER: string = '#E64646';
const ROW_HEIGHT: number = 66;
// 拖拽时一格的位移：行高 + 行间分隔线，否则累计几行后会错位。
const ROW_STEP: number = ROW_HEIGHT + 0.5;

@Entry
@Component
struct ChatFoldersPage {
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State folders: FolderInfo[] = [];
  @State counts: Map<number, number> = new Map();
  @State loading: boolean = true;
  @State loadError: boolean = false;
  @State tagsEnabled: boolean = false;
  @State operationKey: string = '';
  // 拖拽排序：-1 表示没有在拖。offset 是手指相对起点的位移。
  @State draggingIndex: number = -1;
  @State dragOffsetY: number = 0;
  @State recommendations: RecommendedFolder[] = [];
  @State recommendationState: string = 'loading';
  @State limits: FolderLimits = { folderCount: 10, chosenChatCount: 100 };
  @State deleteSheetOpen: boolean = false;
  @State deleteTargetId: number = 0;
  @State deleteTargetTitle: string = '';
  @State leaveChoices: FolderChatSummary[] = [];
  @State leaveSelected: number[] = [];
  private unsubscribe: (() => void) | null = null;
  private active: boolean = false;
  private initialTimer: number = -1;
  private countEpoch: number = 0;

  @Styles
  pressNormal() {
    .opacity(1).scale({ x: 1, y: 1 }).backgroundColor(Color.Transparent)
  }

  @Styles
  pressDown() {
    .opacity(0.7).scale({ x: 0.97, y: 0.97 }).backgroundColor($r('app.color.surface_alt'))
  }

  aboutToAppear(): void {
    this.active = true;
    if (this.unsubscribe !== null) { this.unsubscribe(); }
    const store = getFolderStore();
    this.folders = store.getFolders();
    this.tagsEnabled = store.areTagsEnabled();
    this.loading = !store.isReady();
    this.loadError = false;
    this.unsubscribe = store.subscribe((folders: FolderInfo[]): void => {
      if (!this.active) { return; }
      this.folders = folders;
      this.tagsEnabled = store.areTagsEnabled();
      if (store.isReady()) {
        this.loading = false;
        this.loadError = false;
        this.clearInitialTimer();
      }
      this.refreshCounts(folders);
    });
    if (!store.isReady()) { this.armInitialTimer(); }
    this.loadRecommendations();
    getFolderLimits().then((limits: FolderLimits): void => {
      if (this.active) { this.limits = limits; }
    });
  }

  aboutToDisappear(): void {
    this.active = false;
    this.clearInitialTimer();
    this.countEpoch++;
    if (this.unsubscribe !== null) { this.unsubscribe(); this.unsubscribe = null; }
  }

  private clearInitialTimer(): void {
    if (this.initialTimer !== -1) { clearTimeout(this.initialTimer); this.initialTimer = -1; }
  }

  private armInitialTimer(): void {
    this.clearInitialTimer();
    this.initialTimer = setTimeout((): void => {
      this.initialTimer = -1;
      if (this.active && !getFolderStore().isReady()) {
        this.loading = false;
        this.loadError = true;
      }
    }, 4000);
  }

  private retryInitial(): void {
    if (getFolderStore().isReady()) {
      this.loading = false; this.loadError = false; this.folders = getFolderStore().getFolders();
      return;
    }
    this.loading = true;
    this.loadError = false;
    this.armInitialTimer();
  }

  private refreshCounts(folders: FolderInfo[]): void {
    const epoch = ++this.countEpoch;
    const ids = folders.map((folder: FolderInfo): number => folder.id);
    const clean = new Map<number, number>();
    this.counts.forEach((value: number, id: number): void => {
      if (ids.indexOf(id) >= 0) { clean.set(id, value); }
    });
    this.counts = clean;
    for (const folder of folders) {
      getFolder(folder.id).then((data: FolderData): Promise<number> => folderChatCount(data))
        .then((count: number): void => {
          if (!this.active || epoch !== this.countEpoch) { return; }
          const next = new Map(this.counts);
          next.set(folder.id, count);
          this.counts = next;
        }).catch((error: TdError): void => {
          console.warn(`ChatFoldersPage.count(${folder.id}) failed: ${error.message}`);
        });
    }
  }

  private loadRecommendations(): void {
    this.recommendationState = 'loading';
    getRecommendedFolders().then((rows: RecommendedFolder[]): void => {
      if (!this.active) { return; }
      this.recommendations = rows;
      this.recommendationState = rows.length > 0 ? 'ready' : 'empty';
    }).catch((error: TdError): void => {
      if (!this.active) { return; }
      this.recommendationState = 'error';
      console.warn(`ChatFoldersPage.recommendations failed: ${error.message}`);
    });
  }

  private countLabel(id: number): string {
    const value = this.counts.get(id);
    return value === undefined ? str('counting') : plural('cf_about_chats', value, value);
  }

  private openEditor(id: number): void {
    if (this.operationKey !== '') { return; }
    const params: FolderEditParams = { folderId: id };
    router.pushUrl({ url: 'pages/main/FolderEditPage', params });
  }

  // 拖动中该落到第几位。四舍五入到最近的一格，并夹在合法范围内。
  private dragTargetIndex(): number {
    if (this.draggingIndex < 0) { return -1; }
    const shift = Math.round(this.dragOffsetY / ROW_STEP);
    const target = this.draggingIndex + shift;
    return Math.max(0, Math.min(this.folders.length - 1, target));
  }

  // 每一行在拖拽过程中的视觉位移：被拖的那行跟手，其余行给它让位。
  private rowOffsetY(index: number): number {
    if (this.draggingIndex < 0) { return 0; }
    if (index === this.draggingIndex) { return this.dragOffsetY; }
    const target = this.dragTargetIndex();
    if (this.draggingIndex < target && index > this.draggingIndex && index <= target) {
      return -ROW_STEP;
    }
    if (this.draggingIndex > target && index >= target && index < this.draggingIndex) {
      return ROW_STEP;
    }
    return 0;
  }

  private endDrag(): void {
    const from = this.draggingIndex;
    const to = this.dragTargetIndex();
    this.draggingIndex = -1;
    this.dragOffsetY = 0;
    if (from >= 0 && to >= 0 && from !== to) {
      this.moveFolder(from, to);
    }
  }

  private moveFolder(from: number, to: number): void {
    if (this.operationKey !== '' || from === to || from < 0 || to < 0 ||
      from >= this.folders.length || to >= this.folders.length) { return; }
    const previous = this.folders.slice();
    const next = this.folders.slice();
    const moved = next.splice(from, 1)[0];
    next.splice(to, 0, moved);
    this.folders = next;
    this.operationKey = 'reorder';
    reorderFolders(next.map((folder: FolderInfo): number => folder.id),
      getFolderStore().getMainChatListPosition()).then((): void => {
      if (this.active) { this.operationKey = ''; }
    }).catch((error: TdError): void => {
      if (!this.active) { return; }
      this.operationKey = '';
      this.folders = previous;
      getFolderStore().applyLocalOrder(previous.map((folder: FolderInfo): number => folder.id),
        getFolderStore().getMainChatListPosition());
      promptAction.showToast({ message: $r('app.string.cf_reorder_failed'), duration: 1800 });
      console.error(`ChatFoldersPage.reorder failed: ${error.message}`);
    });
  }

  private toggleTags(next: boolean): void {
    if (this.operationKey !== '') { return; }
    const previous = this.tagsEnabled;
    this.tagsEnabled = next;
    this.operationKey = 'tags';
    setFolderTagsEnabled(next).then((): void => {
      if (this.active) { this.operationKey = ''; }
    }).catch((error: TdError): void => {
      if (!this.active) { return; }
      this.tagsEnabled = previous;
      this.operationKey = '';
      promptAction.showToast({ message: $r('app.string.cf_tags_failed'), duration: 1800 });
      console.error(`ChatFoldersPage.tags failed: ${error.message}`);
    });
  }

  private prepareDelete(folder: FolderInfo): void {
    if (this.operationKey !== '') { return; }
    this.operationKey = `delete_prepare_${folder.id}`;
    getFolderChatsToLeave(folder.id).then((ids: number[]): Promise<FolderChatSummary[]> => {
      if (ids.length === 0) { return Promise.resolve([]); }
      return getFolderChatSummaries(ids);
    }).then((rows: FolderChatSummary[]): void => {
      if (!this.active) { return; }
      this.operationKey = '';
      if (rows.length === 0) {
        this.confirmSimpleDelete(folder);
      } else {
        this.deleteTargetId = folder.id;
        this.deleteTargetTitle = folder.title;
        this.leaveChoices = rows;
        this.leaveSelected = [];
        this.deleteSheetOpen = true;
      }
    }).catch((error: TdError): void => {
      if (!this.active) { return; }
      this.operationKey = '';
      // Failure to calculate optional leave choices must not make the folder
      // impossible to remove; default to keeping all chats.
      console.warn(`ChatFoldersPage.getChatsToLeave failed: ${error.message}`);
      this.confirmSimpleDelete(folder);
    });
  }

  private confirmSimpleDelete(folder: FolderInfo): void {
    promptAction.showDialog({
      title: $r('app.string.cf_delete'),
      message: str('cf_delete_confirm', folder.title),
      buttons: [
        { text: $r('app.string.cancel'), color: COLOR_TEXT_SECONDARY as string },
        { text: $r('app.string.delete'), color: DANGER }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse): void => {
      if (result.index === 1) { this.deleteNow(folder.id, []); }
    }).catch((): void => {});
  }

  private toggleLeave(id: number): void {
    this.leaveSelected = this.leaveSelected.indexOf(id) >= 0
      ? this.leaveSelected.filter((value: number): boolean => value !== id)
      : [...this.leaveSelected, id];
  }

  private deleteNow(id: number, leaveIds: number[]): void {
    if (this.operationKey !== '') { return; }
    this.operationKey = `delete_${id}`;
    deleteFolder(id, leaveIds).then((): void => {
      if (!this.active) { return; }
      this.operationKey = '';
      this.deleteSheetOpen = false;
      promptAction.showToast({ message: $r('app.string.cf_deleted'), duration: 1500 });
    }).catch((error: TdError): void => {
      if (!this.active) { return; }
      this.operationKey = '';
      promptAction.showToast({ message: $r('app.string.delete_failed_retry'), duration: 1800 });
      console.error(`ChatFoldersPage.delete failed: ${error.message}`);
    });
  }

  private addRecommendation(index: number): void {
    if (this.operationKey !== '' || index < 0 || index >= this.recommendations.length ||
      this.folders.length >= this.limits.folderCount) { return; }
    const template = this.recommendations[index].folder;
    this.operationKey = `recommend_${index}`;
    const next: FolderData = {
      id: 0, name: template.name, nameEntities: template.nameEntities.slice(),
      animateCustomEmoji: template.animateCustomEmoji, iconName: template.iconName,
      colorId: template.colorId, isShareable: false,
      pinnedChatIds: template.pinnedChatIds.slice(), includedChatIds: template.includedChatIds.slice(),
      excludedChatIds: template.excludedChatIds.slice(), excludeMuted: template.excludeMuted,
      excludeRead: template.excludeRead, excludeArchived: template.excludeArchived,
      includeContacts: template.includeContacts, includeNonContacts: template.includeNonContacts,
      includeBots: template.includeBots, includeGroups: template.includeGroups,
      includeChannels: template.includeChannels
    };
    saveFolder(next).then((): void => {
      if (!this.active) { return; }
      this.operationKey = '';
      promptAction.showToast({ message: str('cf_created', next.name), duration: 1600 });
    }).catch((error: TdError): void => {
      if (!this.active) { return; }
      this.operationKey = '';
      promptAction.showToast({ message: $r('app.string.create_failed_retry'), duration: 1800 });
      console.error(`ChatFoldersPage.addRecommendation failed: ${error.message}`);
    });
  }

  @Builder
  header() {
    Row({ space: 6 }) {
      Row() { SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(25).fontColor([COLOR_TEXT_PRIMARY]); }
        .width(44).height(44).borderRadius(22).justifyContent(FlexAlign.Center)
        .stateStyles({ normal: this.pressNormal, pressed: this.pressDown })
        .onClick((): void => router.back());
      Column({ space: 1 }) {
        Text($r('app.string.settings_folders')).fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
        Text(this.loading ? $r('app.string.syncing') : str('cf_folder_quota', this.folders.length, this.limits.folderCount))
          .fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      if (this.operationKey !== '') {
        LoadingProgress().width(19).height(19).color(COLOR_PRIMARY).margin({ right: 13 });
      }
    }.width('100%').height(56).padding({ left: 8, right: 8 }).alignItems(VerticalAlign.Center);
  }

  @Builder
  skeleton() {
    Column({ space: 12 }) {
      ForEach([0, 1, 2], (skeletonIndex: number) => {
        Row({ space: 12 }) {
          Row().width(42).height(42).borderRadius(14).backgroundColor($r('app.color.surface_alt'));
          Column({ space: 8 }) {
            Row().width('46%').height(13).borderRadius(7).backgroundColor($r('app.color.surface_alt'));
            Row().width('30%').height(10).borderRadius(5).backgroundColor($r('app.color.surface_alt'));
          }.layoutWeight(1).alignItems(HorizontalAlign.Start);
        }.height(66).padding({ left: 14, right: 14 }).backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
      }, (skeletonIndex: number): string => `folder_skeleton_${skeletonIndex}`);
    }.padding({ left: 12, right: 12, top: 12 });
  }

  @Builder
  errorState() {
    Column({ space: 12 }) {
      Text('📁').fontSize(44);
      Text($r('app.string.cf_sync_failed')).fontSize(18).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
      Text($r('app.string.cf_sync_failed_sub')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
      Text($r('app.string.settings_reload')).fontSize(15).fontColor(Color.White).fontWeight(FontWeight.Medium)
        .padding({ left: 22, right: 22, top: 10, bottom: 10 })
        .backgroundColor(COLOR_PRIMARY).borderRadius(18)
        .stateStyles({ normal: this.pressNormal, pressed: this.pressDown })
        .onClick((): void => this.retryInitial());
    }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
  }

  @Builder
  // 不加彩色底块：前景和底色同色只差透明度，对比度低、看着发糊，42×42 的方块
  // 在 66 高的行里也过重。这里只留单色图标，把视觉重量让给标题、"共享"标签
  // 和右侧的拖拽手柄。颜色仍来自文件夹自身的 colorId，辨识度不丢。
  folderIcon(folder: FolderInfo) {
    Row() {
      SymbolGlyph(folderSymbol(folder.iconName)).fontSize(24)
        .fontColor([folderColor(folder.colorId)]);
    }.width(30).height(30).justifyContent(FlexAlign.Center);
  }

  @Builder
  folderMenu(folder: FolderInfo, index: number) {
    Menu() {
      MenuItem({ content: $r('app.string.cf_edit') }).onClick((): void => this.openEditor(folder.id));
      MenuItem({ content: $r('app.string.move_up') }).enabled(index > 0)
        .onClick((): void => this.moveFolder(index, index - 1));
      MenuItem({ content: $r('app.string.move_down') }).enabled(index < this.folders.length - 1)
        .onClick((): void => this.moveFolder(index, index + 1));
      MenuItem({ content: $r('app.string.cf_delete') }).onClick((): void => this.prepareDelete(folder));
    }
  }

  @Builder
  folderRow(folder: FolderInfo, index: number) {
    Row({ space: 12 }) {
      this.folderIcon(folder);
      Column({ space: 3 }) {
        Row({ space: 6 }) {
          Text(folder.title).fontSize(16).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
          if (folder.isShareable) {
            Text($r('app.string.share')).fontSize(10).fontColor(COLOR_PRIMARY)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor('#185B8FF9').borderRadius(7);
          }
        }
        Text(this.countLabel(folder.id)).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
      }.layoutWeight(1).alignItems(HorizontalAlign.Start).onClick((): void => this.openEditor(folder.id));
      Row() { SymbolGlyph($r('sys.symbol.line_3_horizontal')).fontSize(19).fontColor([COLOR_TEXT_SECONDARY]); }
        .width(40).height(40).borderRadius(20).justifyContent(FlexAlign.Center)
        .stateStyles({ normal: this.pressNormal, pressed: this.pressDown })
        .bindMenu(this.folderMenu(folder, index), { systemMaterial: overlayMaterial('menu') });
    }.width('100%').height(ROW_HEIGHT).padding({ left: 16, right: 8 })
      .alignItems(VerticalAlign.Center)
      .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -5 }))
        .animation({ duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180), curve: Curve.EaseOut }));
  }

  @Builder
  folderCard() {
    Column() {
      Row({ space: 12 }) {
        Row() { Text('💬').fontSize(20); }.width(42).height(42).borderRadius(14)
          .justifyContent(FlexAlign.Center).backgroundColor($r('app.color.surface_alt'));
        Column({ space: 2 }) {
          Text($r('app.string.cf_all_chats')).fontSize(16).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
          Text($r('app.string.cf_default_list')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
        }.layoutWeight(1).alignItems(HorizontalAlign.Start);
        Text($r('app.string.cf_default')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
      }.width('100%').height(ROW_HEIGHT).padding({ left: 14, right: 14 });
      ForEach(this.folders, (folder: FolderInfo, index: number) => {
        Divider().strokeWidth(0.5).color(COLOR_DIVIDER).margin({ left: 68 });
        Column() {
          this.folderRow(folder, index);
        }
        .width('100%')
        .translate({ y: this.rowOffsetY(index) })
        // 被拖的一行浮在其它行之上，并给一点抬起感。
        .zIndex(this.draggingIndex === index ? 2 : 1)
        .scale(this.draggingIndex === index
          ? { x: 1.02, y: 1.02 } : { x: 1, y: 1 })
        .shadow(this.draggingIndex === index
          ? { radius: 12, color: '#22000000', offsetX: 0, offsetY: 4 }
          : { radius: 0, color: Color.Transparent, offsetX: 0, offsetY: 0 })
        .backgroundColor(this.draggingIndex === index
          ? $r('app.color.surface') : Color.Transparent)
        // 让位动画只作用于没被拖的行，被拖那行必须跟手、不能有插值延迟。
        .animation(this.draggingIndex === index
          ? undefined
          : { duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 160), curve: Curve.EaseOut })
        .gesture(
          // Sequence：先长按确认意图，再进入拖动，避免和点击/滚动抢手势。
          GestureGroup(GestureMode.Sequence,
            LongPressGesture({ repeat: false, duration: 300 })
              .onAction((): void => {
                if (this.operationKey !== '') { return; }
                this.draggingIndex = index;
                this.dragOffsetY = 0;
              }),
            PanGesture({ direction: PanDirection.Vertical })
              .onActionUpdate((event: GestureEvent): void => {
                if (this.draggingIndex === index) { this.dragOffsetY = event.offsetY; }
              })
              .onActionEnd((): void => {
                if (this.draggingIndex === index) { this.endDrag(); }
              })
              .onActionCancel((): void => {
                if (this.draggingIndex === index) { this.endDrag(); }
              })
          )
        );
      }, (folder: FolderInfo): string => `folder_${folder.id}`);
      Divider().strokeWidth(0.5).color(COLOR_DIVIDER).margin({ left: 14 });
      Row({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.plus_circle')).fontSize(20).fontColor([COLOR_PRIMARY]);
        Text(this.folders.length >= this.limits.folderCount ? $r('app.string.cf_limit_reached') : $r('app.string.cf_create'))
          .fontSize(16).fontColor(this.folders.length >= this.limits.folderCount ? COLOR_TEXT_SECONDARY : COLOR_PRIMARY)
          .layoutWeight(1);
      }.width('100%').height(54).padding({ left: 16, right: 16 })
        .stateStyles({ normal: this.pressNormal, pressed: this.pressDown })
        .enabled(this.folders.length < this.limits.folderCount && this.operationKey === '')
        .onClick((): void => this.openEditor(0));
    }.width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS).clip(true);
  }

  @Builder
  tagsCard() {
    Row({ space: 12 }) {
      Row() { Text('🏷️').fontSize(20); }.width(42).height(42).borderRadius(14)
        .justifyContent(FlexAlign.Center).backgroundColor('#169270CA');
      Column({ space: 3 }) {
        Text($r('app.string.cf_tags')).fontSize(16).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
        Text($r('app.string.cf_tags_sub')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      Toggle({ type: ToggleType.Switch, isOn: this.tagsEnabled }).selectedColor(COLOR_PRIMARY)
        .enabled(this.operationKey === '')
        .onChange((value: boolean): void => this.toggleTags(value));
    }.width('100%').padding(14).backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
  }

  @Builder
  recommendedCard(row: RecommendedFolder, index: number) {
    Row({ space: 12 }) {
      Row() {
        SymbolGlyph(folderSymbol(row.folder.iconName)).fontSize(21).fontColor(['#5B8FF9']);
      }.width(42).height(42).borderRadius(14)
        .justifyContent(FlexAlign.Center).backgroundColor('#165B8FF9');
      Column({ space: 3 }) {
        Text(row.folder.name).fontSize(16).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
        Text(row.description).fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis });
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      if (this.operationKey === `recommend_${index}`) {
        LoadingProgress().width(18).height(18).color(COLOR_PRIMARY);
      } else {
        Text($r('app.string.add')).fontSize(14).fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Medium)
          .padding({ left: 12, right: 12, top: 7, bottom: 7 }).borderRadius(14)
          .backgroundColor('#145B8FF9').stateStyles({ normal: this.pressNormal, pressed: this.pressDown })
          .onClick((): void => this.addRecommendation(index));
      }
    }.width('100%').padding(14).backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
  }

  @Builder
  content() {
    Scroll() {
      Column({ space: 14 }) {
        Text($r('app.string.cf_note'))
          .fontSize(13).fontColor(COLOR_TEXT_SECONDARY).width('100%')
          .textAlign(TextAlign.Center).padding({ left: 18, right: 18, top: 2 });
        this.folderCard();
        this.tagsCard();
        if (this.folders.length === 0) {
          Column({ space: 5 }) {
            Text($r('app.string.cf_empty')).fontSize(16).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
            Text($r('app.string.cf_empty_sub'))
              .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).textAlign(TextAlign.Center);
          }.width('100%').padding({ top: 8, bottom: 2 });
        }
        if (this.recommendationState === 'ready') {
          Text($r('app.string.cf_suggested')).fontSize(14).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_SECONDARY)
            .width('100%').padding({ left: 4, top: 2 });
          ForEach(this.recommendations, (row: RecommendedFolder, index: number) => {
            if (!this.folders.some((folder: FolderInfo): boolean => folder.title === row.folder.name)) {
              this.recommendedCard(row, index);
            }
          }, (row: RecommendedFolder, index: number): string => `recommended_${index}_${row.folder.name}`);
        } else if (this.recommendationState === 'error') {
          Row({ space: 8 }) {
            Text($r('app.string.cf_suggested_failed')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY).layoutWeight(1);
            Text($r('app.string.settings_retry')).fontSize(13).fontColor(COLOR_PRIMARY).onClick((): void => this.loadRecommendations());
          }.width('100%').padding(14).backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
        }
      }.width('100%').padding({ left: 12, right: 12, top: 6, bottom: this.bottomSafe + 24 });
    }.layoutWeight(1).width('100%').scrollBar(BarState.Off).align(Alignment.Top);
  }

  @Builder
  leaveSheet() {
    Column() {
      Text($r('app.string.cf_delete')).fontSize(19).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .padding({ top: 14, bottom: 4 });
      Text(str('cf_delete_note', this.deleteTargetTitle))
        .fontSize(13).fontColor(COLOR_TEXT_SECONDARY).textAlign(TextAlign.Center)
        .padding({ left: 24, right: 24, bottom: 8 });
      List() {
        ForEach(this.leaveChoices, (chat: FolderChatSummary) => {
          ListItem() {
            Row({ space: 12 }) {
              AvatarView({ avatarPath: chat.avatarPath, initials: chat.initials, colorSeed: chat.id, avatarSize: 38 });
              Text(chat.title).fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
              Toggle({ type: ToggleType.Checkbox, isOn: this.leaveSelected.indexOf(chat.id) >= 0 })
                .selectedColor(DANGER).onChange((): void => this.toggleLeave(chat.id));
            }.width('100%').padding({ left: 16, right: 16, top: 8, bottom: 8 });
          }
        }, (chat: FolderChatSummary): string => `leave_${chat.id}`);
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off);
      Text(this.leaveSelected.length > 0 ? plural('cf_delete_and_leave', this.leaveSelected.length, this.leaveSelected.length) : $r('app.string.cf_delete_only'))
        .fontSize(16).fontWeight(FontWeight.Medium).fontColor(Color.White).textAlign(TextAlign.Center)
        .width('100%').padding({ top: 12, bottom: 12 }).backgroundColor(DANGER).borderRadius(12)
        .margin({ left: 16, right: 16, top: 8, bottom: this.bottomSafe + 10 })
        .onClick((): void => this.deleteNow(this.deleteTargetId, this.leaveSelected));
    }.width('100%').height('100%');
  }

  build() {
    Column() {
      this.header();
      if (this.loading) { this.skeleton(); }
      else if (this.loadError) { this.errorState(); }
      else { this.content(); }
    }.width('100%').height('100%').backgroundColor(COLOR_PAGE_BG)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .padding({ top: this.topSafe })
      .bindSheet($$this.deleteSheetOpen, this.leaveSheet(), {
        height: '72%', backgroundColor: COLOR_SURFACE, dragBar: true, blurStyle: overlayBlur('dialog'), systemMaterial: overlayMaterial('dialog')
      });
  }
}
