// 附件面板分发表 runAttachAction，以及它背后挂的媒体/文件/音频/位置/骰子/
// 联系人/投票/录像笔记等动作方法，连同长按气泡「替换媒体」replaceMedia，
// 共 18 个方法。从 ChatPage 整体搬出（B12 批）。
//
// 【为什么这里不是 @ObservedV2】
// 与 ComposerSession/ChatOverlayState 等前几批不同，本簇不持有任何驱动 UI
// 重渲染的状态——它只是"一堆异步动作方法"的集合，唯一的两个内部字段
// （mediaCopySeq/mediaPickerOpen）纯粹是并发闸门，从不被任何 build() 读取。
// 因此本类是**普通类**：不写 @ObservedV2，字段不写 @Trace，类里不声明
// @Monitor（这条对本类其实是空话——它压根没有可被监听的字段）。
//
// 【pendingMedia / diceSheetOpen / atBottom 为什么都不搬】
// pendingMedia 是发送路径与本簇共写的暂存区（sendPendingMedia 等留页面的
// 逻辑也要读写它），继续留页面；diceSheetOpen 是页面 `@Local`——
// `bindSheet($$this.diceSheetOpen, ...)` 的 `$$` 双向绑定对 `@Trace` 的支持
// 本仓没有编译验证过，且这个 `bindSheet` 必须挂在 `bottomDock` 节点上（方案
// §4/B12），所以宁可让控制器经 host 的一个 setter 写它，也不把它升格进类里；
// atBottom 同理留页面 `@Local`，本簇五处只写不读，经 `host.setAtBottom` 中转。
// 三者都只经宿主的取值器/动作回调读写，本类不持有引用、不存影子拷贝。
//
// 【getContext(this) 一共 6 处，全部换成 host.context()——不是只有 2 处】
// 本簇范围内 `getContext(this)` 出现在 copyUriToCache、collectPickedMedia、
// pickAndSendAudio、startLiveLocation、sendCurrentLocation、pickAndSendFile
// 六个方法里，全部统一改成 `this.host.context()`。这是"控制器不缓存页面值"
// 这条铁律的**唯一例外**：`UIAbilityContext` 在同一个 Ability 生命周期内是
// 稳定值，页面在 `aboutToAppear` 调 `bind()` 时把 `getContext(this) as
// common.UIAbilityContext` **求值一次**、闭包成 `context: () => ctx` 传进来，
// 不是像其余取值器那样每次现读一个 `@Local`/普通字段。从本类的视角看，
// 它仍然只是"调 `this.host.context()`"这一个取值器调用，和其余取值器长得
// 一样，只是页面那边闭包捕获的是一次性求值的常量而不是活字段。
//
// 【chooseLocationKind 用的是 this.getUIContext()，不是 getContext(this)——
// 第 7 个、类型不同的取值点，不能塞进 context()】
// `getUIContext().getPromptAction().showActionMenu(...)` 拿到的是
// `UIContext`（ArkUI 侧、绑定当前窗口/分栏的弹窗入口），`getContext(this)`
// 拿到的是 `UIAbilityContext`（Ability 侧），两者不能互换、也不能简单改成
// 模块级静态 `promptAction.showActionMenu(...)`——那样在分栏场景下弹窗可能
// 弹到错误的窗口上，是会改变行为的替换，不是逐字搬迁。因此本类单独开了
// `host.uiContext()` 这个取值器，和 `host.context()` 并列、互不影响。
//
// 【mediaPickerOpen 的复位位置逐字保持在原来那一行，不挪到 collect 之后】
// `pickMedia` 里 `photoPicker.select().then()` 一进入就把 `mediaPickerOpen`
// 复位成 `false`（原文第一行），而不是等 `collectPickedMedia().then(
// applyPickedMedia)` 那条异步链（实况照片逐张 `await exportLivePhotoMotion`，
// 耗时随张数线性增长）跑完才复位。挪到后面会在整个实况照片导出期间把
// `pickMedia` 入口守卫锁死，挡住用户在导出还没跑完时发起的第二次选择——
// 现状是选择器一关（图集 UI 消失）就立刻放行，导出工作在后台继续跑。
// `replaceMedia` 的 `.then`/`.catch` 复位写法与此对称，同样保持原位。
//
// 【mediaCopySeq 必须是同一个字段，不能被 copyUriToCache/collectPickedMedia
// 各自持有一份】
// 两条路径（`pickMedia→collectPickedMedia`与`pickAndSendFile/pickAndSendAudio
// /replaceMedia→copyUriToCache`）可能在同一会话生命周期内交替触发，若各自
// 独立计数，`cacheDestPath`/`exportLivePhotoMotion` 生成的目标文件名就可能
// 撞号，破坏"去重"这个唯一目的。本类里两处自增点共享同一个私有字段。
//
// 【composerSending / draft / composerFocused：page 留字段，本簇经取值器/
// 动作回调读写】
// `composerSending` 是 4 条发送路径共享的并发闸门（B9 的所有权裁决未动），
// `pickMedia` 只读它判断能不能开选择器；`draft` 每键入一次写、留页面，
// `pickAndSendAudio`/`pickAndSendFile` 发送后读它拼文案、发完清空，经
// `host.draftText()`/`host.clearDraft()` 中转；`composerFocused` 同样留页面
// `@Local`，`openVideoNoteRecorder` 单独写它一次——**这一行不是
// `stopEditing()` 的副作用**（页面另外三处 `composerController.stopEditing()`
// + `composerFocused=false` 组合彼此独立，不应该被这里新增的一个合并回调
// 意外牵连），所以本类保留两条独立的 host 调用
// （`host.stopEditing()`、`host.setComposerFocused(false)`），不合并成一个。
//
// 【overlayState 四个 sheet 开关：控制器不持有 ChatOverlayState 引用，
// 经宿主转发 setSheet】
// `openScheduledSheet`/`openPollComposer`/`openVideoNoteRecorder`（其中一句）/
// `openContactPicker` 原来是 `this.overlayState.showXxxSheet = true` 的直写。
// 控制器之间不允许互相持有引用（B8 起立的规矩），本类只经
// `host.setSheet(kind, show)` 转发，页面侧把它实现为
// `(kind, show) => { this.overlayState.setSheet(kind, show); }`——
// `ChatOverlaySheetKind`/`setSheet` 都是 `ChatOverlayState`（B11）已有的
// 公开面，这里直接复用其 kind 类型，不重复定义一份。
//
// 【openScheduledSheet 是死代码，原样带走，不顺手接调用点】
// 全仓（含 `util/attachActions.ets` 的 `ATTACH_KEYS`/`ORDER`）都没有
// `'schedule'` 这个 key，`runAttachAction` 的分发表里也没有对应分支——这个
// 方法在当前代码里不可达。搬迁时原样带走（依然是死代码），不新增调用点，
// 那是行为变更，超出本批范围。
//
// 【pendingMedia 的"读"与"写"两个不同的 toast 时机，不能合并】
// `pickMedia` 开选择器前算 `room = PENDING_MEDIA_MAX - host.pendingMediaCount()`，
// 房间不够直接拒绝并提示（dropped 恒为 0，"选之前就没位置了"）；
// `applyPickedMedia` 选完之后经 `host.appendPendingMedia(items)` 写入，若
// 返回值（截断张数）大于 0 再提示一次（"选完发现超了，截了几张"）。两条
// `cp_pending_media_full` 文案是原文本来就有的两处独立判断，逐字保留、
// 不合并成一次。
//
// 【toast 不进 host 接口，本类自己 import promptAction】
// 与 `ComposerSession`/`ChatOverlayState` 同样的先例：`promptAction` 是
// HarmonyOS SDK 提供的模块级全局 API（不是页面自己 new 出来的实例），
// 搬进新文件后原样 `import` 不会引入多实例串扰问题；16 处不同的
// message/duration 组合若都经宿主转发，只会为一个笨重的转发签名增加间接层，
// 没有收益。
//
// 【composerController 是 TextAreaController，不是 ComposerSession】
// `openVideoNoteRecorder` 里的 `this.composerController.stopEditing()` 操作的
// 是 ArkUI 内建的 `TextAreaController`（页面另有同名相近字段
// `this.composer: ComposerSession`，两者是完全不同的两个对象）。
// `host.stopEditing()` 必须转发到 `this.composerController.stopEditing()`，
// 不要接到 `ComposerSession` 上。
//
// 【dispose() 为什么是空的】
// 逐行核对过 `aboutToDisappear` 全链路（`disposeInitialStageAndTgs`/
// `disposePlaybackAndSlots`/`persistDraftAndViewport`/
// `disposeTimersAndSeqGuards`/`stopVoicePlaybackKeepingMusic`/
// `disposeSubscriptionsInOrder`/`closeStores`），原代码对
// `mediaPickerOpen`/`mediaCopySeq` 在页面销毁时**没有任何清理**——
// `mediaPickerOpen` 若恰好是 `true` 就一直留着，`mediaCopySeq` 随实例一起被
// GC，两者都不产生可观察副作用（整个 ChatPage 实例本身也在同一时刻被丢弃）。
// 按"不许凭感觉新增清理"的纪律，这里的 `dispose()` 保持空实现，不替原代码
// 编造一份它从来没有过的收尾逻辑。仍然提供这个方法只是为了和其余控制器统一
// 的 bind/dispose 生命周期形状。
//
// 【与 ComposerSession/ChatOverlayState 同款约定】
// per-ChatPage 字段初始化器 new，绝非模块级单例；宿主接口全是箭头函数
// 取值器/动作回调，现取不缓存（`context`/`uiContext` 见上方专门说明）；
// 方法不加访问修饰符（与两个先例一致，只有字段标 `private`）。

