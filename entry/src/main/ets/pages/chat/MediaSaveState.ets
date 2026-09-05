// 媒体保存/下载簇：查看器"保存到相册"单槽等待 + 新消息自动保存队列 + 文档
// 下载后自动打开/另存。saveMediaTo/saveViewerMedia/processAutomaticGallerySave
// /openDownloadedFile/onFileTap/onFileSave 六个方法，连同 B4「原地分相」拆出
// 的 landPendingGallerySave/landPendingFileOpen 合并为 onSnapshot。从
// ChatPage 整体搬出（B15 批）。
//
// 【为什么这里不是 @ObservedV2】
// 六个字段（autoSavePendingIds/autoSaveInFlight/pendingGallerySaveId/
// pendingGallerySaveProgress/pendingFileOpenId/fileOpenInFlightId）没有一个
// 是 `@Local`，没有任何 build() 直接读它们——它们只是三对"等待句柄 + 进度/
// 并发闸门"，纯粹的异步状态记账。与 AttachActions（B12）同一个判断：本类是
// **普通类**，不写 @ObservedV2，字段不加 @Trace，类里不声明 @Monitor。
//
// 【getContext(this) 全部换成 host.context()——与 AttachActions 同一个例外】
// 本簇范围内 `getContext(this) as common.UIAbilityContext` 出现在
// saveViewerMedia（1 处）、landPendingGallerySave 的两个成功分支（2 处，
// 现并入 onSnapshot）、openDownloadedFile（1 处）、onFileSave（2 处），共 6
// 处，全部改成 `this.host.context()`。理由与 AttachActions.ets 文件头
// 「getContext(this) 一共 6 处」一节相同：`UIAbilityContext` 在同一个
// Ability 生命周期内是稳定值，页面在 `aboutToAppear` 调 `bind()` 时把它
// 求值一次、闭包成常量传进来，不是每次现读一个活字段——是"控制器不缓存页面
// 值"这条铁律的同一个既有例外，不是本批新开的口子。
//
// 【this.entryById(this.viewerMsgId) / this.messages.find(...) / this.messages
// 三处不同的"查消息"，对应三个不同的宿主取值器，不合并】
// - saveViewerMedia 原文是 `this.entryById(this.viewerMsgId)`
//   （entryById 用 findIndex+下标取值，找不到回 null）——经
//   `host.viewerEntry()` 一次性拿到结果，本类不需要知道 viewerMsgId 或
//   entryById 的存在，也不必分两步现取。
// - onFileTap/onFileSave 原文是 `this.messages.find((x) => x.id ===
//   messageId)`（数组 `.find`，找不到回 `undefined`）——经
//   `host.findMsg(messageId)` 现取，返回类型原样保持 `MessageEntry |
//   undefined`，判据 `m === undefined` 逐字不改。
// - processAutomaticGallerySave 的两处递归续体原文是
//   `this.processAutomaticGallerySave(this.messages)`（读的是**页面当下最新
//   的** `this.messages`，不是发起这次保存时传入的 `list` 参数——已在侦察
//   报告 (B) 核实：`saveMediaToGallery` 的 Promise 落地时页面可能已经收到
//   更新的快照）——经 `host.latestMessages()` 每次现取，不把参数 `list`
//   闭包捕获后继续往下传，否则会改变"总是读最新页面状态"的原语义。
// 三者字面上都是"从消息表里找/取"，但取值方式、返回类型、new/旧快照语义都
// 不同，因此拆成三个独立的宿主方法，不合并成一个万能取值器。
//
// 【store 在 saveViewerMedia/onFileTap/onFileSave 里各自 `const store =
// host.store()` 现取一次，不是缓存】
// 原文里 `this.store` 在同一个方法内被读两次的地方（例如 onFileTap 先在
// 入口守卫判 `this.store === null`，再在下面调 `this.store.pauseFileDownload
// (...)`），本类改成方法开头 `const store = this.host.store();` 读一次、
// 方法体内复用这个局部变量——两次读的是同一次 `host.store()` 调用结果，
// 整个方法体都在同一次同步执行栈内跑完，中间不经过任何 await/微任务边界，
// 与原文分两次读 `this.store` 的效果完全等价，不是"控制器缓存页面值"。
// 这与 AttachActions 自己方法体内 `const store = this.host.store();` 的写法
// 一致。
//
// 【onSnapshot(list, store, autoScope) 吞并了原 consumeLiveIncomingMediaAndCommands
// 的入队那一段——遗留给下一批的接线顺序问题，本批不下结论】
// 原 `consumeLiveIncomingMediaAndCommands(store)`（原 2928 行，2662 处调用）
// 同时做两件不相干的事：① 把这次快照新出现的 `store.
// consumeLiveIncomingMediaIds()` 在 `autosaveEnabled(autoScope)` 为真时去重
// 入队进 `autoSavePendingIds`；② 探测是否要 `command.ensureCommandsLoaded()`
// （B14 的命令面板控制器，不属于本簇）。本类的 `onSnapshot` 只吞并①（连同
// `autoScope` 的计算逻辑一并作为参数交给调用方），②继续留在页面原地。
// 但原代码里①在 `onMessagesSnapshot` 内的调用时机（原 2662 行）早于
// `landPendingGallerySave`/`landPendingFileOpen`（原 2668/2669 行），中间还
// 隔着 `applyInitialOrFollowLanding`/`consumeJumpToLatestIntent`/
// `scheduleNewerTailRefresh` 三次调用。`onSnapshot` 内部把①放在最前、
// 紧接着才是原 `landPendingGallerySave`/`landPendingFileOpen` 的方法体，这
// 保留了①相对于②③④的顺序不变，但**没有**、也不能替下一批决定接线进
// `ChatPage.onMessagesSnapshot` 时该把整个 `onSnapshot` 调用点放在原 2662
// 的位置（这样③④会被推到 onSnapshot 之后，与原顺序不同）还是原 2668/2669
// 的位置（这样①会比③④晚执行，与原顺序不同）——两种接法都会改变①与
// ③④的相对顺序，需要下一批实施时结合③④是否读写 `autoSavePendingIds`/
// `pendingGallerySaveId`/`pendingFileOpenId`（逐行核对过，三者都不读写这
// 六个字段）来判断这个顺序差异是否可观察。本批只提供方法，不改
// ChatPage.ets，因此不下结论，留給接线批次核实。
//
// 【dispose() 的 8 行 vs 7 行：musicQueue.reset() 不属于本簇】
// 原 `aboutToDisappear` 全链路对本簇字段的清理集中在
// `disposeTimersAndSeqGuards`（原 3665-3672 行）：
//   pendingGallerySaveId=0 → pendingGallerySaveProgress.dispose() → 置空 →
//   pendingFileOpenId=0 → fileOpenInFlightId=0 → musicQueue.reset() →
//   autoSavePendingIds=[] → autoSaveInFlight=false
// 中间那一句 `musicQueue.reset()`（原 3670 行）操作的是页面另一个字段
// `MusicQueue`，与本簇的六个字段无关，不属于 MediaSaveState 的搬迁范围，
// 因此 dispose() 只保留其余 7 行，顺序不变（跳过 musicQueue 那一行，不代表
// 遗漏——它继续留在页面 aboutToDisappear 里原地执行）。没有定时器句柄需要
// 清理（本簇原本就没有 setTimeout/setInterval，侦察报告 (A) 已确认），
// dispose() 不新增 clearTimeout。
//
// 【与 AttachActions/JumpFlashState 同款约定】
// per-ChatPage 字段初始化器 new，绝非模块级单例；宿主接口全是箭头函数
// 取值器/动作回调，现取不缓存（`context` 一次性求值的例外见上）；类中不
// 声明 @Monitor；未 bind 时的空宿主字段类型非空，占位值在页面 bind() 完成
// 前不会被真正用到；`private` 只标在字段与仅供内部调用的方法上，被页面
// 外部调用的方法（onFileTap/onFileSave/saveViewerMedia/onSnapshot/
// bind/dispose）不加访问修饰符。

