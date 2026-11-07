import { WallpaperEditorSession, WallpaperEditorSource } from '../../services/WallpaperEditorSession';
import { getTdClient, getChatStore, getChatThemeStore } from '../../tdkit/Globals';
import { TdClient } from '../../tdkit/TdClient';
import { ThumbBatch } from '../../util/thumbBatch';
import { uploadedThumbPath } from '../../util/localWallpaper';
import { writeUploadedThumb } from '../../util/wallpaperThumb';
import { LengthMetrics, router, promptAction } from '@kit.ArkUI';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { TdError, TdObject } from '../../tdkit/TdTypes';
import {
  applyChatBackground, applyRemoteBackground, applySolidChatBackground, applySolidDefaultBackground,
  clearChatBackground, downloadFileToPath, listBackgrounds, resetDefaultBackground
} from '../../store/BackgroundApi';
import {
  hexColorToInt, isSolidBackgroundOf, isSystemBackground, solidBackgroundState, solidPaletteFor,
  systemSlotColor
} from '../../util/solidBackground';
import {
  backgroundPreviewOf, backgroundThumbnailFile
} from '../../util/backgroundPresentation';
import {
  backgroundStateOf, BackgroundStateResult, ChatBackgroundState, ChatBackgroundStore, defaultChatBackgroundSnapshot,
  emptyChatBackground, invalidateDefaultSnapshot, localWallpaperState, parseSnapshot,
  serialiseSnapshot, referencedWallpaperPaths
} from '../../store/ChatBackgroundStore';
import { inflateTgvIfNeeded } from '../../util/gunzipTgs';
import {
  NO_BLUR_RADIUS, patternTileGrid, patternTileGridLayer, wallpaperTakesBlur, wallpaperTakesUserDim
} from '../../util/chatBackgroundRaster';
import {
  COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE, COLOR_TEXT_PRIMARY, COLOR_ICON_SECONDARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';
import {
  BG_BLUR_DEFAULT, BG_BLUR_MAX, BG_BLUR_MIN, BG_PATTERN_DEFAULT, BG_PATTERN_MIN,
  CHAT_DIM_MAX, KEY_BG_BLUR, KEY_BG_PATTERN, KEY_BG_PATTERN_DARK, KEY_CHAT_DIM,
  bumpLocalWallpaperEpoch, KEY_LOCAL_BG_DARK, KEY_LOCAL_BG_LIGHT,
  patternStrengthKey, setNumber, setString
} from '../../store/AppSettings';
import {
  isUploadedWallpaperFile, localWallpaperFileName, wallpaperFileStillUsed
} from '../../util/localWallpaper';
import {
  SLOT_CHAT_DARK, SLOT_CHAT_LIGHT, slotHasDim, slotIsApp, slotIsDark,
  wallpaperSlotKeys, WallpaperSlotKeys
} from '../../util/wallpaperSlot';
import { logE, logI } from '../../util/log';
import { contentSideGutter } from '../../util/contentWidth';
import { BLUR_MAX_VP, topEdgeBlurStops } from '../../util/scrollEdgeBlur';
import { WallpaperPreview } from './WallpaperPreview';
import { GalleryRow } from '../../util/backgroundRow';

const CARD_RADIUS: number = 14;
const TILE_HEIGHT: number = 118;
const PREVIEW_HEIGHT: number = 188;
const SOLID_SWATCH: number = 40;
// 三条滑杆改成「常显」之后的不可用态：文字、轨道、滑块一起降透明度，并且 .enabled(false)
// 让它拖不动。以前是条件渲染（用不到就整行不画），于是切背景时卡片高度跳、偶发整张卡片
// 不出现；改成常显+置灰后，布局恒定，用户也能看出「这项跟当前背景无关」。
const COLOR_TEXT_DISABLED: ResourceColor = '#59000000';
const COLOR_TRACK_DISABLED: ResourceColor = '#1F000000';
const COLOR_BLOCK_DISABLED: ResourceColor = '#3D000000';
// 缩略图下载并发上限。TDLib 的 downloadFile 由 native 侧串行处理并回收回调，
// 把整页几十张壁纸一次性发出去，等于在收包路径上排队，页面刚进来就整段卡住。
const THUMB_CONCURRENCY: number = 3;

// 一格的缩略图。**必须是 @ComponentV2**：V1 的 @Component 订阅不了 @ObservedV2
// 类上的 @Trace（同 pages/chat/ChatHeader.ets 里那条约束），只有 V2 子组件才会
// 因为本行的 thumb / applying 变化被单独标记重绘 —— 父级 ForEach 的项 builder
// 因此一次都不用重算（v2sample 两轮小样实测 24/24 → 0）。
@ComponentV2
struct GalleryTile {
  @Require @Param row: GalleryRow;
  // 一格在布局里的实际宽度（vp）。图案按真实背景的平铺密度铺，需要它来算列数。
  @Param cellW: number = 0;
  @Event onTap: () => void = () => {};

  build() {
    Stack({ alignContent: Alignment.BottomStart }) {
      if (this.row.preview.kind === 'wallpaper') {
        if (this.row.thumb !== '') {
          Image(`file://${this.row.thumb}`).draggable(false)
            .autoResize(true)
            .width('100%').height('100%').objectFit(ImageFit.Cover);
        } else {
          Column() {
            LoadingProgress().width(22).height(22).color(COLOR_ICON_SECONDARY);
          }.width('100%').height('100%').justifyContent(FlexAlign.Center)
          .backgroundColor(COLOR_SURFACE);
        }
      } else if (this.row.preview.colors.length === 1) {
        Column().width('100%').height('100%')
          .backgroundColor(this.row.preview.colors[0]);
      } else {
        Column().width('100%').height('100%')
          .linearGradient({
            angle: this.row.preview.angle,
            colors: this.row.preview.colors.map((color: string, index: number): [string, number] =>
              [color, this.row.preview.colors.length > 1 ? index / (this.row.preview.colors.length - 1) : 0])
          });
      }
      // 图案背景的「底」只是垫在图案下面的填充色，真正的观感来自 pattern 文档本身。
      // 以前瓦片只画这层填充、不画图案，于是 fill 为黑色的那几条图案壁纸整格渲染成
      // 纯 #000000 —— 用户报的「异常黑瓦片」其实是**黑色壁纸**缺了图案本体。
      // 底色仍然照 TDLib 给的 fill 画（不要改成中性灰：用户 2026-11-06 确认这些背景
      // 本来就是黑的），下面这层把图案本体叠上去即可。
      if (this.row.preview.kind === 'pattern' && this.row.thumb !== '') {
        // 图案在真实背景里是**按 patternTileGrid 平铺**的（一屏约 10 列），而
        // document.thumbnail 只有 155×320 —— 直接 Cover 一张铺满整格，等于把单个图元
        // 放大 2 倍多，主观上就是「图案太粗、不够细腻」（用户 2026-11-06 实报）。
        // 这里改成同样按格高铺：格高 118vp → 每列 57.4vp，一张 155px 的缩略图被**缩小**
        // 而不是放大，图元大小和真实背景一致，线稿也回到细腻。
        if (this.cellW > 0) {
          patternTileGridLayer(this.row.thumb, 1, patternTileGrid(this.cellW, TILE_HEIGHT), NO_BLUR_RADIUS);
        } else {
          // 首帧还没量到宽度时的兜底（下一帧就会换成平铺）。
          Image(`file://${this.row.thumb}`).draggable(false)
            .autoResize(true)
            .width('100%').height('100%').objectFit(ImageFit.Cover);
        }
      }
      if (this.row.preview.kind === 'pattern') {
        Text($r('app.string.cb_pattern')).fontSize(10).fontColor('#D9FFFFFF')
          .padding({ left: 7, right: 7, top: 2, bottom: 2 })
          .borderRadius(9).backgroundColor('#59000000').margin(7);
      }
      if (this.row.applying) {
        Column() {
          LoadingProgress().width(26).height(26).color(Color.White);
        }.width('100%').height('100%').justifyContent(FlexAlign.Center)
        .backgroundColor('#40000000');
      }
    }
    .width('100%').height(TILE_HEIGHT).borderRadius(12).clip(true)
    .renderGroup(true)
    .onClick((): void => { this.onTap(); });
  }
}

interface BackgroundPageParams {
  chatId?: number;
  // 四槽位模式：'appLight' / 'appDark' / 'chatLight' / 'chatDark'（见
  // util/wallpaperSlot）。给了 slot 就固定深浅色、隐藏页内的模式开关；不给则是
  // 从会话资料页进来的"给这个会话设背景"，走原来的 chatId 那条路。
  slot?: string;
}

@Entry
@Component
struct ChatBackgroundPage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  // 滚动区实测高度（vp）：linearGradientBlur 的 fractionStops 要按实际高度归一化。
  @State private listViewH: number = 0;
  // 滚动中把整页的线性渐变虚化关掉（半径传 0）。这一页原来是无条件 22vp——
  // 全仓 20 多个二级页里只有聊天消息列表做了滚动降级，这一页漏了。平板可视
  // 面积是手机的两三倍，RS 侧要重绘的模糊层（实测 188 个 modifier、单个
  // ~10ms）随面积线性增长，叠上滑杆/缩略图引起的整页 ExecuteRerender，
  // 单次停顿能到 100–150ms。真机 hitrace 见 performance/ 归档。
  @State private scrollActive: boolean = false;
  // 窗口宽（不是屏幕宽），限宽用。平板上把一列拉满 2880px 眼睛要横扫一行。
  @StorageProp('screenWidthVp') screenW: number = 360;
  // 三根滑杆改成 @State 镜像：它们要按**槽位**读写，而 @StorageProp 的键是写死的。
  // 这页只活一会儿，进来时从槽位键读一次、改动时写回去就够。
  @State bgBlur: number = BG_BLUR_DEFAULT;
  @State loadState: string = 'loading';
  @State rows: GalleryRow[] = [];
  @State forDark: boolean = false;
  // '' = 旧的按会话设背景；非空 = 四槽位之一，见 util/wallpaperSlot。
  @State slotId: string = '';
  @State patternPct: number = BG_PATTERN_DEFAULT;
  // 深色遮罩强度（0..CHAT_DIM_MAX）。滑杆按百分比显示，存的是 0..1 的小数。
  @State chatDim: number = 0;
  // 当前槽位真正生效的壁纸。纹理滑块的显隐和实时预览都只读这一份，不能再去
  // 猜“聊天默认背景”——APP 槽位本来就不经过那份状态。
  @State currentBackground: ChatBackgroundState = emptyChatBackground();
  @State applyingId: string = '';
  // 网格实际宽度（vp），由 GridRow 的 onAreaChange 写入；用来算每格宽度，图案按
  // 真实密度平铺需要它。
  @State gridWidth: number = 0;
  // 正在应用的那一行。applyingId 仍是页面级互斥锁（6 处应用动作都靠它当闸门），
  // 这里只是它的镜像：瓦片转圈读 row.applying，才不会点一下就让整张网格重算。
  private applyingRow: GalleryRow | null = null;
  // 本机自选壁纸的沙箱路径（'' = 没设）。只在全局背景页出现（chatId === 0）：
  // 它压过账号默认背景，但让位于会话自己的背景，做成"某个会话专属的本地图"
  // 会和服务端的会话背景抢同一块语义。
  @State localPath: string = '';
  private pickingLocal: boolean = false;
  // 这台机器上传过的壁纸。上传过的图是**共用的**：同一张可以给多个槽位用，不必
  // 重传（用户："上传的壁纸互相区域之间应该可以显示，不需要重新传"）。
  @State uploaded: string[] = [];
  // 缩略图到达合批：先攒进 ThumbBatch，180ms 一次逐行写进 row.thumb
  //（见 util/thumbBatch；不再整表换 Map）。
  private thumbBatch: ThumbBatch = new ThumbBatch();
  private thumbFlushTimer: number = -1;
  // 缩略图下载队列：等着下的行 + 在途数量（并发上限见 THUMB_CONCURRENCY）。
  private thumbQueue: GalleryRow[] = [];
  private thumbInFlight: number = 0;
  // 已上传壁纸 → 它旁边那份小缩略图（有才记；没有就退回原图 + sourceSize）。
  private uploadedThumbs: Map<string, string> = new Map();
  // 0 = account default mode; non-zero = one chat only. Group/channel chat
  // ids are NEGATIVE — never gate the per-chat branch on chatId > 0.
  private chatId: number = 0;
  private active: boolean = false;
  private previewSession: WallpaperEditorSession = new WallpaperEditorSession();
  private pageClient: TdClient | null = null;
  private editSequence: number = 0;
  @StorageProp('tdSessionEpoch') @Watch('onSessionChanged') sessionEpoch: number = 0;

  private onSessionChanged(): void {
    if (!this.active) { return; }
    this.active = false;
    this.editSequence++; this.sequence++;
    this.previewSession.close();
    this.currentBackground = emptyChatBackground();
    this.rows = []; this.uploaded = []; this.applyingRow = null;
    router.back();
  }

  private observeCurrentBackground(known?: TdObject | null): void {
    this.previewSession.close();
    if (!this.active || slotIsApp(this.effectiveSlot()) ||
      (this.chatId === 0 && this.localPath !== '')) { return; }
    const client = this.pageClient;
    if (client === null || client !== getTdClient()) { return; }
    const slot: string = this.effectiveSlot();
    const dark: boolean = this.forDark;
    const store = new ChatBackgroundStore(client, getChatStore(), getChatThemeStore(), (): boolean => dark);
    const source: WallpaperEditorSource = {
      seedFromDefault: (): void => store.seedFromDefault(),
      subscribe: (listener: (state: ChatBackgroundState) => void): (() => void) => store.subscribe(listener),
      open: (chatId: number): void => store.open(chatId),
      close: (): void => store.close()
    };
    this.previewSession.open(source, this.chatId,
      (): boolean => this.active && client === getTdClient() && slot === this.effectiveSlot(),
      (state: ChatBackgroundState): void => { this.currentBackground = state; });
    if (known !== undefined) { store.applyKnownBackground(known); }
  }

  private beginEdit(): number {
    this.previewSession.close();
    return ++this.editSequence;
  }

  private editIsCurrent(sequence: number): boolean {
    return this.active && sequence === this.editSequence && this.pageClient === getTdClient();
  }
  private sequence: number = 0;

  aboutToAppear(): void {
    this.active = true;
    this.pageClient = getTdClient();
    const params = router.getParams() as BackgroundPageParams | undefined;
    this.chatId = params?.chatId ?? 0;
    this.slotId = params?.slot ?? '';
    if (this.slotId !== '') {
      this.forDark = slotIsDark(this.slotId);
    }
    this.loadSlotValues();
    this.loadLocal();
    this.observeCurrentBackground();
    this.loadUploaded();
    this.load();
  }

  aboutToDisappear(): void {
    this.active = false;
    this.editSequence++;
    this.previewSession.close();
    this.sequence++;
    this.thumbBatch.clear();
    this.thumbQueue = [];
    this.thumbInFlight = 0;
    this.applyingRow = null;
    if (this.thumbFlushTimer !== -1) {
      clearTimeout(this.thumbFlushTimer);
      this.thumbFlushTimer = -1;
    }
  }

  // 返回键必须在这一页自己吃掉并出栈。
  // 不写的话会冒泡到 Index.onBackPress，那边只看 AppStorage 里的页签序号：
  // 我们是从「设置」页签进来的，序号不是 0，于是它把页签切回聊天并 return true，
  // router 栈一动不动 —— 用户看到的就是「返回没反应」；再配合这一页进入时
  // getInstalledBackgrounds 可能整整 15 秒不返回（loading 态），观感就是黑屏卡死。
  // 2026-11-05 真机复现：进入壁纸页 → 返回键 → 页面原地不动，pid 不变。
  onBackPress(): boolean {
    logI('[ChatBackgroundPage] onBackPress fired');
    // router.back() 直接写在返回事件回调里，某些情况下会被当成"同一帧内再次触发
    // 返回"而无效果；挪到下一个宏任务再出栈（真机验证用）。
    setTimeout((): void => {
      logI('[ChatBackgroundPage] onBackPress -> router.back()');
      router.back();
    }, 0);
    return true;
  }

  private load(): void {
    const sequence = ++this.sequence;
    this.loadState = 'loading';
    listBackgrounds(this.forDark).then((backgrounds: TdObject[]): void => {
      if (!this.active || sequence !== this.sequence) { return; }
      const rows: GalleryRow[] = [];
      const seen: Map<string, number> = new Map();
      for (const raw of backgrounds) {
        const preview = backgroundPreviewOf(raw);
        if (preview !== null && (preview.colors.length > 0 || preview.kind === 'wallpaper')) {
          const base: string = `bg_${preview.backgroundId}_${preview.kind}_${preview.isDark ? 'd' : 'l'}`;
          const hit: number = seen.get(base) ?? 0;
          seen.set(base, hit + 1);
          rows.push(new GalleryRow(preview, raw, hit === 0 ? base : `${base}#${hit}`));
        }
      }
      this.rows = rows;
      this.loadState = 'ready';
      this.loadThumbnails(rows, sequence);
    }).catch((error: TdError): void => {
      if (!this.active || sequence !== this.sequence) { return; }
      logE(`ChatBackgroundPage.load failed: ${error.message}`);
      this.loadState = 'error';
    });
  }

  // Photo wallpapers can't be drawn from colors — fetch their small document
  // thumbnails after the grid is already on screen.
  // Photo wallpapers can't be drawn from colors — fetch their small document
  // thumbnails after the grid is already on screen.
  //
  // 这里原来有两个会把整页拖死的问题：
  // 1) 把全部 wallpaper 的 downloadFile 一次性发出去，没有并发上限；
  // 2) 每收到一张就 setTimeout 一次且不清旧定时器 —— 20 张图 = 20 个定时器，
  //    每个都整表替换缩略图状态（当时是整表换一个 Map），于是整页网格重建 20 次。实测一次整页
  //    ExecuteRerender 23.8ms，叠上这一页 22vp 的整页渐变虚化（RS 侧 188 个
  //    modifier、单个 ~10ms），单次停顿能到 100–150ms，平板上表现为卡死。
  // 改成「限量下载队列 + 只有一个在途合批定时器」。
  private loadThumbnails(rows: GalleryRow[], sequence: number): void {
    this.thumbQueue = [];
    for (const row of rows) {
      // 图案背景同样要取 document.thumbnail：它的「底」只是填充色，图案本体在
      // 文档里。不取的话 fill 为黑色的那几条渲染成纯黑格子（见 placeholderFill）。
      if (row.preview.kind !== 'wallpaper' && row.preview.kind !== 'pattern') { continue; }
      const file = backgroundThumbnailFile(row.raw);
      const fileId = file !== null ? ((file['id'] as number | undefined) ?? 0) : 0;
      if (fileId > 0) { this.thumbQueue.push(row); }
    }
    this.pumpThumbnails(sequence);
  }

  // 同时在途最多 THUMB_CONCURRENCY 个，完成一个补一个。
  private pumpThumbnails(sequence: number): void {
    while (this.thumbInFlight < THUMB_CONCURRENCY && this.thumbQueue.length > 0) {
      const row: GalleryRow = this.thumbQueue.shift() as GalleryRow;
      const file = backgroundThumbnailFile(row.raw);
      const fileId: number = file !== null ? ((file['id'] as number | undefined) ?? 0) : 0;
      if (fileId <= 0) { continue; }
      this.thumbInFlight++;
      downloadFileToPath(fileId).then((path: string): void => {
        this.thumbInFlight--;
        if (!this.active || sequence !== this.sequence) { return; }
        if (path !== '' && this.thumbBatch.add(row.key, path)) {
          this.scheduleThumbFlush(sequence);
        }
        this.pumpThumbnails(sequence);
      }).catch((error: TdError): void => {
        this.thumbInFlight--;
        logE(`ChatBackgroundPage.thumb ${fileId} failed: ${error.message}`);
        if (this.active && sequence === this.sequence) { this.pumpThumbnails(sequence); }
      });
    }
  }

  // 合批只保留一个在途定时器：再来一张也不重置它，攒满一拍一起落。
  private scheduleThumbFlush(sequence: number): void {
    if (this.thumbFlushTimer !== -1) { return; }
    this.thumbFlushTimer = setTimeout((): void => {
      this.thumbFlushTimer = -1;
      if (!this.active || sequence !== this.sequence) { this.thumbBatch.clear(); return; }
      const pending: Map<string, string> = this.thumbBatch.drain();
      if (pending.size === 0) { return; }
      // 逐行写 row.thumb：每张图只标脏它自己那一格。原来这里整表换 Map，
      // ForEach 的项 builder 会全部重算（v2sample 实测 24/24），才是 3100 条
      // RS 命令 / CustomNodeUpdate 23.8ms 的来源。
      for (const row of this.rows) {
        const path: string | undefined = pending.get(row.key);
        if (path !== undefined) { row.thumb = path; }
      }
      // 180ms 而不是 80ms：并发 3 时 80ms 窗口平均只能攒到 1 张图，等于"下一张
      // 刷一次"；拉到 180ms 仍远低于人能察觉的"缩略图迟钝"，却能把 flush 次数
      // 压到约三分之一。合批窗口照样保留（见 2026-11-06 perf 归档），只是现在
      // 它省的是逐行写入的调度次数，不再是整表 Map 替换。
    }, 180);
  }

  // 清锁：互斥位归零，同时把瓦片上的转圈镜像一起撤掉。
  // 纯色 / 跟随系统那几路没有行对象（applyingRow 为 null），这里天然是空操作。
  private endApply(): void {
    this.applyingId = '';
    if (this.applyingRow !== null) {
      this.applyingRow.applying = false;
      this.applyingRow = null;
    }
  }

  private setForDark(value: boolean): void {
    if (this.forDark === value || this.applyingId !== '' || this.pickingLocal) { return; }
    this.beginEdit();
    this.forDark = value;
    // 深浅色各存一张、三根滑杆也各存一份，切档要跟着换。
    this.loadSlotValues();
    this.loadLocal();
    this.observeCurrentBackground();
    this.loadUploaded();
    this.thumbBatch.clear();
    this.load();
  }

  // 账号默认背景变了：作废持久化快照，否则冷启动后第一个会话会先画出旧背景。
  private invalidateSnapshotIfDefault(): void {
    if (this.chatId === 0) {
      invalidateDefaultSnapshot(this.forDark);
    }
  }

  private apply(row: GalleryRow): void {
    if (!this.active || this.applyingId !== '' || this.pickingLocal) { return; }
    const edit: number = this.beginEdit();
    this.applyingRow = row;
    row.applying = true;
    this.applyingId = row.key;
    // APP 槽位不经过 TDLib：协议里根本没有「APP 背景」这个概念，它只能是本机设置。
    // 但转换必须和聊天壁纸走**同一段** backgroundStateOf + inflateTgvIfNeeded，
    // 否则同一张壁纸在聊天里和在主界面上会长得不一样。
    if (slotIsApp(this.effectiveSlot())) {
      this.applyToAppSlot(row, edit);
      return;
    }
    this.invalidateSnapshotIfDefault();
    const task: Promise<void> = this.chatId !== 0
      ? applyChatBackground(this.chatId, row.raw, true)
      : applyRemoteBackground(row.raw, this.forDark);
    task.then((): void => {
      if (!this.editIsCurrent(edit)) { return; }
      this.dropLocalForChatSlot();
      const parsed: BackgroundStateResult = backgroundStateOf(row.raw);
      if (parsed.state !== null) {
        // TDLib 的默认背景更新会异步回流；先用手里的选择刷新显隐与预览，避免
        // 刚选中图案时纹理滑杆仍要退出重进才出现。
        this.currentBackground = parsed.state;
      }
      this.endApply();
      this.observeCurrentBackground(row.raw);
      promptAction.showToast({
        message: this.chatId !== 0
          ? $r('app.string.cb_chat_set')
          : (this.forDark ? $r('app.string.cb_dark_set') : $r('app.string.cb_light_set')),
        duration: 1600
      });
    }).catch((error: TdError): void => {
      if (!this.editIsCurrent(edit)) { return; }
      this.endApply();
      this.observeCurrentBackground();
      logE(`ChatBackgroundPage.apply failed: ${error.message}`);
      const text = error.message.indexOf('BOOST') >= 0 || error.message.indexOf('boost') >= 0
        ? $r('app.string.cb_boost_required')
        : (error.message.indexOf('ADMIN') >= 0 || error.message.indexOf('rights') >= 0
          ? $r('app.string.cb_admin_required')
          : $r('app.string.cb_set_failed'));
      promptAction.showToast({ message: text, duration: 2000 });
    });
  }

  private sliderSettled(mode: SliderChangeMode): boolean {
    return mode === SliderChangeMode.End || mode === SliderChangeMode.Click;
  }

  private setBlur(value: number, mode: SliderChangeMode): void {
    if (!this.sliderSettled(mode)) { return; }
    this.bgBlur = Math.round(value);
    setNumber(this.slotKeys().blur, this.bgBlur);
  }

  private setPattern(value: number, mode: SliderChangeMode): void {
    if (!this.sliderSettled(mode)) { return; }
    this.patternPct = Math.round(value) / 100;
    setNumber(this.slotKeys().pattern, this.patternPct);
  }

  private setDim(value: number, mode: SliderChangeMode): void {
    if (!this.sliderSettled(mode)) { return; }
    this.chatDim = Math.round(value) / 100;
    setNumber(this.slotKeys().dim, this.chatDim);
  }

  // 当前编辑的是哪个槽位。没给 slot（从会话资料页进来）时按页内的深浅色开关
  // 落到聊天那两个槽位上——那正是旧行为。
  private effectiveSlot(): string {
    if (this.slotId !== '') {
      return this.slotId;
    }
    return this.forDark ? SLOT_CHAT_DARK : SLOT_CHAT_LIGHT;
  }

  private slotKeys(): WallpaperSlotKeys {
    return wallpaperSlotKeys(this.effectiveSlot());
  }

  private loadSlotValues(): void {
    const keys: WallpaperSlotKeys = this.slotKeys();
    this.bgBlur = AppStorage.get<number>(keys.blur) ?? BG_BLUR_DEFAULT;
    this.patternPct = AppStorage.get<number>(keys.pattern) ?? BG_PATTERN_DEFAULT;
    this.chatDim = AppStorage.get<number>(keys.dim) ?? 0;
  }

  private localKey(): string {
    return this.forDark ? KEY_LOCAL_BG_DARK : KEY_LOCAL_BG_LIGHT;
  }

  // 列出沙箱里所有上传过的壁纸。只按文件名前缀认（见
  // util/localWallpaper.isUploadedWallpaperFile），不去读文件内容。
  private loadUploaded(): void {
    try {
      const dir: string = (getContext(this) as common.UIAbilityContext).filesDir;
      const names: string[] = fs.listFileSync(dir);
      const out: string[] = [];
      const thumbs: Map<string, string> = new Map();
      for (const name of names) {
        if (isUploadedWallpaperFile(name)) {
          const full: string = `${dir}/${name}`;
          out.push(full);
          // 旁边那份 ≤512px 缩略图（导入时另存的；老壁纸没有，退回原图 + sourceSize）。
          const thumbName: string = uploadedThumbPath(name);
          if (names.indexOf(thumbName) >= 0) {
            thumbs.set(full, `${dir}/${thumbName}`);
          }
        }
      }
      this.uploadedThumbs = thumbs;
      // 文件名带时间戳，倒序就是"最近上传的排前面"。
      this.uploaded = out.sort().reverse();
    } catch (error) {
      logE(`ChatBackgroundPage.loadUploaded failed: ${error}`);
      this.uploaded = [];
    }
  }

  // 选一张已上传的图给当前槽位。**不复制文件**——共用同一份。
  private useUploaded(path: string): void {
    if (!this.active || this.applyingId !== '' || this.pickingLocal) { return; }
    this.beginEdit();
    const previous: string = this.localPath;
    const state: ChatBackgroundState = localWallpaperState(path);
    if (slotIsApp(this.effectiveSlot())) {
      setString(this.slotKeys().state, serialiseSnapshot(state));
    } else {
      setString(this.localKey(), path);
    }
    this.localPath = path;
    this.currentBackground = state;
    this.removeQuietly(previous);
    this.afterLocalChange();
    promptAction.showToast({ message: $r('app.string.cb_local_applied'), duration: 1500 });
  }

  @Builder
  uploadedRow() {
    Column({ space: 8 }) {
      Text($r('app.string.cb_uploaded'))
        .fontSize(15).fontColor(COLOR_TEXT_PRIMARY)
        .width('100%').padding({ left: 14, right: 14 });
      Scroll() {
        Row({ space: 8 }) {
          ForEach(this.uploaded, (path: string) => {
            // 原图是相机原片；有小缩略图用小缩略图，没有也只按 52vp×3 解码
            // （autoResize 默认 false，不设就是全分辨率解码——闪退根源）。
            Image(`file://${this.uploadedThumbs.get(path) ?? path}`).draggable(false)
              .sourceSize({ width: 156, height: 156 }).autoResize(true)
              .width(52).height(52).borderRadius(8).clip(true)
              .objectFit(ImageFit.Cover)
              .border({
                width: path === this.localPath ? 2 : 0.7,
                color: path === this.localPath ? COLOR_PRIMARY : $r('app.color.divider')
              })
              .onClick((): void => { this.useUploaded(path); });
          }, (path: string): string => path);
        }.padding({ left: 14, right: 14 });
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%');
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
  }

  private loadLocal(): void {
    if (slotIsApp(this.effectiveSlot())) {
      const state: ChatBackgroundState | null = parseSnapshot(
        AppStorage.get<string>(this.slotKeys().state) ?? '');
      this.currentBackground = state ?? emptyChatBackground();
      if (state === null || state.path === '') {
        this.localPath = '';
        return;
      }
      const slash: number = Math.max(state.path.lastIndexOf('/'), state.path.lastIndexOf('\\'));
      const name: string = state.path.substring(slash + 1);
      // 原生图案/照片也有本地缓存 path，但只有相册上传文件才属于“本机壁纸”，
      // 否则会被错误标成已上传、还会出现一个能删除 TDLib 缓存的“移除”按钮。
      this.localPath = isUploadedWallpaperFile(name) ? state.path : '';
      return;
    }
    this.localPath = AppStorage.get<string>(this.localKey()) ?? '';
    this.currentBackground = this.localPath !== ''
      ? localWallpaperState(this.localPath)
      : defaultChatBackgroundSnapshot(this.forDark);
  }

  private pickLocal(): void {
    if (!this.active || this.applyingId !== '' || this.pickingLocal) {
      return;
    }
    this.pickingLocal = true;
    const edit: number = this.editSequence;
    const picker = new photoAccessHelper.PhotoViewPicker();
    const opts = new photoAccessHelper.PhotoSelectOptions();
    opts.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    opts.maxSelectNumber = 1;
    picker.select(opts).then((res: photoAccessHelper.PhotoSelectResult): void => {
      this.pickingLocal = false;
      if (!this.editIsCurrent(edit) || res.photoUris.length === 0) {
        return;
      }
      this.installLocal(res.photoUris[0]);
    }).catch((): void => { this.pickingLocal = false; });
  }

  private installLocal(uri: string): void {
    this.beginEdit();
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      // 文件名带时间戳：固定名会被 Image 的解码缓存卡住，换了图屏幕上还是旧的。
      // 代价是必须自己删旧图，见 removeQuietly。判据见 util/localWallpaper。
      const dest: string = `${ctx.filesDir}/${localWallpaperFileName(this.forDark, Date.now())}`;
      const src = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      fs.copyFileSync(src.fd, dest);
      fs.closeSync(src);
      const previous: string = this.localPath;
      this.loadUploaded();
      writeUploadedThumb(dest).then((thumb: string): void => {
        if (thumb !== '' && this.active) { this.loadUploaded(); }
      });
      if (slotIsApp(this.effectiveSlot())) {
        // APP 槽位和聊天槽位存的是同一种数据（序列化的 ChatBackgroundState），
        // 这样原生壁纸和本机图走的是同一条渲染路径。blurred 恒为 true 的理由见
        // ChatBackgroundStore 里同一处说明。
        const state: ChatBackgroundState = emptyChatBackground();
        state.custom = true;
        state.path = dest;
        state.blurred = true;
        setString(this.slotKeys().state, serialiseSnapshot(state));
        this.currentBackground = state;
      } else {
        setString(this.localKey(), dest);
        this.currentBackground = localWallpaperState(dest);
      }
      this.localPath = dest;
      this.removeQuietly(previous);
      this.afterLocalChange();
      promptAction.showToast({ message: $r('app.string.cb_local_applied'), duration: 1500 });
    } catch (error) {
      this.observeCurrentBackground();
      logE(`ChatBackgroundPage.installLocal failed: ${error}`);
      promptAction.showToast({ message: $r('app.string.cb_local_failed'), duration: 1800 });
    }
  }

  private clearLocal(): void {
    if (!this.active || this.applyingId !== '' || this.pickingLocal) { return; }
    this.beginEdit();
    const previous: string = this.localPath;
    if (slotIsApp(this.effectiveSlot())) {
      setString(this.slotKeys().state, '');
      this.currentBackground = emptyChatBackground();
    } else {
      setString(this.localKey(), '');
      this.currentBackground = defaultChatBackgroundSnapshot(this.forDark);
    }
    this.localPath = '';
    this.removeQuietly(previous);
    this.afterLocalChange();
    this.observeCurrentBackground();
  }

  // 纯本地改动不会有 TDLib update 推回来，聊天页靠这个代次重算；快照也要作废，
  // 否则下次进会话会先闪一帧旧背景。
  private afterLocalChange(): void {
    if (slotIsApp(this.effectiveSlot())) {
      return;
    }
    bumpLocalWallpaperEpoch();
    invalidateDefaultSnapshot(this.forDark);
  }

  // 换图/移除之后清理旧文件。**只在没有任何槽位还引用它时才删**——上传过的
  // 壁纸是共用的，同一张图可能同时给几个槽位用，无条件删会把别人的槽位弄成
  // 一个指向空路径的洞。删不掉也不该打断流程：壁纸已经换好了，残留一个文件
  // 不影响任何事。
  private removeQuietly(path: string): void {
    if (path === '' || wallpaperFileStillUsed(path, referencedWallpaperPaths())) {
      return;
    }
    try {
      fs.unlinkSync(path);
    } catch (error) {
      logE(`ChatBackgroundPage.removeQuietly failed: ${error}`);
    }
    try {
      fs.unlinkSync(uploadedThumbPath(path));
    } catch (_error) {
      // 老壁纸没有缩略图，删不到是常态。
    }
  }

  private async applyToAppSlot(row: GalleryRow, edit: number): Promise<void> {
    try {
      const previous: string = this.localPath;
      const parsed: BackgroundStateResult = backgroundStateOf(row.raw);
      if (parsed.state === null) {
        throw new Error(`unpaintable background ${parsed.typeName}`);
      }
      const state: ChatBackgroundState = parsed.state;
      if (parsed.fileId > 0) {
        // 图案是 .tgv（gzip 的 SVG），下完要解压；纯色/渐变没有文档，跳过。
        state.path = await inflateTgvIfNeeded(await downloadFileToPath(parsed.fileId));
      }
      if (!this.editIsCurrent(edit)) { return; }
      setString(this.slotKeys().state, serialiseSnapshot(state));
      this.currentBackground = state;
      this.localPath = '';
      this.removeQuietly(previous);
      if (!this.editIsCurrent(edit)) {
        return;
      }
      this.endApply();
      promptAction.showToast({ message: $r('app.string.cb_local_applied'), duration: 1500 });
    } catch (error) {
      if (!this.editIsCurrent(edit)) {
        return;
      }
      this.endApply();
      logE(`ChatBackgroundPage.applyToAppSlot failed: ${error}`);
      promptAction.showToast({ message: $r('app.string.cb_set_failed'), duration: 1800 });
    }
  }

  // 选纯色 / 跟随系统时顺手撤掉本机自选的图：本机图压过账号默认背景（见
  // util/localWallpaper），不撤的话选了纯色也看不见。只管全局聊天槽位——APP 槽位
  // 的图就存在槽位状态里，覆盖写入即可；按会话设背景时本机图本来就让位。
  private dropLocalForChatSlot(): void {
    if (slotIsApp(this.effectiveSlot()) || this.chatId !== 0 || this.localPath === '') {
      return;
    }
    const previous: string = this.localPath;
    setString(this.localKey(), '');
    this.localPath = '';
    this.removeQuietly(previous);
    this.afterLocalChange();
  }

  private applySolid(color: string): void {
    if (!this.active || this.applyingId !== '' || this.pickingLocal) { return; }
    const value: number = hexColorToInt(color);
    if (value < 0) { return; }
    const edit: number = this.beginEdit();
    const state: ChatBackgroundState = solidBackgroundState(color);
    if (slotIsApp(this.effectiveSlot())) {
      const previous: string = this.localPath;
      setString(this.slotKeys().state, serialiseSnapshot(state));
      this.currentBackground = state;
      this.localPath = '';
      this.removeQuietly(previous);
      promptAction.showToast({ message: $r('app.string.cb_local_applied'), duration: 1500 });
      return;
    }
    this.applyingId = `solid_${color}`;
    this.dropLocalForChatSlot();
    this.invalidateSnapshotIfDefault();
    const task: Promise<void> = this.chatId !== 0
      ? applySolidChatBackground(this.chatId, value)
      : applySolidDefaultBackground(value, this.forDark);
    task.then((): void => {
      if (!this.editIsCurrent(edit)) { return; }
      this.currentBackground = state;
      this.endApply();
      const fill: TdObject = { '@type': 'backgroundFillSolid', 'color': value };
      const type: TdObject = { '@type': 'backgroundTypeFill', 'fill': fill };
      this.observeCurrentBackground({ '@type': 'background', 'type': type });
      promptAction.showToast({
        message: this.chatId !== 0
          ? $r('app.string.cb_chat_set')
          : (this.forDark ? $r('app.string.cb_dark_set') : $r('app.string.cb_light_set')),
        duration: 1600
      });
    }).catch((error: TdError): void => {
      if (!this.editIsCurrent(edit)) { return; }
      this.endApply();
      this.observeCurrentBackground();
      logE(`ChatBackgroundPage.applySolid failed: ${error.message}`);
      promptAction.showToast({ message: $r('app.string.cb_set_failed'), duration: 2000 });
    });
  }

  // 「跟随系统」= 什么都不设：渲染层画随深浅色切换的 chat_bg。
  private followSystem(): void {
    if (this.applyingId !== '') { return; }
    this.dropLocalForChatSlot();
    this.reset();
  }

  private reset(): void {
    if (!this.active || this.applyingId !== '' || this.pickingLocal) { return; }
    const edit: number = this.beginEdit();
    this.applyingId = 'reset';
    if (slotIsApp(this.effectiveSlot())) {
      const previous: string = this.localPath;
      setString(this.slotKeys().state, '');
      this.localPath = '';
      this.currentBackground = emptyChatBackground();
      this.removeQuietly(previous);
      this.endApply();
      this.observeCurrentBackground();
      promptAction.showToast({ message: $r('app.string.cb_reset_done'), duration: 1500 });
      return;
    }
    this.invalidateSnapshotIfDefault();
    const task: Promise<void> = this.chatId !== 0
      ? clearChatBackground(this.chatId)
      : resetDefaultBackground(this.forDark);
    task.then((): void => {
      if (!this.editIsCurrent(edit)) { return; }
      this.currentBackground = this.chatId !== 0
        ? defaultChatBackgroundSnapshot(this.forDark)
        : emptyChatBackground();
      this.endApply();
      this.observeCurrentBackground();
      promptAction.showToast({
        message: this.chatId !== 0 ? $r('app.string.cb_reset_to_global') : $r('app.string.cb_reset_done'), duration: 1500
      });
    }).catch((error: TdError): void => {
      if (!this.editIsCurrent(edit)) { return; }
      this.endApply();
      this.observeCurrentBackground();
      logE(`ChatBackgroundPage.reset failed: ${error.message}`);
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

  // 图案线条太重时压一档。乘在壁纸自带的 intensity 上，不改壁纸本身，
  // 所以换一张图案后这个设置仍然生效。整图壁纸没有图案可言，滑块不出现。
  private patternValue(): number {
    return this.patternPct;
  }

  // 当前生效的背景是不是图案。整图壁纸没有图案可言，滑块不该出现。
  // 每格宽度：三列 + 两条 10vp 的 gutter。
  private cellWidth(): number {
    if (this.gridWidth <= 0) { return 0; }
    return Math.max(0, (this.gridWidth - 20) / 3);
  }

  private currentIsPattern(): boolean {
    return this.currentBackground.isPattern;
  }

  private previewWidth(): number {
    return Math.max(1, this.screenW - 24 - contentSideGutter(this.screenW) * 2);
  }

  @Builder
  previewCard() {
    Stack() {
      WallpaperPreview({
        wallpaper: this.currentBackground,
        blurAmount: this.bgBlur,
        patternStrength: this.patternPct,
        dimAmount: this.chatDim,
        dark: this.forDark,
        previewW: this.previewWidth(),
        previewH: PREVIEW_HEIGHT,
        baseColor: systemSlotColor(this.forDark, slotIsApp(this.effectiveSlot()))
      });
    }
    .width('100%').height(PREVIEW_HEIGHT).borderRadius(CARD_RADIUS).clip(true)
    .border({ width: 0.7, color: $r('app.color.divider') });
  }

  @Builder
  @Builder
  blurAdjustment() {
    Column({ space: 6 }) {
      Row() {
        Text($r('app.string.cb_blur_amount')).fontSize(15)
          .fontColor(this.showsBlur() ? COLOR_TEXT_PRIMARY : COLOR_TEXT_DISABLED).layoutWeight(1);
        Text(`${this.bgBlur}`).fontSize(14)
          .fontColor(this.showsBlur() ? COLOR_TEXT_SECONDARY : COLOR_TEXT_DISABLED);
      }.width('100%');
      Slider({ value: this.bgBlur, min: BG_BLUR_MIN, max: BG_BLUR_MAX, step: 1, style: SliderStyle.OutSet })
        .width('100%')
        .trackColor(this.showsBlur() ? $r('app.color.divider') : COLOR_TRACK_DISABLED)
        .selectedColor(this.showsBlur() ? COLOR_PRIMARY : COLOR_BLOCK_DISABLED)
        .blockColor(this.showsBlur() ? COLOR_PRIMARY : COLOR_BLOCK_DISABLED)
        .enabled(this.showsBlur())
        .onChange((value: number, mode: SliderChangeMode): void => { this.setBlur(value, mode); });
    }
    .width('100%').padding({ left: 14, right: 14, top: 10, bottom: 10 });
  }

  @Builder
  @Builder
  patternAdjustment() {
    Column({ space: 6 }) {
      Row() {
        Text($r('app.string.cb_pattern_strength')).fontSize(15)
          .fontColor(this.currentIsPattern() ? COLOR_TEXT_PRIMARY : COLOR_TEXT_DISABLED).layoutWeight(1);
        Text(`${Math.round(this.patternPct * 100)}%`).fontSize(14)
          .fontColor(this.currentIsPattern() ? COLOR_TEXT_SECONDARY : COLOR_TEXT_DISABLED);
      }.width('100%');
      Slider({ value: Math.round(this.patternPct * 100), min: Math.round(BG_PATTERN_MIN * 100), max: 100,
        step: 5, style: SliderStyle.OutSet })
        .width('100%')
        .trackColor(this.currentIsPattern() ? $r('app.color.divider') : COLOR_TRACK_DISABLED)
        .selectedColor(this.currentIsPattern() ? COLOR_PRIMARY : COLOR_BLOCK_DISABLED)
        .blockColor(this.currentIsPattern() ? COLOR_PRIMARY : COLOR_BLOCK_DISABLED)
        .enabled(this.currentIsPattern())
        .onChange((value: number, mode: SliderChangeMode): void => { this.setPattern(value, mode); });
    }
    .width('100%').padding({ left: 14, right: 14, top: 10, bottom: 10 });
  }

  @Builder
  @Builder
  dimAdjustment() {
    Column({ space: 6 }) {
      Row() {
        Column({ space: 2 }) {
        Text($r('app.string.chat_settings_dark_dim')).fontSize(15)
          .fontColor(this.showsDim() ? COLOR_TEXT_PRIMARY : COLOR_TEXT_DISABLED);
        Text($r('app.string.chat_settings_dark_dim_sub')).fontSize(11)
          .fontColor(this.showsDim() ? COLOR_TEXT_SECONDARY : COLOR_TEXT_DISABLED)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        }.alignItems(HorizontalAlign.Start).layoutWeight(1);
        Text(`${Math.round(this.chatDim * 100)}%`).fontSize(14)
          .fontColor(this.showsDim() ? COLOR_TEXT_SECONDARY : COLOR_TEXT_DISABLED);
      }.width('100%');
      Slider({ value: Math.round(this.chatDim * 100), min: 0, max: Math.round(CHAT_DIM_MAX * 100),
        step: 5, style: SliderStyle.OutSet })
        .width('100%')
        .trackColor(this.showsDim() ? $r('app.color.divider') : COLOR_TRACK_DISABLED)
        .selectedColor(this.showsDim() ? COLOR_PRIMARY : COLOR_BLOCK_DISABLED)
        .blockColor(this.showsDim() ? COLOR_PRIMARY : COLOR_BLOCK_DISABLED)
        .enabled(this.showsDim())
        .onChange((value: number, mode: SliderChangeMode): void => { this.setDim(value, mode); });
    }
    .width('100%').padding({ left: 14, right: 14, top: 10, bottom: 10 });
  }

  // 纯色 / 跟随系统没有模糊和遮罩（util/chatBackgroundRaster.wallpaperTakes*），
  // 三项都不出现时整张卡片不画。
  private showsBlur(): boolean {
    return wallpaperTakesBlur(this.currentBackground.path);
  }

  private showsDim(): boolean {
    return slotHasDim(this.effectiveSlot()) &&
      wallpaperTakesUserDim(this.currentBackground.colors, this.currentBackground.path);
  }

  @Builder
  @Builder
  adjustmentsCard() {
    Column() {
      this.blurAdjustment();
      Divider().strokeWidth(0.7).color($r('app.color.divider')).margin({ left: 8, right: 4 });
      this.patternAdjustment();
      Divider().strokeWidth(0.7).color($r('app.color.divider')).margin({ left: 8, right: 4 });
      this.dimAdjustment();
    }
    .width('100%').padding({ top: 2, bottom: 2 })
    .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
  }

  // 色块**必须写在 solidCard() 里内联**，不能收成带参 @Builder。
  //
  // 【为什么】带参 @Builder 的参数是挂载那一刻按值捕获的，之后永不更新——传对象
  // 也一样（见 2026-09-11 相册那轮的实测）。原来这里是
  // `solidSwatch(color, selected, busy)`，三个参数，于是 selected 永远是首次
  // 构建时的那个值：点了别的颜色，底色换了、勾选标记却钉在旧格上（用户 2026-10-29
  // 实报）。零参 builder 读 this.currentBackground 才跟着重算。
  @Builder
  solidCard() {
    Column({ space: 10 }) {
      Text($r('app.string.cb_solid_title'))
        .fontSize(15).fontColor(COLOR_TEXT_PRIMARY).width('100%');
      Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(12), cross: LengthMetrics.vp(12) } }) {
        // 第一格「跟随系统」：画的是这个槽位对应模式下的 chat_bg，不是当前系统模式的。
        Column({ space: 4 }) {
          Stack() {
            if (this.applyingId === 'reset') {
              LoadingProgress().width(20).height(20).color(COLOR_PRIMARY);
            } else if (isSystemBackground(this.currentBackground)) {
              SymbolGlyph($r('sys.symbol.checkmark')).fontSize(18).fontColor([COLOR_PRIMARY]);
            }
          }
          .width(SOLID_SWATCH).height(SOLID_SWATCH).borderRadius(SOLID_SWATCH / 2)
          .backgroundColor(systemSlotColor(this.forDark, slotIsApp(this.effectiveSlot())))
          .border({
            width: isSystemBackground(this.currentBackground) ? 2 : 0.7,
            color: isSystemBackground(this.currentBackground) ? COLOR_PRIMARY : $r('app.color.divider')
          });
          Text($r('app.string.cb_follow_system')).fontSize(10).fontColor(COLOR_TEXT_SECONDARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width(56)
            .textAlign(TextAlign.Center);
        }
        .width(56)
        .onClick((): void => this.followSystem());
        ForEach(solidPaletteFor(this.forDark), (color: string) => {
          Column() {
            Stack() {
              if (this.applyingId === `solid_${color}`) {
                LoadingProgress().width(20).height(20).color(COLOR_PRIMARY);
              } else if (isSolidBackgroundOf(this.currentBackground, color)) {
                SymbolGlyph($r('sys.symbol.checkmark')).fontSize(18).fontColor([COLOR_PRIMARY]);
              }
            }
            .width(SOLID_SWATCH).height(SOLID_SWATCH).borderRadius(SOLID_SWATCH / 2)
            .backgroundColor(color)
            .border({
              width: isSolidBackgroundOf(this.currentBackground, color) ? 2 : 0.7,
              color: isSolidBackgroundOf(this.currentBackground, color)
                ? COLOR_PRIMARY : $r('app.color.divider')
            });
          }
          .width(56).height(SOLID_SWATCH)
          .onClick((): void => this.applySolid(color));
        }, (color: string): string => `solid_${color}`);
      }
    }
    .width('100%').padding(14)
    .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
  }

  build() {
    // header 画在内容层之上、不占布局高度：滚动区从屏幕最上沿开始铺垫，
    // 顶部那条渐变模糊才有东西可糊（内容穿过 header 底下）。
    Stack({ alignContent: Alignment.Top }) {
      if (this.loadState === 'loading') {
        Column({ space: 9 }) {
          LoadingProgress().width(34).height(34).color(COLOR_PRIMARY);
          Text($r('app.string.cb_loading')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
        }.width('100%').height('100%').justifyContent(FlexAlign.Center);
      } else if (this.loadState === 'error') {
        Column({ space: 10 }) {
          Text($r('app.string.cb_load_failed')).fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
          Button($r('app.string.settings_reload')).onClick((): void => this.load());
        }.width('100%').height('100%').justifyContent(FlexAlign.Center);
      } else {
        Scroll() {
          Column({ space: 12 }) {
            // 槽位模式下深浅色由槽位定死，页内不该再有一个能改它的开关。
            // 放进滚动内容当首项：滚动区必须从屏幕顶开始，否则顶部模糊带的起点
            // 会被这一行顶下去，穿透效果只剩半条。
            if (this.chatId === 0 && this.slotId === '') {
              Row() { this.modeSwitch(); }.width('100%').justifyContent(FlexAlign.Center)
                .padding({ top: 2, bottom: 10 });
            }
            this.previewCard();
            if (this.chatId === 0) {
              Row({ space: 10 }) {
                SymbolGlyph($r('sys.symbol.picture')).fontSize(17).fontColor([COLOR_PRIMARY]);
                Text($r('app.string.cb_pick_local'))
                  .fontSize(15).fontColor(COLOR_PRIMARY).layoutWeight(1);
              }
              .width('100%').height(48).padding({ left: 14, right: 14 })
              .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS)
              .onClick((): void => { this.pickLocal(); });
              if (this.uploaded.length > 0) {
                this.uploadedRow();
              }
              if (this.localPath !== '') {
                // 单独一行而不是塞进上面那行的尾部：两个 onClick 叠在同一个 Row 上
                // 会互相吃手势，点"移除"多半会先触发"选择"。
                Row({ space: 10 }) {
                  SymbolGlyph($r('sys.symbol.trash')).fontSize(17).fontColor([COLOR_TEXT_SECONDARY]);
                  Text($r('app.string.cb_clear_local'))
                    .fontSize(15).fontColor(COLOR_TEXT_SECONDARY).layoutWeight(1);
                }
                .width('100%').height(48).padding({ left: 14, right: 14 })
                .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS)
                .onClick((): void => { this.clearLocal(); });
              }
            }
            Row({ space: 10 }) {
              SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(17).fontColor([COLOR_PRIMARY]);
              Text(this.chatId !== 0 ? $r('app.string.cb_reset_to_global_action') : $r('app.string.cb_reset_action'))
                .fontSize(15).fontColor(COLOR_PRIMARY).layoutWeight(1);
            }
            .width('100%').height(48).padding({ left: 14, right: 14 })
            .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS)
            .onClick((): void => this.reset());
            this.solidCard();
            // 三条滑杆常显（不可用时置灰、拖不动）：以前这里按当前背景条件渲染，
            // 切背景时卡片高度会跳，还出现过整张卡片偶发不画。
            this.adjustmentsCard();
            GridRow({ columns: 3, gutter: 10 }) {
              ForEach(this.rows, (row: GalleryRow) => {
                GridCol({ span: 1 }) {
                  GalleryTile({ row: row, cellW: this.cellWidth(), onTap: (): void => { this.apply(row); } })
                }
              }, (row: GalleryRow): string => row.key);
            }
            .onAreaChange((_oldArea: Area, newArea: Area): void => {
              const w: number = Number(newArea.width);
              if (w > 0 && w !== this.gridWidth) { this.gridWidth = w; }
            })
            Text(this.chatId !== 0
              ? $r('app.string.cb_chat_note')
              : $r('app.string.cb_global_note'))
              .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).lineHeight(18).width('100%');
          }
          .width('100%')
            // 限宽做在内容列的内边距上而不是 Scroll 的宽度上：Scroll 仍铺满窗口，
            // 两侧让出来的留白因此还在它的命中区里，手指按在留白上照样能滚页面。
            // 手机上 contentSideGutter 恒为 0，两个值逐像素等于改动前的 12。
          // 三列缩略图网格跟着一起收窄是限宽的正常结果：1440vp 窗口下内容列 880，
          // 去掉左右各 12 的内边距和两道 10 的 gutter，单格 (856−20)/3 ≈ 278.7vp。
          // 格子高度是定值 TILE_HEIGHT，没有 aspectRatio，所以只是从 465×118 变成
          // 278.7×118 —— 比手机上的 105×118 还宽，不存在压扁。
          .padding({
            top: this.topSafe + 56 + 12,
            left: 12 + contentSideGutter(this.screenW),
            right: 12 + contentSideGutter(this.screenW),
            bottom: this.bottomSafe + 24
          });
        }
        .align(Alignment.Top).width('100%').height('100%').scrollBar(BarState.Off)
        .onScrollStart((): void => { this.scrollActive = true; })
        .onScrollStop((): void => { this.scrollActive = false; })
        // 半径传 0 = 不模糊（stops 仍然生效，只是没有半径）。滚动中关掉这一层，
        // 静止时恢复——和聊天消息列表同一套降级方式，静止画面像素不变。
        .linearGradientBlur(this.scrollActive ? 0 : BLUR_MAX_VP, {
          fractionStops: topEdgeBlurStops(this.listViewH),
          direction: GradientDirection.Bottom
        })
        .clip(false)
        .onAreaChange((_o: Area, n: Area): void => {
          const h: number = n.height as number;
          if (h > 0 && Math.abs(h - this.listViewH) > 0.5) { this.listViewH = h; }
        });
      }
      Column() {
        this.header();
      }
      .width('100%')
      .padding({ top: this.topSafe })
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%').height('100%').backgroundColor(COLOR_PAGE_BG)
    // 没有这一行时页面的布局区停在安全区边界，状态栏那一条不归页面画，
    // 露出的是窗口底色。padding 只负责把内容让开，铺满是另一回事。
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
  }
}