import { common, abilityAccessCtrl, Permissions } from '@kit.AbilityKit';
import { geoLocationManager } from '@kit.LocationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { promptAction, UIContext } from '@kit.ArkUI';
import { MessageStore, MediaSendItem } from '../../store/MessageStore';
import { MessageEntry } from '../../store/MessageEntry';
import { cacheDestPath, isVideoPath } from '../../util/mediaPick';
import { LivePhotoExport, exportLivePhotoMotion } from '../../util/movingPhotoPick';
import { logE } from '../../util/log';
import { plural, str } from '../../util/strings';
import { liveLocation } from '../../services/LiveLocationService';
import { withLocationPermission } from '../../util/locationActions';
import { TdError } from '../../tdkit/TdTypes';
import { COLOR_TEXT_PRIMARY } from '../../util/theme';
import { PENDING_MEDIA_MAX } from '../../util/pendingMedia';
import { ChatOverlaySheetKind } from './ChatOverlayState';

// collectPickedMedia 的返回：可发送项 + 读不出来被跳过的张数。原样复制自
// ChatPage.ets 里同名的模块级 private 接口，不导出。
interface PickedMedia {
  items: MediaSendItem[];
  skipped: number;
}

// 宿主（ChatPage）暴露给控制器的那一小片接口，全是箭头函数字段——取值器读
// 页面当下的真值，动作回调把副作用交回页面执行。仿 ComposerSession 的
// ComposerSessionHost / ChatOverlayState 的 ChatOverlayStateHost。
//
// 两条纪律（与其余控制器一致）：
// 1. 这里只放**取值器**/动作回调，不放页面的 @Local/状态引用。控制器不缓存
//    页面的值，每次要用就现取——`context` 是唯一例外（见文件头说明）。
// 2. pendingMedia/atBottom/diceSheetOpen/draft/composerFocused/
//    composerSending 等留页面的字段，本类只经这里的取值器/动作回调读写，
//    不在本类里存一份影子拷贝。
export interface AttachActionsHost {
  // UIAbilityContext。**唯一例外**：页面在 `aboutToAppear` 调 `bind()` 时把
  // `getContext(this) as common.UIAbilityContext` 求值一次、闭包成常量传进
  // 来，不是像其余取值器那样每次现读一个活字段——`UIAbilityContext` 在同一个
  // Ability 生命周期内本来就是稳定值。copyUriToCache/collectPickedMedia/
  // pickAndSendAudio/startLiveLocation/sendCurrentLocation/pickAndSendFile
  // 六处 `getContext(this)` 全部改经这里取。
  context: () => common.UIAbilityContext;
  // UIContext（与上面的 UIAbilityContext 是两个不同的东西）。仅
  // chooseLocationKind 一处使用，对应原 `this.getUIContext()`——Component
  // 基类能力，本类是普通类没有，经这个取值器现取（不是绑定时求值一次，
  // 因为它不像 `context` 那样有"同 Ability 生命周期内稳定"这条依据）。
  uiContext: () => UIContext;
  // 当前会话 id。仅 startLiveLocation 用，对应
  // `liveLocation.start(this.chatId, ...)`——本簇范围内唯一读 chatId 的地方。
  chatId: () => number;
  // 当前 MessageStore；路由切换途中可能为 null。
  store: () => MessageStore | null;
  // 按 id 在页面当前消息列表（`this.messages`）里查一条，找不到返回 null。
  // replaceMedia 用它取被替换消息的原文（caption）。
  findMsg: (messageId: number) => MessageEntry | null;
  // 当前已暂存的媒体张数（`this.pendingMedia.length`）。pickMedia 用它算
  // "选择器还能再放几张"（`PENDING_MEDIA_MAX - pendingMediaCount()`），在
  // 真正打开选择器**之前**判断，不经 appendPendingMedia 那条写入路径。
  pendingMediaCount: () => number;
  // 把选好的媒体追加进页面的暂存区（`appendPendingMedia(this.pendingMedia,
  // items)` 然后 `this.pendingMedia = merged.items`），返回被截断的张数
  // （原 `merged.dropped`）供 applyPickedMedia 决定要不要再提示一次「截了
  // 几张」。pendingMedia 是发送路径共写的域，本类不持有引用，只经这一读一写
  // 两个入口（`pendingMediaCount`/`appendPendingMedia`）触达。
  appendPendingMedia: (items: MediaSendItem[]) => number;
  // 发送闸门当下的值（页面 `@Local composerSending`，B9 所有权裁决未动，
  // 4 条发送路径共享的一把锁）。pickMedia 入口守卫只读它。
  composerSending: () => boolean;
  // 输入框当下的草稿文本（页面 `@Local draft`，42 处引用，留页面）。
  // pickAndSendAudio/pickAndSendFile 发送后拼 caption 要读它。
  draftText: () => string;
  // 发送后清空草稿（对应原 `this.draft = ''`）。与 `draftText()` 成对使用，
  // 不合并成一个"读并清空"的方法——原文本来就是先读 `.trim()` 传给
  // `store.sendXxx`，成功与否都紧接着清空，两步逐字保留。
  clearDraft: () => void;
  // 写页面 `@Local atBottom`（本簇五处只写不读）。
  setAtBottom: (value: boolean) => void;
  // 收起附件面板（对应原 `this.closeAttachPanel()`）。runAttachAction 分发前
  // 先调用它，逐字保留原顺序。
  closeAttachPanel: () => void;
  // 收起系统输入法编辑态（对应原 `this.composerController.stopEditing()`，
  // 操作的是 ArkUI 内建 `TextAreaController`，**不是** ComposerSession——两者
  // 页面里同时存在、容易看错，务必转发到前者）。
  stopEditing: () => void;
  // 写页面 `@Local composerFocused`（对应原 `openVideoNoteRecorder` 里独立的
  // `this.composerFocused = false` 那一行）。**不要**把这一步并进
  // `stopEditing()` 里一起做——页面另外三处
  // `composerController.stopEditing()` + `composerFocused=false` 组合彼此
  // 独立，合并成一个回调会让它们意外被牵连。
  setComposerFocused: (value: boolean) => void;
  // 停止当前录音（对应原 `this.cancelRecording()`，页面方法，本簇不拥有
  // 录音状态机）。openVideoNoteRecorder 用它避免录音与圆形视频录制撞车。
  cancelRecording: () => void;
  // 反应/转发/投票/联系人/录像笔记/定时消息六个 sheet 开关的统一写入口
  // （`ChatOverlayState.setSheet`，B11 已有的公开面，这里直接复用其
  // `ChatOverlaySheetKind`，不重复定义）。控制器之间不互相持有引用（B8 起
  // 立的规矩），页面侧把它实现成
  // `(kind, show) => { this.overlayState.setSheet(kind, show); }`。
  // openScheduledSheet/openPollComposer/openContactPicker 以及
  // openVideoNoteRecorder 里那一句都经它写。
  setSheet: (kind: ChatOverlaySheetKind, show: boolean) => void;
  // 写页面 `@Local diceSheetOpen`（`bindSheet($$this.diceSheetOpen, ...)` 的
  // `$$` 双向绑定必须留在页面、挂在 `bottomDock` 节点上，见文件头说明）。
  // showDiceMenu 传 `true`、sendDiceEmoji 传 `false`，一读一写对称成一个
  // setter，不拆成 open/close 两个方法。
  setDiceSheetOpen: (open: boolean) => void;
}