import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { MessageStore } from '../../store/MessageStore';
import { MessageEntry } from '../../store/MessageEntry';
import { mediaEntryIsPhoto, mediaEntryIsVideo } from '../../util/mediaEntryKind';
import { FileSaveProgress, saveMediaToGallery } from '../../util/mediaSaver';
import {
  DownloadSaveNotification, downloadSaveService
} from '../../services/DownloadSaveNotification';
import { openLocalFile } from '../../util/openLocalFile';
import { fileOpenMimeType } from '../../util/fileMessage';
import { autosaveEnabled } from '../../store/AppSettings';
import { str } from '../../util/strings';
import { logE } from '../../util/log';

// 宿主（ChatPage）暴露给控制器的那一小片接口，全是箭头函数字段——取值器读
// 页面当下的真值，本类不缓存。仿 AttachActions 的 AttachActionsHost。
export interface MediaSaveStateHost {
  // UIAbilityContext。**唯一例外**：页面在 `aboutToAppear` 调 `bind()` 时把
  // `getContext(this) as common.UIAbilityContext` 求值一次、闭包成常量传进
  // 来——理由见文件头「getContext(this) 全部换成 host.context()」一节。
  context: () => common.UIAbilityContext;
  // 当前 MessageStore；路由切换途中可能为 null。
  store: () => MessageStore | null;
  // 当前会话 id。saveViewerMedia/onFileSave 里 `downloadSaveService.
  // saveRemoteFile(ctx, fileId, this.chatId, ...)` 用它。
  chatId: () => number;
  // 对应原 `this.entryById(this.viewerMsgId)`——查看器当前展示的那条消息，
  // 找不到回 null。仅 saveViewerMedia 使用。
  viewerEntry: () => MessageEntry | null;
  // 对应原 `this.messages.find((x) => x.id === messageId)`——按 id 在页面
  // 当前消息列表里查一条，找不到回 undefined（与数组 `.find` 原生返回类型
  // 一致，不改成 null）。onFileTap/onFileSave 使用。
  findMsg: (messageId: number) => MessageEntry | undefined;
  // 对应原 `this.messages`——页面当下最新的消息列表（不是调用时传入的
  // `list` 参数）。仅 processAutomaticGallerySave 的两处递归续体使用，每次
  // 现取，不缓存、不把 `list` 闭包捕获后继续往下传。
  latestMessages: () => MessageEntry[];
}

