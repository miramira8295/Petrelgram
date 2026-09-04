import { router, promptAction } from '@kit.ArkUI';
import { TdError } from '../../tdkit/TdTypes';
import {
  StorageUsage, NetworkUsage, formatBytes, getStorageUsage, clearCache,
  getNetworkUsage, resetNetworkUsage, clearAllDrafts,
  prepareAutosaveSettings, syncAutosaveSettings, applyCacheLimit
} from '../../store/StorageApi';
import {
  KEY_CACHE_LIMIT, powerAnimationDuration,
  KEY_POWER_SMOOTH_TRANSITIONS,
  setBoolean, setNumber,
  KEY_AUTOSAVE_PRIVATE, KEY_AUTOSAVE_GROUP, KEY_AUTOSAVE_CHANNEL
} from '../../store/AppSettings';
import {
  CACHE_LIMIT_OPTIONS, CACHE_LIMIT_UNLIMITED, CACHE_LIMIT_DEFAULT
} from '../../store/CacheLimit';
import {
  COLOR_DIVIDER, COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE,
  COLOR_TEXT_PRIMARY, COLOR_ICON_SECONDARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';
import { plural, str } from '../../util/strings';
import { fullDate } from '../../util/intlFormat';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { logE, logW } from '../../util/log';
import { HdsSubDestination } from '../common/HdsSubDestination';
import { changeDownloadDirectory, getDownloadDirectoryPath } from '../../util/mediaSaver';
import { common } from '@kit.AbilityKit';

const CARD_RADIUS: number = 14;
const DANGER: string = '#E64646';
const SKELETON_ROWS: number[] = [0, 1, 2];

// 路由表（router_map.json）的 buildFunction 指向这里。系统在跳转时动态加载
// 本模块并调用它，页面因此不再进 main_pages.json——一个页面不能同时是 router
// 页和 NavDestination。形状与 PowerUsagePageBuilder 一致。
@Builder
export function DataStoragePageBuilder(): void {
  DataStoragePage();
}

@Component
export struct DataStoragePage {
  private hdsScroller: Scroller = new Scroller();
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @StorageProp(KEY_CACHE_LIMIT) cacheLimit: number = CACHE_LIMIT_DEFAULT;
  @State storage: StorageUsage | null = null;
  @State network: NetworkUsage | null = null;
  @State storageLoading: boolean = true;
  @State networkLoading: boolean = true;
  @State storageError: string = '';
  @State networkError: string = '';
  @State syncWarning: string = '';
  @State actionKey: string = '';
  @State skeletonBright: boolean = false;
  @State autosavePrivate: boolean = false;
  @State autosaveGroup: boolean = false;
  @State autosaveChannel: boolean = false;
  @State autosaveSyncing: boolean = false;
  @State autosaveWarning: string = '';
  @State downloadPath: string = '';
  @State changingDownloadPath: boolean = false;
  private active: boolean = false;
  private loadSequence: number = 0;
  private lastLoadAt: number = 0;
  private skeletonTimer: number = -1;
  private autosaveSyncSequence: number = 0;
  private autosavePrepared: boolean = false;

  @Styles
  actionNormalStyle() {
    .backgroundColor(Color.Transparent)
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  actionPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.76)
    .scale({ x: 0.94, y: 0.94 })
  }

  @Styles
  rowNormalStyle() {
    .backgroundColor(COLOR_SURFACE)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  rowPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .scale({ x: 0.99, y: 0.99 })
  }

  aboutToAppear(): void {
    this.active = true;
    this.autosavePrivate = AppStorage.get<boolean>(KEY_AUTOSAVE_PRIVATE) ?? false;
    this.autosaveGroup = AppStorage.get<boolean>(KEY_AUTOSAVE_GROUP) ?? false;
    this.autosaveChannel = AppStorage.get<boolean>(KEY_AUTOSAVE_CHANNEL) ?? false;
    this.refreshDownloadPath();
    this.load(true);
    prepareAutosaveSettings().then((): void => {
      this.autosavePrepared = true;
    }).catch((error: TdError): void => {
      logW(`DataStoragePage.prepareAutosave failed: ${error.message}`);
      if (this.active) { this.autosaveWarning = str('ms_album_sync_failed'); }
    });
  }

  private refreshDownloadPath(): void {
    this.downloadPath = getDownloadDirectoryPath(getContext(this) as common.UIAbilityContext);
  }

  private changeDownloadPath(): void {
    if (this.changingDownloadPath) { return; }
    this.changingDownloadPath = true;
    changeDownloadDirectory(getContext(this) as common.UIAbilityContext).then((changed: boolean): void => {
      this.changingDownloadPath = false;
      if (changed) {
        this.refreshDownloadPath();
        promptAction.showToast({ message: $r('app.string.ds_download_path_changed'), duration: 1600 });
      }
    }).catch((error: Error): void => {
      this.changingDownloadPath = false;
      logE(`DataStoragePage.changeDownloadPath failed: ${error.message}`);
      promptAction.showToast({ message: $r('app.string.media_cannot_open_location'), duration: 1800 });
    });
  }

  // 迁移前是 router 页的 onPageShow()。**方法体一字未改**，只改了名字并由外壳
  // 转发——NavDestination 上对应的是 HdsNavDestination.onShown()，调用页够不着
  // 那一层，所以在 build() 里把它作为 onShown Prop 传给 HdsSubDestination。
  //
  // 触发时机对得上：这个页面本来就是靠"从 StorageUsagePage / NetworkUsagePage
  // 返回时重新拉一次用量"才不显示陈旧数字的，而那两个页面还是 router 页，盖在
  // 本 NavDestination 之上、退出时本页重新可见——正是 onShown。
  onShown(): void {
    if (Date.now() - this.lastLoadAt > 1200) { this.load(false); }
  }

  aboutToDisappear(): void {
    this.active = false;
    this.loadSequence++;
    this.autosaveSyncSequence++;
    this.stopSkeleton();
  }

  private animationDuration(value: number): number {
    return powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, value);
  }

  private startSkeleton(): void {
    if (this.skeletonTimer !== -1 || this.animationDuration(1) === 0) { return; }
    this.skeletonTimer = setInterval((): void => {
      this.skeletonBright = !this.skeletonBright;
    }, 680);
  }

  private stopSkeleton(): void {
    if (this.skeletonTimer !== -1) {
      clearInterval(this.skeletonTimer);
      this.skeletonTimer = -1;
    }
    this.skeletonBright = false;
  }

  private load(initial: boolean): void {
    const sequence = ++this.loadSequence;
    this.lastLoadAt = Date.now();
    if (initial && this.storage === null && this.network === null) { this.startSkeleton(); }
    this.storageLoading = true;
    this.networkLoading = true;
    this.syncWarning = '';
    getStorageUsage().then((value: StorageUsage): void => {
      if (!this.active || sequence !== this.loadSequence) { return; }
      this.storage = value;
      this.storageLoading = false;
      this.storageError = '';
      if (!this.networkLoading) { this.stopSkeleton(); }
    }).catch((error: TdError): void => {
      if (!this.active || sequence !== this.loadSequence) { return; }
      this.storageLoading = false;
      this.storageError = this.storage === null ? str('ds_storage_load_failed') : '';
      if (this.storage !== null) { this.syncWarning = str('ds_partial_sync'); }
      if (!this.networkLoading) { this.stopSkeleton(); }
      logE(`DataStoragePage.getStorageUsage failed: ${error.message}`);
    });
    getNetworkUsage().then((value: NetworkUsage): void => {
      if (!this.active || sequence !== this.loadSequence) { return; }
      this.network = value;
      this.networkLoading = false;
      this.networkError = '';
      if (!this.storageLoading) { this.stopSkeleton(); }
    }).catch((error: TdError): void => {
      if (!this.active || sequence !== this.loadSequence) { return; }
      this.networkLoading = false;
      this.networkError = this.network === null ? str('network_load_failed') : '';
      if (this.network !== null) { this.syncWarning = str('ds_partial_sync'); }
      if (!this.storageLoading) { this.stopSkeleton(); }
      logE(`DataStoragePage.getNetworkUsage failed: ${error.message}`);
    });
  }

  private selectLimit(value: number): void {
    if (this.cacheLimit === value) { return; }
    setNumber(KEY_CACHE_LIMIT, value);
    applyCacheLimit(value).catch((error: TdError): void => {
      if (this.active) { this.autosaveWarning = str('ms_download_sync_failed'); }
      logE(`DataStoragePage.applyCacheLimit failed: ${error.message}`);
    });
  }

  private setAutosave(scope: string, value: boolean): void {
    const key = scope === 'channel' ? KEY_AUTOSAVE_CHANNEL
      : (scope === 'group' ? KEY_AUTOSAVE_GROUP : KEY_AUTOSAVE_PRIVATE);
    setBoolean(key, value);
    if (scope === 'channel') { this.autosaveChannel = value; }
    else if (scope === 'group') { this.autosaveGroup = value; }
    else { this.autosavePrivate = value; }
    if (!this.autosavePrepared) { return; }
    const current = ++this.autosaveSyncSequence;
    this.autosaveSyncing = true;
    syncAutosaveSettings(scope, value).then((): void => {
      if (this.active && current === this.autosaveSyncSequence) { this.autosaveSyncing = false; }
    }).catch((error: TdError): void => {
      if (!this.active || current !== this.autosaveSyncSequence) { return; }
      this.autosaveSyncing = false;
      this.autosaveWarning = str('ms_album_cloud_sync_failed');
      logE(`DataStoragePage.syncAutosave failed: ${error.message}`);
    });
  }

  private sinceLabel(): string {
    if (this.network === null || this.network.sinceDate <= 0) { return str('ds_since_unknown'); }
    const date = new Date(this.network.sinceDate * 1000);
    return str('ds_since', fullDate(date));
  }

  private confirmAction(key: string, title: ResourceStr, message: ResourceStr, button: ResourceStr,
    color: string, operation: () => Promise<void>, success: ResourceStr): void {
    if (this.actionKey !== '') { return; }
    promptAction.showDialog({
      title, message,
      buttons: [
        { text: $r('app.string.cancel'), color: COLOR_TEXT_SECONDARY as string },
        { text: button, color }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse): void => {
      if (result.index !== 1 || this.actionKey !== '') { return; }
      this.actionKey = key;
      operation().then((): void => {
        this.actionKey = '';
        promptAction.showToast({ message: success, duration: 1800 });
        this.load(false);
      }).catch((error: TdError): void => {
        this.actionKey = '';
        logE(`DataStoragePage.${key} failed: ${error.message}`);
        promptAction.showToast({ message: $r('app.string.action_failed_retry'), duration: 1800 });
        this.load(false);
      });
    });
  }

  @Builder
  skeletonCard() {
    Column({ space: 13 }) {
      Row().width('42%').height(14).borderRadius(7).backgroundColor($r('app.color.surface_alt'));
      Row().width('68%').height(28).borderRadius(8).backgroundColor($r('app.color.surface_alt'));
      ForEach(SKELETON_ROWS, (index: number) => {
        Row({ space: 10 }) {
          Circle({ width: 34, height: 34 }).fill($r('app.color.surface_alt'));
          Column({ space: 5 }) {
            Row().width(index === 1 ? '48%' : '62%').height(11).borderRadius(6)
              .backgroundColor($r('app.color.surface_alt'));
            Row().width(index === 1 ? '70%' : '52%').height(9).borderRadius(5)
              .backgroundColor($r('app.color.surface_alt'));
          }.layoutWeight(1).alignItems(HorizontalAlign.Start);
        }.width('100%');
      }, (index: number): string => `${index}`);
    }
    .width('100%').padding(16).backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS)
    .opacity(this.skeletonBright ? 0.55 : 0.94)
    .animation({ duration: this.animationDuration(640), curve: Curve.EaseInOut });
  }

  @Builder
  overviewCard() {
    Column({ space: 14 }) {
      Row() {
        Column({ space: 3 }) {
          Text($r('app.string.ds_local_usage')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
          Text(this.storage !== null ? formatBytes(this.storage.totalSize) : '—')
            .fontSize(30).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
        }.layoutWeight(1).alignItems(HorizontalAlign.Start);
        Stack({ alignContent: Alignment.Center }) {
          Circle({ width: 58, height: 58 }).fill('#163478F6');
          SymbolGlyph($r('sys.symbol.folder_fill')).fontSize(27).fontColor([COLOR_PRIMARY]);
        }
      }.width('100%');
      if (this.storage !== null) {
        Row({ space: 4 }) {
          Row().height(6).layoutWeight(Math.max(1, this.storage.filesSize))
            .borderRadius(3).backgroundColor(COLOR_PRIMARY);
          Row().height(6).layoutWeight(Math.max(1, this.storage.databaseSize))
            .borderRadius(3).backgroundColor('#8E8E93');
          Row().height(6).layoutWeight(Math.max(1,
            this.storage.languagePackDatabaseSize + this.storage.logSize))
            .borderRadius(3).backgroundColor('#C7C7CC');
        }.width('100%');
        Row() {
          Text(str('ds_media_size', formatBytes(this.storage.filesSize))).fontSize(11).fontColor(COLOR_PRIMARY);
          Blank();
          Text(str('ds_database_size', formatBytes(this.storage.databaseSize))).fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
        }.width('100%');
      }
    }
    .width('100%').padding(16).backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS)
    .transition(TransitionEffect.OPACITY.animation({ duration: this.animationDuration(180) }));
  }

  @Builder
  navRow(icon: Resource, title: ResourceStr, subtitle: ResourceStr, value: ResourceStr, page: string) {
    Row({ space: 12 }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle({ width: 38, height: 38 }).fill('#163478F6');
        SymbolGlyph(icon).fontSize(20).fontColor([COLOR_PRIMARY]);
      }
      Column({ space: 2 }) {
        Text(title).fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
        Text(subtitle).fontSize(12).fontColor(COLOR_TEXT_SECONDARY).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      if (value !== '') { Text(value).fontSize(13).fontColor(COLOR_TEXT_SECONDARY); }
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(15).fontColor([COLOR_ICON_SECONDARY]);
    }
    .width('100%').height(64).padding({ left: 12, right: 12 })
    .stateStyles({ normal: this.rowNormalStyle, pressed: this.rowPressedStyle })
    .onClick((): void => { router.pushUrl({ url: page }); });
  }

  @Builder
  statsCard() {
    Column() {
      this.navRow($r('sys.symbol.folder_fill'), $r('app.string.storage_title'),
        this.storageError !== '' ? this.storageError :
          (this.storage !== null ? plural('ds_cached_files', this.storage.fileCount, this.storage.fileCount) : $r('app.string.ds_awaiting_stats')),
        this.storage !== null ? formatBytes(this.storage.filesSize) : '—',
        'pages/main/StorageUsagePage');
      Divider().strokeWidth(0.5).color(COLOR_DIVIDER).margin({ left: 62 });
      this.navRow($r('sys.symbol.data_proportion'), $r('app.string.network_title'),
        this.networkError !== '' ? this.networkError : this.sinceLabel(),
        this.network !== null ? formatBytes(this.network.sent + this.network.received) : '—',
        'pages/main/NetworkUsagePage');
    }.width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS).clip(true);
  }

  @Builder
  limitRow(value: number) {
    Row({ space: 10 }) {
      Text(value === CACHE_LIMIT_UNLIMITED ? str('ms_cache_unlimited') : formatBytes(value))
        .fontSize(15).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
      if (this.cacheLimit === value) {
        SymbolGlyph($r('sys.symbol.checkmark')).fontSize(18).fontColor([COLOR_PRIMARY]);
      }
    }
    .width('100%').padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .stateStyles({ normal: this.rowNormalStyle, pressed: this.rowPressedStyle })
    .onClick((): void => this.selectLimit(value));
  }

  @Builder
  limitCard() {
    Column() {
      Text(str('ms_cache_limit')).fontSize(14).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY)
        .width('100%').padding({ left: 14, right: 14, top: 12, bottom: 2 });
      Text(str('ms_cache_limit_sub')).fontSize(11).fontColor(COLOR_TEXT_SECONDARY)
        .width('100%').padding({ left: 14, right: 14, bottom: 6 });
      ForEach(CACHE_LIMIT_OPTIONS, (value: number, index: number) => {
        if (index > 0) { Divider().strokeWidth(0.5).color(COLOR_DIVIDER).margin({ left: 14 }); }
        this.limitRow(value);
      }, (value: number): string => `${value}`);
    }.width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS).clip(true);
  }

  @Builder
  toggleRow(title: string, subtitle: string, value: boolean, change: (next: boolean) => void) {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text(title).fontSize(15).fontColor(COLOR_TEXT_PRIMARY);
        Text(subtitle).fontSize(11).fontColor(COLOR_TEXT_SECONDARY).maxLines(2);
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      Toggle({ type: ToggleType.Switch, isOn: value }).selectedColor(COLOR_PRIMARY)
        .onChange((next: boolean): void => change(next));
    }.width('100%').padding({ left: 14, right: 14, top: 10, bottom: 10 });
  }

  @Builder
  autosaveCard() {
    Column() {
      this.toggleRow(str('ns_private'), str('ms_save_private_sub'), this.autosavePrivate,
        (next: boolean): void => this.setAutosave('private', next));
      Divider().strokeWidth(0.5).color(COLOR_DIVIDER).margin({ left: 14 });
      this.toggleRow(str('gn_group'), str('ms_save_group_sub'), this.autosaveGroup,
        (next: boolean): void => this.setAutosave('group', next));
      Divider().strokeWidth(0.5).color(COLOR_DIVIDER).margin({ left: 14 });
      this.toggleRow(str('gn_channel'), str('ms_save_channel_sub'), this.autosaveChannel,
        (next: boolean): void => this.setAutosave('channel', next));
    }.width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS).clip(true);
  }

  @Builder
  downloadPathCard() {
    Row({ space: 12 }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle({ width: 38, height: 38 }).fill('#163478F6');
        SymbolGlyph($r('sys.symbol.folder_fill')).fontSize(20).fontColor([COLOR_PRIMARY]);
      }
      Column({ space: 3 }) {
        Text($r('app.string.ds_download_path')).fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
        Text(this.downloadPath !== '' ? this.downloadPath : $r('app.string.ds_download_path_picker'))
          .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      if (this.changingDownloadPath) {
        LoadingProgress().width(19).height(19).color(COLOR_PRIMARY);
      } else {
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(15).fontColor([COLOR_ICON_SECONDARY]);
      }
    }
    .width('100%').padding({ left: 12, right: 12, top: 11, bottom: 11 })
    .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS)
    .enabled(!this.changingDownloadPath)
    .stateStyles({ normal: this.rowNormalStyle, pressed: this.rowPressedStyle })
    .onClick((): void => this.changeDownloadPath());
  }

  @Builder
  autosaveWarningCard() {
    if (this.autosaveWarning !== '') {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.exclamationmark_circle')).fontSize(17).fontColor(['#FF9500']);
        Text(this.autosaveWarning).fontSize(12).fontColor(COLOR_TEXT_SECONDARY).layoutWeight(1);
        if (this.autosaveSyncing) { LoadingProgress().width(16).height(16).color(COLOR_PRIMARY); }
      }.width('100%').padding(11).backgroundColor('#12FF9500').borderRadius(11);
    }
  }

  @Builder
  actionRow(title: ResourceStr, subtitle: ResourceStr, key: string, danger: boolean,
    action: () => void) {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text(title).fontSize(16).fontColor(danger ? DANGER : COLOR_TEXT_PRIMARY);
        Text(subtitle).fontSize(12).fontColor(COLOR_TEXT_SECONDARY).maxLines(2);
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      if (this.actionKey === key) {
        LoadingProgress().width(19).height(19).color(danger ? DANGER : COLOR_PRIMARY);
      }
    }
    .width('100%').padding({ left: 14, right: 14, top: 11, bottom: 11 })
    .enabled(this.actionKey === '')
    .stateStyles({ normal: this.rowNormalStyle, pressed: this.rowPressedStyle })
    .onClick(action);
  }

  @Builder
  actionsCard() {
    Column() {
      this.actionRow($r('app.string.ds_clear_cache'), $r('app.string.ds_clear_cache_sub'), 'cache', false, (): void => {
        const before = this.storage !== null ? this.storage.filesSize : 0;
        this.confirmAction('cache', $r('app.string.ds_clear_cache'),
          str('ds_clear_confirm', formatBytes(before)),
          $r('app.string.clear'), COLOR_PRIMARY as string,
          (): Promise<void> => clearCache().then((): void => {}), $r('app.string.storage_clear_done'));
      });
      Divider().strokeWidth(0.5).color(COLOR_DIVIDER).margin({ left: 14 });
      this.actionRow($r('app.string.network_reset'), $r('app.string.ds_reset_sub'), 'network', false, (): void => {
        this.confirmAction('network', $r('app.string.network_reset'), $r('app.string.ds_reset_confirm'),
          $r('app.string.reset'), COLOR_PRIMARY as string, resetNetworkUsage, $r('app.string.network_reset_done'));
      });
      Divider().strokeWidth(0.5).color(COLOR_DIVIDER).margin({ left: 14 });
      this.actionRow($r('app.string.ds_clear_drafts'), $r('app.string.ds_clear_drafts_sub'), 'drafts', true, (): void => {
        this.confirmAction('drafts', $r('app.string.ds_clear_drafts'),
          $r('app.string.ds_clear_drafts_confirm'),
          $r('app.string.clear_all'), DANGER, clearAllDrafts, $r('app.string.ds_drafts_cleared'));
      });
    }.width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS).clip(true);
  }

  @Builder
  warningCard() {
    if (this.syncWarning !== '') {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.exclamationmark_circle')).fontSize(17).fontColor(['#FF9500']);
        Text(this.syncWarning).fontSize(12).fontColor(COLOR_TEXT_SECONDARY).layoutWeight(1);
        Text($r('app.string.settings_retry')).fontSize(12).fontColor(COLOR_PRIMARY).onClick((): void => this.load(false));
      }.width('100%').padding(11).backgroundColor('#12FF9500').borderRadius(11);
    }
  }

  build() {
    Column() {
      HdsSubDestination({
        title: $r('app.string.settings_data'), scroller: this.hdsScroller,
        pageBackground: COLOR_PAGE_BG,
        onShown: (): void => { this.onShown(); }
      }) {
      Scroll(this.hdsScroller) {
        Column({ space: 12 }) {
          Text($r('app.string.ds_download_location')).fontSize(14).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY)
            .width('100%').padding({ left: 4, top: 4 });
          this.downloadPathCard();
          this.warningCard();
          if (this.storage === null && this.network === null &&
            (this.storageLoading || this.networkLoading)) {
            this.skeletonCard();
          } else {
            this.overviewCard();
            this.statsCard();
          }
          this.actionsCard();
          this.limitCard();
          this.autosaveWarningCard();
          Text($r('app.string.ms_save_to_gallery')).fontSize(14).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY)
            .width('100%').padding({ left: 4, top: 4 });
          this.autosaveCard();
          Text($r('app.string.ds_note'))
            .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).width('100%')
            .padding({ left: 14, right: 14, top: 1 });
        }.width('100%').padding({ left: 12, right: 12, top: 6, bottom: this.bottomSafe + 24 });
      }
      .layoutWeight(1).width('100%').align(Alignment.Top)
      .scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
      // 不裁剪，内容才能穿到标题栏底下——渐变模糊模糊的正是这部分。
      .clip(false);
    }
    }
    .width('100%').height('100%').backgroundColor(COLOR_PAGE_BG)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
  }
}