export class AttachActions {
  // ——— 内部机件：普通类，字段都不加装饰器 ———

  // 拷贝去重序号，copyUriToCache 与 collectPickedMedia 两处自增点共享同一份
  // （见文件头说明：不能拆成两份计数器，否则两条路径可能撞号）。
  private mediaCopySeq: number = 0;
  // 系统相册选择器的并发闸门。replaceMedia/pickMedia 各自维护自己的
  // 打开/复位时机（见文件头 mediaPickerOpen 专项说明），共用同一个字段。
  private mediaPickerOpen: boolean = false;

  // 未 bind 时的空宿主：字段类型非空，且控制器在 aboutToAppear 之前就已经被
  // 构造出来（页面的字段初始化器 new）。取值器返回的都是「什么都还没有」的
  // 值；`context`/`uiContext` 用一个空对象强转占位——真实调用发生在用户点开
  // 附件面板之后，严格晚于页面 bind() 完成，这两个占位值永远不会被真正用到。
  private host: AttachActionsHost = {
    context: (): common.UIAbilityContext => ({} as common.UIAbilityContext),
    uiContext: (): UIContext => ({} as UIContext),
    chatId: (): number => 0,
    store: (): MessageStore | null => null,
    findMsg: (_messageId: number): MessageEntry | null => null,
    pendingMediaCount: (): number => 0,
    appendPendingMedia: (_items: MediaSendItem[]): number => 0,
    composerSending: (): boolean => false,
    draftText: (): string => '',
    clearDraft: (): void => {},
    setAtBottom: (_value: boolean): void => {},
    closeAttachPanel: (): void => {},
    stopEditing: (): void => {},
    setComposerFocused: (_value: boolean): void => {},
    cancelRecording: (): void => {},
    setSheet: (_kind: ChatOverlaySheetKind, _show: boolean): void => {},
    setDiceSheetOpen: (_open: boolean): void => {}
  };