export class MediaSaveState {
  // ——— 内部机件：普通类，字段都不加装饰器 ———

  // 查看器"保存到相册"单槽等待句柄 + 其进度通知。
  private pendingGallerySaveId: number = 0;
  private pendingGallerySaveProgress: DownloadSaveNotification | null = null;
  // 新消息自动保存到相册的队列 + in-flight 闸门。
  private autoSavePendingIds: number[] = [];
  private autoSaveInFlight: boolean = false;
  // 文档下载后自动打开的等待句柄 + in-flight 闸门。
  private pendingFileOpenId: number = 0;
  private fileOpenInFlightId: number = 0;

  // 未 bind 时的空宿主：字段类型非空，且控制器在 aboutToAppear 之前就已经被
  // 构造出来（页面的字段初始化器 new）。取值器返回的都是「什么都还没有」的
  // 值；`context` 用一个空对象强转占位——真实调用发生在消息快照到达/用户
  // 点开查看器之后，严格晚于页面 bind() 完成，这个占位值永远不会被真正
  // 用到。
  private host: MediaSaveStateHost = {
    context: (): common.UIAbilityContext => ({} as common.UIAbilityContext),
    store: (): MessageStore | null => null,
    chatId: (): number => 0,
    viewerEntry: (): MessageEntry | null => null,
    findMsg: (_messageId: number): MessageEntry | undefined => undefined,
    latestMessages: (): MessageEntry[] => []
  };

  // ChatPage.aboutToAppear 里调一次。
  bind(host: MediaSaveStateHost): void {
    this.host = host;
  }

  // Viewer "保存到相册": photos save right away (full-res preferred); a video
  // that isn't fully local yet starts its download and saves automatically on
  // completion (see the pendingGallerySaveId check in the store subscription).
  // 保存到相册还是任意文件夹，由菜单里点的是哪一项决定（issue #97/#65）。
  private saveMediaTo(ctx: common.UIAbilityContext, path: string, isVideo: boolean,
    fileName: string, toFiles: boolean, progress?: FileSaveProgress): void {
    if (toFiles) {
      const name: string = fileName.trim() !== ''
        ? fileName : path.substring(path.lastIndexOf('/') + 1);
      downloadSaveService.saveDownloadedFile(ctx, path, name);
      return;
    }
    saveMediaToGallery(ctx, path, isVideo, progress);
  }

  saveViewerMedia(toFiles: boolean): void {
    const e = this.host.viewerEntry();
    if (e === null) {
      return;
    }
    const ctx = this.host.context();
    if (mediaEntryIsVideo(e)) {
      const displayName: string = e.videoFileName.trim() !== ''
        ? e.videoFileName : str('storage_video');
      if (e.videoPath !== '') {
        this.saveMediaTo(ctx, e.videoPath, true, e.videoFileName, toFiles,
          toFiles ? undefined : new DownloadSaveNotification(displayName));
      } else {
        if (toFiles) {
          downloadSaveService.saveRemoteFile(
            ctx, e.videoFileId, this.host.chatId(), e.id, displayName);
          promptAction.showToast({
            message: $r('app.string.cp_video_downloading_save'), duration: 2500
          });
          return;
        }
        this.pendingGallerySaveProgress?.dispose();
        this.pendingGallerySaveProgress =
          new DownloadSaveNotification(displayName, e.videoFileId);
        this.pendingGallerySaveId = e.id;
        const store = this.host.store();
        if (store !== null) {
          store.requestVideoDownload(e.id, true, e.videoFailed);
        }
        promptAction.showToast({ message: $r('app.string.cp_video_downloading_save'), duration: 2500 });
      }
      return;
    }
    if (e.photoFullPath !== '') {
      this.saveMediaTo(ctx, e.photoFullPath, false, '', toFiles,
        toFiles ? undefined : new DownloadSaveNotification(str('storage_photo')));
      return;
    }
    if (e.photoFullFileId !== 0) {
      if (toFiles) {
        downloadSaveService.saveRemoteFile(
          ctx, e.photoFullFileId, this.host.chatId(), e.id, str('storage_photo'));
        promptAction.showToast({
          message: $r('app.string.cp_photo_downloading_save'), duration: 2200
        });
        return;
      }
      this.pendingGallerySaveProgress?.dispose();
      this.pendingGallerySaveProgress =
        new DownloadSaveNotification(str('storage_photo'), e.photoFullFileId);
      this.pendingGallerySaveId = e.id;
      const store = this.host.store();
      if (store !== null) {
        store.requestFullPhoto(e.id, e.photoFullFailed);
      }
      promptAction.showToast({ message: $r('app.string.cp_photo_downloading_save'), duration: 2200 });
      return;
    }
    if (e.photoPath !== '') {
      this.saveMediaTo(ctx, e.photoPath, false, '', toFiles,
        toFiles ? undefined : new DownloadSaveNotification(str('storage_photo')));
    } else {
      promptAction.showToast({ message: $r('app.string.cp_photo_not_available'), duration: 1800 });
    }
  }