  // ChatPage.aboutToAppear 里调一次。
  bind(host: AttachActionsHost): void {
    this.host = host;
  }

  // Copy a picker URI into the sandbox so TDLib can read it; '' on failure.
  // Single copy path for every picker (media, document, audio): they used to
  // inline three near-copies of this, two of them without the sequence counter.
  private copyUriToCache(uri: string): string {
    try {
      const cacheDir = this.host.context().cacheDir;
      const dest = cacheDestPath(cacheDir, uri, ++this.mediaCopySeq, Date.now());
      const src = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      fs.copyFileSync(src.fd, dest);
      fs.closeSync(src);
      return dest;
    } catch (e) {
      logE(`AttachActions.copyUriToCache failed: ${e}`);
      return '';
    }
  }

  // 长按气泡「替换媒体」。唯一调用点在页面的 messageActions() 单例闭包工厂
  // 方法（气泡点击时才执行），不在本簇范围内，因此这里保持对外可见。
  replaceMedia(messageId: number): void {
    const msg = this.host.findMsg(messageId);
    const store = this.host.store();
    if (msg === null || store === null || this.mediaPickerOpen) { return; }
    this.mediaPickerOpen = true;
    const photoPicker = new photoAccessHelper.PhotoViewPicker();
    const opts = new photoAccessHelper.PhotoSelectOptions();
    opts.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_VIDEO_TYPE;
    opts.maxSelectNumber = 1;
    photoPicker.select(opts).then((res: photoAccessHelper.PhotoSelectResult): void => {
      this.mediaPickerOpen = false;
      if (res.photoUris.length === 0) { return; }
      const path = this.copyUriToCache(res.photoUris[0]);
      if (path === '') {
        promptAction.showToast({ message: $r('app.string.cp_cannot_read_file'), duration: 1600 });
        return;
      }
      store.editMediaAsync(messageId, path, isVideoPath(path), msg.text).then((): void => {
        promptAction.showToast({ message: $r('app.string.cp_media_replaced'), duration: 1500 });
      }).catch((e: TdError): void => {
        logE(`AttachActions.replaceMedia failed: ${e.message}`);
        promptAction.showToast({ message: $r('app.string.cp_replace_failed'), duration: 1700 });
      });
    }).catch((): void => { this.mediaPickerOpen = false; });
  }