  private processAutomaticGallerySave(list: MessageEntry[]): void {
    if (this.autoSaveInFlight || this.autoSavePendingIds.length === 0) { return; }
    let target: MessageEntry | undefined = undefined;
    let path: string = '';
    let video: boolean = false;
    for (const messageId of this.autoSavePendingIds) {
      const entry = list.find((item: MessageEntry): boolean => item.id === messageId);
      if (entry === undefined || entry.isOutgoing ||
        (entry.contentType !== 'photo' && entry.contentType !== 'video')) {
        this.autoSavePendingIds = this.autoSavePendingIds.filter((id: number): boolean => id !== messageId);
        continue;
      }
      if (entry.contentType === 'video') {
        if (entry.videoFailed) {
          this.autoSavePendingIds = this.autoSavePendingIds.filter((id: number): boolean => id !== messageId);
          continue;
        }
        if (entry.videoPath !== '') { target = entry; path = entry.videoPath; video = true; break; }
      } else {
        if (entry.photoFullFailed) {
          this.autoSavePendingIds = this.autoSavePendingIds.filter((id: number): boolean => id !== messageId);
          continue;
        }
        if (entry.photoFullPath !== '') { target = entry; path = entry.photoFullPath; break; }
        if (entry.photoFullFileId === 0 && entry.photoPath !== '') {
          target = entry; path = entry.photoPath; break;
        }
      }
    }
    if (target === undefined || path === '') { return; }
    const id = target.id;
    this.autoSavePendingIds = this.autoSavePendingIds.filter((value: number): boolean => value !== id);
    this.autoSaveInFlight = true;
    saveMediaToGallery(this.host.context(), path, video).then((): void => {
      this.autoSaveInFlight = false;
      this.processAutomaticGallerySave(this.host.latestMessages());
    }).catch((): void => {
      this.autoSaveInFlight = false;
      this.processAutomaticGallerySave(this.host.latestMessages());
    });
  }

  private openDownloadedFile(message: MessageEntry): void {
    if (message.videoPath === '' || this.fileOpenInFlightId !== 0) {
      return;
    }
    const messageId: number = message.id;
    this.fileOpenInFlightId = messageId;
    openLocalFile(
      this.host.context(),
      message.videoPath,
      fileOpenMimeType(message.videoFileName, message.videoMimeType)
    ).then((opened: boolean): void => {
      if (this.fileOpenInFlightId === messageId) {
        this.fileOpenInFlightId = 0;
      }
      if (!opened) {
        promptAction.showToast({
          message: $r('app.string.cp_no_app_for_file'),
          duration: 2200
        });
      }
    }).catch((caught: Object): void => {
      if (this.fileOpenInFlightId === messageId) {
        this.fileOpenInFlightId = 0;
      }
      logE(`MediaSaveState.openDownloadedFile failed: ${JSON.stringify(caught)}`);
      promptAction.showToast({ message: $r('app.string.cp_file_open_failed'), duration: 1800 });
    });
  }

  // Document card tap: an on-demand download retains the open intent, so the
  // file launches immediately when TDLib reports completion.
  onFileTap(messageId: number): void {
    const m = this.host.findMsg(messageId);
    const store = this.host.store();
    if (m === undefined || m.contentType !== 'file' || store === null) {
      return;
    }
    // Opening is page-scoped. Explicit saves are owned by downloadSaveService
    // and can continue independently if the page disappears.
    if (m.videoPath !== '') {
      this.pendingFileOpenId = 0;
      this.openDownloadedFile(m);
      return;
    }
    if (m.videoFileId === 0) {
      this.pendingFileOpenId = 0;
      promptAction.showToast({ message: $r('app.string.cp_file_unavailable'), duration: 1600 });
      return;
    }
    if (m.mediaDownloadActive) {
      // 下载中再点一下 = 暂停（issue #45 子项：下载开始后没法暂停取消）。
      // 已下的部分留着，下次点从断点继续。
      this.pendingFileOpenId = 0;
      store.pauseFileDownload(messageId);
      promptAction.showToast({ message: $r('app.string.cp_file_paused'), duration: 1500 });
      return;
    }
    this.pendingFileOpenId = messageId;
    store.requestVideoDownload(messageId, true, m.videoFailed);
    promptAction.showToast({
      message: m.videoFailed ? $r('app.string.cp_redownloading_file')
        : $r('app.string.cp_file_download_started'),
      duration: 1700
    });
  }