  private pickMedia(): void {
    if (this.mediaPickerOpen || this.host.composerSending() || this.host.store() === null) {
      return;
    }
    // 选择器自己就按"还能再放几张"限制，好过让用户挑满九张再被截断。
    const room: number = PENDING_MEDIA_MAX - this.host.pendingMediaCount();
    if (room <= 0) {
      promptAction.showToast({
        message: str('cp_pending_media_full', PENDING_MEDIA_MAX, 0), duration: 2000
      });
      return;
    }
    this.mediaPickerOpen = true;
    const photoPicker = new photoAccessHelper.PhotoViewPicker();
    const opts = new photoAccessHelper.PhotoSelectOptions();
    opts.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_VIDEO_TYPE;
    opts.maxSelectNumber = room;
    photoPicker.select(opts).then((res: photoAccessHelper.PhotoSelectResult) => {
      this.mediaPickerOpen = false;
      if (res.photoUris.length === 0 || this.host.store() === null) {
        return;
      }
      // 实况照片要先把动态部分导出来（异步），所以收集这一步整体是异步的。
      this.collectPickedMedia(res.photoUris).then((picked: PickedMedia): void => {
        this.applyPickedMedia(picked.items, picked.skipped);
      });
    }).catch((e: Object) => {
      this.mediaPickerOpen = false;
      logE(`AttachActions.pickMedia failed: ${JSON.stringify(e)}`);
      promptAction.showToast({ message: $r('app.string.cp_cannot_open_picker'), duration: 1800 });
    });
  }

  // 选中的每一项 → 可发送项。实况照片发它的**动态部分**（带音轨的 mp4，文件名
  // 带标记）：别的客户端收到就是一段普通有声视频、照常播放，PG 靠文件名把它认回
  // 实况。协议约定见 util/livePhoto，导出见 util/movingPhotoPick。
  //
  // 逐个 await 而不是并发：requestMovingPhoto 背后是媒体库的解码与落盘，一次挑
  // 九张全并发只会互相抢资源；而一次选择里通常只有一两张是实况。
  private async collectPickedMedia(uris: string[]): Promise<PickedMedia> {
    const items: MediaSendItem[] = [];
    let skipped: number = 0;
    const ctx = this.host.context();
    for (const uri of uris) {
      const live: LivePhotoExport = await exportLivePhotoMotion(
        ctx, uri, ctx.filesDir, `${Date.now()}_${++this.mediaCopySeq}`);
      if (live.videoPath !== '') {
        // 几何与封面都由导出那一步算好（见 util/movingPhotoPick）：静图给显示
        // 宽高，另存的小图给 inputThumbnail。这里只负责搬运。
        items.push({
          path: live.videoPath,
          isVideo: true,
          thumbPath: live.thumbPath,
          thumbWidth: live.thumbWidth,
          thumbHeight: live.thumbHeight,
          width: live.displayWidth,
          height: live.displayHeight
        });
        continue;
      }
      const path: string = this.copyUriToCache(uri);
      if (path === '') {
        skipped++;
        continue;
      }
      items.push({ path, isVideo: isVideoPath(path) });
    }
    return { items, skipped };
  }

  private applyPickedMedia(items: MediaSendItem[], skipped: number): void {
    if (items.length === 0) {
      promptAction.showToast({ message: $r('app.string.cp_media_read_failed'), duration: 1800 });
      return;
    }
    if (skipped > 0) {
      promptAction.showToast({ message: plural('cp_media_skipped', skipped, skipped), duration: 1800 });
    }
    // 不直接发：先攒到输入框上方那一条，等用户配完文字再一起发。
    // 追加而不是替换——用户分几次从不同相册挑图是常见操作。超出九张
    // （Telegram 相册上限）时截断并**明确告知截了几张**，不静默丢弃。
    const dropped: number = this.host.appendPendingMedia(items);
    if (dropped > 0) {
      promptAction.showToast({
        message: str('cp_pending_media_full', PENDING_MEDIA_MAX, dropped),
        duration: 2200
      });
    }
  }

  // --- 定时消息管理 ---

  // Loading and the send-now/delete actions live in ScheduledSheet, which
  // fetches on mount.
  //
  // 死代码：全仓（含 util/attachActions.ets 的 ATTACH_KEYS/ORDER）都没有
  // 'schedule' 这个 key，runAttachAction 分发表里也没有对应分支，此方法当前
  // 不可达。原样带走，不新增调用点。
  private openScheduledSheet(): void {
    this.host.setSheet('scheduled', true);
  }

  private openPollComposer(): void {
    this.host.setSheet('poll', true);
  }

  // 圆形视频走附件菜单而不是麦克风按钮：麦克风已经是"点一下开始录音"的
  // 单击语义，再叠一个长按会和录音的起录竞争，误触率高；附件菜单里它和
  // 照片/文件是同一类"选一种内容发出去"的入口，心智更一致。
  private openVideoNoteRecorder(): void {
    if (this.host.store() === null) {
      return;
    }
    this.host.cancelRecording();
    this.host.stopEditing();
    this.host.setComposerFocused(false);
    this.host.setSheet('videoNote', true);
  }