  // Document card save arrow: first asks for a public directory grant, then
  // exports into its Petrelgram child folder. Download and copy share one
  // progress notification so the hand-off is visible rather than a silent gap.
  onFileSave(messageId: number): void {
    const m = this.host.findMsg(messageId);
    const store = this.host.store();
    if (m === undefined || m.contentType !== 'file' || store === null) {
      return;
    }
    this.pendingFileOpenId = 0;
    if (m.videoPath !== '') {
      downloadSaveService.saveDownloadedFile(
        this.host.context(), m.videoPath, m.videoFileName);
      return;
    }
    if (m.videoFileId === 0) {
      promptAction.showToast({ message: $r('app.string.cp_file_unavailable'), duration: 1600 });
      return;
    }
    downloadSaveService.saveRemoteFile(
      this.host.context(),
      m.videoFileId, this.host.chatId(), messageId, m.videoFileName);
    promptAction.showToast({
      message: m.videoFailed ? $r('app.string.cp_redownload_then_save')
        : $r('app.string.cp_downloading_then_save'),
      duration: 2200
    });
  }

  // B4「原地分相」拆出的 landPendingGallerySave(list) + landPendingFileOpen
  // (list) 两个方法体，逐字合并进本方法；另吞并原
  // consumeLiveIncomingMediaAndCommands 里与本簇相关的入队那一段（autoScope
  // 由调用方算好传入）。三段各自的内部顺序、判据、分支逐字不改——合并顺序
  // 与接线到 ChatPage.onMessagesSnapshot 后的相对时序问题，见文件头专项
  // 说明，本批不下结论。
  onSnapshot(list: MessageEntry[], store: MessageStore, autoScope: string): void {
    // 原 consumeLiveIncomingMediaAndCommands（原 2928-2952 行）里与 command
    // 面板加载判断混在一起的入队那六行，抽出搬进本类；command 面板探测
    // （this.command.commandLoadState/ensureCommandsLoaded()）继续留在页面。
    const liveMediaIds: number[] = store.consumeLiveIncomingMediaIds();
    if (autosaveEnabled(autoScope)) {
      for (const mediaId of liveMediaIds) {
        if (this.autoSavePendingIds.indexOf(mediaId) < 0) {
          this.autoSavePendingIds.push(mediaId);
        }
      }
    }
    // landPendingGallerySave(list) 原文（B4 拆出，原 3099-3134 行）。
    // A viewer item queued for gallery save finished downloading — always
    // prefer the original photo rather than silently saving its thumbnail.
    if (this.pendingGallerySaveId !== 0) {
      const pe = list.find((m: MessageEntry) => m.id === this.pendingGallerySaveId);
      if (pe !== undefined) {
        if (mediaEntryIsVideo(pe) && pe.videoPath !== '') {
          this.pendingGallerySaveId = 0;
          const progress: DownloadSaveNotification | undefined =
            this.pendingGallerySaveProgress ?? undefined;
          this.pendingGallerySaveProgress = null;
          this.saveMediaTo(this.host.context(), pe.videoPath, true,
            pe.videoFileName, false, progress);
        } else if (mediaEntryIsVideo(pe) && pe.videoFailed) {
          this.pendingGallerySaveId = 0;
          this.pendingGallerySaveProgress?.downloadFailed();
          this.pendingGallerySaveProgress = null;
          promptAction.showToast({ message: $r('app.string.cp_video_download_failed'), duration: 1800 });
        } else if (mediaEntryIsPhoto(pe) && pe.photoFullPath !== '') {
          this.pendingGallerySaveId = 0;
          const progress: DownloadSaveNotification | undefined =
            this.pendingGallerySaveProgress ?? undefined;
          this.pendingGallerySaveProgress = null;
          this.saveMediaTo(this.host.context(), pe.photoFullPath, false,
            '', false, progress);
        } else if (mediaEntryIsPhoto(pe) && pe.photoFullFailed) {
          this.pendingGallerySaveId = 0;
          this.pendingGallerySaveProgress?.downloadFailed();
          this.pendingGallerySaveProgress = null;
          promptAction.showToast({ message: $r('app.string.cp_photo_download_failed'), duration: 1800 });
        }
      }
    }
    this.processAutomaticGallerySave(list);
    // landPendingFileOpen(list) 原文（B4 拆出，原 3135-3151 行）。
    // A document queued for "save as" finished downloading — open the picker.
    if (this.pendingFileOpenId !== 0) {
      const openEntry: MessageEntry | undefined =
        list.find((m: MessageEntry): boolean => m.id === this.pendingFileOpenId);
      if (openEntry === undefined || openEntry.contentType !== 'file') {
        this.pendingFileOpenId = 0;
      } else if (openEntry.videoFailed) {
        this.pendingFileOpenId = 0;
        promptAction.showToast({ message: $r('app.string.cp_file_download_failed'), duration: 1800 });
      } else if (openEntry.videoPath !== '') {
        this.pendingFileOpenId = 0;
        this.openDownloadedFile(openEntry);
      }
    }
  }