  private openContactPicker(): void {
    this.host.setSheet('contact', true);
  }

  // 音乐：文件选择器按音频后缀过滤，复制沙箱后按音频消息发送。
  private pickAndSendAudio(): void {
    const docPicker = new picker.DocumentViewPicker(this.host.context());
    const opts = new picker.DocumentSelectOptions();
    opts.maxSelectNumber = 1;
    opts.fileSuffixFilters = ['.mp3', '.m4a', '.flac', '.ogg', '.wav', '.aac'];
    docPicker.select(opts).then((uris: string[]) => {
      if (uris.length === 0) {
        return;
      }
      const dest = this.copyUriToCache(uris[0]);
      if (dest === '') {
        promptAction.showToast({ message: $r('app.string.cp_audio_read_failed'), duration: 2000 });
        return;
      }
      const store = this.host.store();
      if (store !== null) {
        this.host.setAtBottom(true);
        store.sendAudio(dest, this.host.draftText().trim());
        this.host.clearDraft();
      }
    }).catch((e: Object) => {
      logE(`AttachActions.pickAndSendAudio select failed: ${JSON.stringify(e)}`);
    });
  }

  // 位置入口：先问是发静态点还是实时共享。
  private chooseLocationKind(): void {
    this.host.uiContext().getPromptAction().showActionMenu({
      title: $r('app.string.cp_send_location'),
      buttons: [
        { text: $r('app.string.cp_current_location'), color: COLOR_TEXT_PRIMARY as string },
        { text: $r('app.string.cp_live_15m'), color: COLOR_TEXT_PRIMARY as string },
        { text: $r('app.string.cp_live_1h'), color: COLOR_TEXT_PRIMARY as string },
        { text: $r('app.string.cp_live_8h'), color: COLOR_TEXT_PRIMARY as string }
      ]
    }).then((res: promptAction.ActionMenuSuccessResponse): void => {
      const periods: number[] = [0, 15 * 60, 3600, 8 * 3600];
      const period: number = periods[res.index] ?? 0;
      if (period === 0) {
        this.sendCurrentLocation();
      } else {
        this.startLiveLocation(period);
      }
    }).catch((): void => {});
  }

  // 实时位置：发出后按固定间隔用新坐标 editMessageLiveLocation。TDLib 不会
  // 替我们采集位置，更新完全由客户端驱动，所以这里自己维护定时器；页面销毁
  // 或时长到期就停，避免后台一直定位耗电。
  private startLiveLocation(periodSec: number): void {
    withLocationPermission(this.host.context(), (): void => {
      this.currentLocation(10000).then((loc: geoLocationManager.Location): void => {
        const store = this.host.store();
        if (store === null) { return; }
        this.host.setAtBottom(true);
        store.sendLiveLocation(loc.latitude, loc.longitude, periodSec)
          .then((messageId: number): void => {
            if (messageId === 0) {
              promptAction.showToast({ message: $r('app.string.cp_live_location_failed'), duration: 1800 });
              return;
            }
            // 交给独立服务：退出会话、切后台都要继续共享。
            liveLocation.start(this.host.chatId(), messageId, periodSec);
            promptAction.showToast({ message: $r('app.string.cp_live_location_started'), duration: 1600 });
          });
      }).catch((): void => {
        promptAction.showToast({ message: $r('app.string.cp_location_failed'), duration: 2000 });
      });
    });
  }

  private currentLocation(timeoutMs: number): Promise<geoLocationManager.Location> {
    const request: geoLocationManager.SingleLocationRequest = {
      locatingPriority: geoLocationManager.LocatingPriority.PRIORITY_LOCATING_SPEED,
      locatingTimeoutMs: timeoutMs
    };
    return geoLocationManager.getCurrentLocation(request);
  }

  // 位置：申请定位权限 → 取当前坐标 → 发送。无地图选点（Map Kit 需 AGC 凭据）。
  private sendCurrentLocation(): void {
    const context = this.host.context();
    const permissions: Permissions[] =
      ['ohos.permission.APPROXIMATELY_LOCATION', 'ohos.permission.LOCATION'];
    abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context, permissions)
      .then((result): void => {
        const granted: boolean = result.authResults.length > 0 && result.authResults[0] === 0;
        if (!granted) {
          promptAction.showToast({ message: $r('app.string.cp_needs_location'), duration: 1800 });
          return;
        }
        promptAction.showToast({ message: $r('app.string.cp_getting_location'), duration: 1200 });
        const request: geoLocationManager.SingleLocationRequest = {
          locatingPriority: geoLocationManager.LocatingPriority.PRIORITY_LOCATING_SPEED,
          locatingTimeoutMs: 10000
        };
        geoLocationManager.getCurrentLocation(request)
          .then((location: geoLocationManager.Location): void => {
            const store = this.host.store();
            if (store !== null) {
              this.host.setAtBottom(true);
              store.sendLocation(location.latitude, location.longitude);
            }
          })
          .catch((e: BusinessError): void => {
            logE(`AttachActions.sendCurrentLocation failed: ${e.message}`);
            promptAction.showToast({ message: $r('app.string.cp_location_failed'), duration: 2000 });
          });
      })
      .catch((e: BusinessError): void => {
        logE(`AttachActions location permission failed: ${e.message}`);
      });
  }

  // 骰子六选一。原来走 promptAction.showActionMenu，那是系统弹窗，外观完全
  // 由系统定——ActionMenuOptions 里没有模糊或材质字段，套不上玻璃。改成自绘
  // 的 sheet，和翻译面板同一套 blurStyle + systemMaterial。
  // 🎰 老虎机由 DiceBubble 叠 5 层 TGS 渲染。
  //
  // diceSheet @Builder（仍在页面：bindSheet($$) 挂 bottomDock 节点）里
  // ForEach 的 onClick 调用点。
  private showDiceMenu(): void {
    this.host.setDiceSheetOpen(true);
  }

  // 唯一调用点在页面的 diceSheet @Builder（留页面）里 ForEach 的 onClick，
  // 因此这里保持对外可见。
  sendDiceEmoji(emoji: string): void {
    this.host.setDiceSheetOpen(false);
    const store = this.host.store();
    if (store !== null) {
      this.host.setAtBottom(true);
      store.sendDice(emoji);
    }
  }

  // Paperclip: pick a document, copy it into the app sandbox (TDLib can't read
  // picker URIs), then send it as a document message.
  private pickAndSendFile(): void {
    const docPicker = new picker.DocumentViewPicker(this.host.context());
    const opts = new picker.DocumentSelectOptions();
    opts.maxSelectNumber = 1;
    docPicker.select(opts).then((uris: string[]) => {
      if (uris.length === 0) {
        return;
      }
      const dest = this.copyUriToCache(uris[0]);
      if (dest === '') {
        promptAction.showToast({ message: $r('app.string.cp_file_read_failed'), duration: 2000 });
        return;
      }
      const store = this.host.store();
      if (store !== null) {
        this.host.setAtBottom(true);
        store.sendDocument(dest, this.host.draftText().trim());
        this.host.clearDraft();
      }
    }).catch((e: Object) => {
      logE(`AttachActions.pickAndSendFile select failed: ${JSON.stringify(e)}`);
    });
  }

  // 面板只说"点了哪一格"，这里说"那一格做什么"。两边靠 key 对上，
  // AttachActions.test 钉住了不会出现分发表之外的 key。唯一调用点在页面的
  // attachDrawerContent（@LocalBuilder，声明在页面里，但执行是用户点击面板
  // 格子时，不在 build 渲染期间），因此这里保持对外可见。
  runAttachAction(key: string): void {
    this.host.closeAttachPanel();
    if (key === 'media') {
      this.pickMedia();
    } else if (key === 'file') {
      this.pickAndSendFile();
    } else if (key === 'audio') {
      this.pickAndSendAudio();
    } else if (key === 'videoNote') {
      this.openVideoNoteRecorder();
    } else if (key === 'location') {
      this.chooseLocationKind();
    } else if (key === 'contact') {
      this.openContactPicker();
    } else if (key === 'poll') {
      this.openPollComposer();
    } else if (key === 'dice') {
      this.showDiceMenu();
    }
  }

  // ChatPage.aboutToDisappear 调用。原代码对 mediaPickerOpen/mediaCopySeq 在
  // 页面销毁时没有任何清理（逐行核对过 aboutToDisappear 全链路七个子方法，
  // 零命中），两个字段随实例一起被丢弃、不产生可观察副作用。这里保持空实现，
  // 不替原代码编造一份清理逻辑——只是为了和其余控制器统一的 bind/dispose
  // 生命周期形状而提供这个方法。
  dispose(): void {}
}