  // ChatPage.aboutToDisappear 全链路对本簇的清理集中在
  // disposeTimersAndSeqGuards（原 3665-3672 行，跳过其中与本簇无关的
  // musicQueue.reset() 那一句）——见文件头「dispose() 的 8 行 vs 7 行」
  // 一节，逐字对应，不新增（本簇没有定时器句柄可清）、不少做。
  dispose(): void {
    this.pendingGallerySaveId = 0;
    this.pendingGallerySaveProgress?.dispose();
    this.pendingGallerySaveProgress = null;
    this.pendingFileOpenId = 0;
    this.fileOpenInFlightId = 0;
    this.autoSavePendingIds = [];
    this.autoSaveInFlight = false;
  }

  // ChatPage.resetScrollSession（**换会话**，不是页面销毁）里那两行
  // `this.pendingFileOpenId = 0; this.fileOpenInFlightId = 0;` 的搬迁落点。
  //
  // 【为什么它必须和 dispose() 分成两个口子】
  // 本簇六个字段里，只有这一对会在换会话时单独清空；另外四个
  // （pendingGallerySaveId / pendingGallerySaveProgress / autoSavePendingIds /
  // autoSaveInFlight）在这条路径上**从来不动**。用 dispose() 顶替会连带清掉
  // 它们、还会 dispose 掉一个可能仍在等待的相册保存进度通知——那是原代码在这个
  // 调用点从没做过的事，是行为变更。
  //
  // 【不清会怎样】"打开这个文档"的意图是**跨会话**挂着的。TDLib 的消息 id 是
  // 每会话独立编号的（resetScrollSession 上方那段原注释点名过这个危险）：A 会话
  // 里点了一个还没下完的文档、切到 B 会话，B 的第一张快照会拿这个陈旧 id 去
  // `list.find(...)`；万一 B 里恰好有同号消息且是 file、videoPath 非空，就会
  // 拉起一个用户从没点过的文件。fileOpenInFlightId 同理，会把新会话第一次
  // "已下载→打开"无声吞掉。
  resetFileOpenIntent(): void {
    this.pendingFileOpenId = 0;
    this.fileOpenInFlightId = 0;
  }
}
