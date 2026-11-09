import { describe, expect, it } from '@ohos/hypium';
import { MediaSaveState, MediaSaveStateHost } from '../main/ets/pages/chat/MediaSaveState';
import { cloneMessage, MessageEntry } from '../main/ets/store/MessageEntry';
import { MessageStore } from '../main/ets/store/MessageStore';
import { UserStore } from '../main/ets/store/UserStore';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdBridge, TdObject } from '../main/ets/tdkit/TdTypes';
import { common } from '@kit.AbilityKit';
import { KEY_AUTOSAVE_PRIVATE } from '../main/ets/store/AppSettings';

// 媒体保存/下载簇（B15 从 ChatPage 整体搬出）的第一组断言。写法照抄
// ChatOverlayState.test.ets / AttachActions.test.ets（FakeHost + callOrder
// 合并时间线、真实 TdClient+FakeBridge 的 newWiredStore、文件头先说环境
// 限制）。
//
// 【核心环境限制，读用例前必看——本文件覆盖率被这一条卡得比较死】
//
// saveMediaTo()（私有，被 saveViewerMedia 与 onSnapshot 的"下载完成，落地
// 保存"分支调用）**不管 toFiles 是 true 还是 false**，最终都会摸到一个真实
// 系统选择器/确认弹层：
//   - toFiles=false → util/mediaSaver.ets 的 saveMediaToGallery() →
//     `photoAccessHelper.getPhotoAccessHelper(ctx).showAssetsCreationDialog(...)`
//   - toFiles=true → services/DownloadSaveNotification.ets 的
//     downloadSaveService.saveDownloadedFile()/saveRemoteFile() → 最终经
//     util/mediaSaver.ets 的 saveFileToDownloads/saveFileToLocal →
//     `new picker.DocumentViewPicker(ctx).save(...)`（首次还可能先弹文件夹
//     授权选择器 `picker.DocumentViewPicker(ctx).select(...)`）
// 这两个都是 AttachActions.test.ets 文件头点名的同一类风险："是否会真的
// 拉起一个系统选择器/确认页面，未经验证"——`MediaSaveStateHost` 虽然为
// `context()` 留了缝（可以喂一个空对象），但这两个系统 API 是否会校验
// context 的合法性、进而在拿到非法 context 时同步失败，还是径直弹出一个
// 需要真人交互才能关掉的系统弹层，本地无法验证，风险与 AttachActions 对
// photoAccessHelper/picker 的顾虑完全一致。因此：
//   - saveViewerMedia 四个分支里，只有"本地路径已存在""thumbnail 未取回"两
//     个会调 saveMediaTo 的分支不测（会摸 photoAccessHelper/picker）；
//     "toFiles=true 的两个远程分支"同样会摸 downloadSaveService 内部的
//     picker，也不测；"toFiles=false 的两个远程分支"（还没下载完，先建立
//     等待句柄+发起 TDLib 下载）跟"照片彻底没有可保存内容"分支完全不碰这两
//     个系统 API，可以安全测。
//   - onSnapshot 的"落地保存成功"两个分支（3105/3117 那两条，成功后调
//     saveMediaTo）不测；"下载失败"两个分支虽然不碰 saveMediaTo，但
//     pendingGallerySaveId/pendingGallerySaveProgress 是没有读口子的私有
//     字段，唯一能验证"确实清空了"的手段是让下一次 onSnapshot 走到本该被
//     跳过的成功分支——而"确实清空"的反面（回归重现）恰恰就是没跳过、
//     真的摸到了 saveMediaTo，等于用一个本该避免触发的调用去证明另一个
//     调用没被触发，不安全，见 skippedAreas。
//   - onFileSave 的三个非 guard 分支全部经 downloadSaveService（同上，
//     picker 风险），只测三条 guard。
//   - onFileTap 不受这条限制：它的"已下载→打开"分支走 util/openLocalFile.ets
//     的 `context.startAbility(want)`——这是**方法调用在我们自己喂的 host
//     .context() 返回值上**，喂一个 `{}` 空对象，`({}).startAbility` 连方法
//     都不存在，JS 语义上必然同步抛出 TypeError，被 openLocalFile 自己的
//     try/catch 吞掉、resolve(false)——不是"未经验证"，是必然的、可推导的
//     行为，因此这条分支可以安全测（这一点是 onFileTap 与 saveMediaTo 的
//     关键区别：前者的风险 API 是我们自己可控 context 上的方法，后者是
//     独立的系统模块函数，不会因为参数不合法就必然同步失败）。
//
// 【关于 DownloadSaveNotification 摸到的 notificationManager——判断依据，非
// 已验证的先例】saveViewerMedia 的两条"toFiles=false 远程待下载"分支会
// `new DownloadSaveNotification(...)`，其构造函数内部异步调用
// `notificationManager.isSupportTemplate/.publish`（services/
// DownloadSaveNotification.ets）。全仓 `entry/src/test/` 目前没有任何一个
// 文件碰过 notificationManager，这条判断不像 promptAction.showToast 那样
// 有直接先例可循。之所以仍然纳入测试而不是归进 skippedAreas 的 Category A
// （photoAccessHelper/picker）：这是一枚"发通知"的 fire-and-forget 异步
// 系统服务调用，不弹出需要真人交互才能关闭的界面——不同于选择器/确认
// 对话框，通知一发出 Promise 就落地，不会挂起等谁去点它；且调用方自己
// 的 `.catch((e) => logE(...))` 已经包住了失败路径。判断依据仅此而已，
// 如果这条判断有误，请把对应用例移进 skippedAreas 并说明原因。
//
// 另外，requestVideoDownload/requestFullPhoto/pauseFileDownload 内部都先
// `this.indexOf(messageId)` 在 MessageStore **自己的** messages 数组里查，
// 查不到就静默 return、不发任何 TDLib 请求——所以喂给 host.findMsg/
// host.viewerEntry 的 MessageEntry 必须真的是同一个 store 通过
// updateNewMessage 收下的那一条（用 wired.store.getMessages() 取回，不能
// 另外拼一个"看起来一样"的对象），否则测试会静默地什么都测不到。

class FakeHost implements MediaSaveStateHost {
  callOrder: string[] = [];
  contextValue: common.UIAbilityContext = {} as common.UIAbilityContext;
  storeValue: MessageStore | null = null;
  chatIdValue: number = 0;
  findMsgResult: MessageEntry | undefined = undefined;
  latestMessagesValue: MessageEntry[] = [];

  context: () => common.UIAbilityContext = (): common.UIAbilityContext => {
    this.callOrder.push('context');
    return this.contextValue;
  };
  store: () => MessageStore | null = (): MessageStore | null => {
    this.callOrder.push('store');
    return this.storeValue;
  };
  chatId: () => number = (): number => {
    this.callOrder.push('chatId');
    return this.chatIdValue;
  };
  findMsg: (messageId: number) => MessageEntry | undefined = (messageId: number): MessageEntry | undefined => {
    this.callOrder.push(`findMsg:${messageId}`);
    return this.findMsgResult;
  };
  latestMessages: () => MessageEntry[] = (): MessageEntry[] => {
    this.callOrder.push('latestMessages');
    return this.latestMessagesValue;
  };
}

function controllerOn(host: FakeHost): MediaSaveState {
  const controller: MediaSaveState = new MediaSaveState();
  controller.bind(host);
  return controller;
}

// 形状照抄 ChatOverlayState.test.ets / AttachActions.test.ets 的
// newWiredStore：一套真的能收发的 TdClient，不经过 tdkit/Globals 的模块级
// 单例（本地是坏的），自己的 FakeBridge 自己接收、自己回。
class FakeBridge implements TdBridge {
  onReceive: (json: string) => void = (): void => {};
  sent: string[] = [];
  init(cb: (json: string) => void): void { this.onReceive = cb; }
  send(json: string): void { this.sent.push(json); }
}

interface WiredStore {
  store: MessageStore;
  bridge: FakeBridge;
}

function newWiredStore(chatId: number): WiredStore {
  const bridge: FakeBridge = new FakeBridge();
  const client: TdClient = new TdClient(bridge);
  client.start();
  const users: UserStore = new UserStore(client);
  const store: MessageStore = new MessageStore(client, users, chatId);
  // passive=true：只订阅 updateNewMessage 等更新（本文件靠它把测试消息喂进
  // store 自己的 messages 数组），不发 openChat/getChatHistory——保持
  // bridge.sent 只装我们自己这条用例关心的请求，不用去过滤打开会话的噪音。
  store.open(undefined, true);
  return { store, bridge };
}

// 把一条 updateNewMessage 喂给已经 open() 过的 store——照抄
// MessageStore.test.ets 的 pushNewMessage，完全同步生效，不需要 await。
function pushNewMessage(bridge: FakeBridge, message: TdObject): void {
  const u: TdObject = { '@type': 'updateNewMessage' };
  u['message'] = message;
  bridge.onReceive(JSON.stringify(u));
}

// 文档（file）消息构造器——形状照抄 MessageStore.test.ets 的 documentMessage，
// 额外加一个 active 参数覆盖"下载中"状态（本文件的 mediaDownloadActive 分支
// 要用）。
function documentMessage(
  id: number, chatId: number, fileId: number,
  localPath: string = '', active: boolean = false, isOutgoing: boolean = false
): TdObject {
  const source: TdObject = { '@type': 'file' };
  source['id'] = fileId;
  source['size'] = 1000;
  const local: TdObject = { '@type': 'localFile' };
  local['is_downloading_completed'] = localPath !== '';
  local['is_downloading_active'] = active;
  local['path'] = localPath;
  local['downloaded_size'] = localPath !== '' ? 1000 : 0;
  source['local'] = local;
  const document: TdObject = { '@type': 'document' };
  document['document'] = source;
  document['file_name'] = 'guide.pdf';
  document['mime_type'] = 'application/pdf';
  const content: TdObject = { '@type': 'messageDocument' };
  content['document'] = document;
  const message: TdObject = { '@type': 'message' };
  message['id'] = id;
  message['chat_id'] = chatId;
  message['is_outgoing'] = isOutgoing;
  message['date'] = 100;
  message['content'] = content;
  return message;
}

// 视频消息构造器（远程未下载）——照抄 MessageStore.test.ets 的 videoMessage。
function videoMessage(id: number, chatId: number, fileId: number, thumbId: number): TdObject {
  const source: TdObject = { '@type': 'file' };
  source['id'] = fileId;
  source['size'] = 1000;
  const thumbFile: TdObject = { '@type': 'file' };
  thumbFile['id'] = thumbId;
  const thumb: TdObject = { '@type': 'thumbnail' };
  thumb['file'] = thumbFile;
  thumb['width'] = 320;
  thumb['height'] = 180;
  const video: TdObject = { '@type': 'video' };
  video['video'] = source;
  video['thumbnail'] = thumb;
  video['width'] = 320;
  video['height'] = 180;
  const content: TdObject = { '@type': 'messageVideo' };
  content['video'] = video;
  const m: TdObject = { '@type': 'message' };
  m['id'] = id;
  m['chat_id'] = chatId;
  m['is_outgoing'] = false;
  m['date'] = 100;
  m['content'] = content;
  return m;
}

// 三档尺寸的图片消息构造器（远程未下载、full 尺寸未取回）——照抄
// MessageStore.test.ets 的 photoMessage。
function photoMessage(id: number, chatId: number, thumbId: number, fullId: number): TdObject {
  const smallFile: TdObject = { '@type': 'file' };
  smallFile['id'] = thumbId - 1;
  smallFile['size'] = 5000;
  const smallSize: TdObject = { '@type': 'photoSize' };
  smallSize['type'] = 's';
  smallSize['photo'] = smallFile;
  smallSize['width'] = 200;
  smallSize['height'] = 200;
  const midFile: TdObject = { '@type': 'file' };
  midFile['id'] = thumbId;
  midFile['size'] = 30000;
  const midSize: TdObject = { '@type': 'photoSize' };
  midSize['type'] = 'm';
  midSize['photo'] = midFile;
  midSize['width'] = 900;
  midSize['height'] = 900;
  const fullFile: TdObject = { '@type': 'file' };
  fullFile['id'] = fullId;
  fullFile['size'] = 200000;
  const fullSize: TdObject = { '@type': 'photoSize' };
  fullSize['type'] = 'x';
  fullSize['photo'] = fullFile;
  fullSize['width'] = 1600;
  fullSize['height'] = 1600;
  const photo: TdObject = { '@type': 'photo' };
  photo['sizes'] = [smallSize, midSize, fullSize];
  const content: TdObject = { '@type': 'messagePhoto' };
  content['photo'] = photo;
  const m: TdObject = { '@type': 'message' };
  m['id'] = id;
  m['chat_id'] = chatId;
  m['is_outgoing'] = false;
  m['date'] = 100;
  m['content'] = content;
  return m;
}

// 单尺寸图片消息——full 尺寸与 inline 尺寸是同一张，photoFullFileId 因此是
// 0（"没有可升级的高清版"）。saveViewerMedia 的"照片彻底没有可保存内容"
// 分支要用这个。
function singleSizePhotoMessage(id: number, chatId: number, fileId: number): TdObject {
  const file: TdObject = { '@type': 'file' };
  file['id'] = fileId;
  file['size'] = 5000;
  const size: TdObject = { '@type': 'photoSize' };
  size['type'] = 'm';
  size['photo'] = file;
  size['width'] = 200;
  size['height'] = 200;
  const photo: TdObject = { '@type': 'photo' };
  photo['sizes'] = [size];
  const content: TdObject = { '@type': 'messagePhoto' };
  content['photo'] = photo;
  const m: TdObject = { '@type': 'message' };
  m['id'] = id;
  m['chat_id'] = chatId;
  m['is_outgoing'] = false;
  m['date'] = 100;
  m['content'] = content;
  return m;
}

export default function mediaSaveStateTest() {
  describe('MediaSaveState', () => {

    // ================= saveMediaEntry =================

    // 【S2 删掉了一条用例，这里记下为什么】
    // 原有 'host.viewerEntry() 为 null 时直接返回' 那条，防的是控制器里的
    // null 早退判据被删。S2 之后 saveMediaEntry(e, toFiles) 的 e 是非空入参，
    // 控制器里**不再有这个分支**——判据搬到了 ChatPage.saveCurrentViewerMedia()，
    // 由它取 entryById(viewerMsgId)、为 null 就不调。
    // 在这里保留一条测不到东西的用例比删掉更坏（会让人以为还有防线）。

    // 防的回归：四条 if 都判空之后那个 else 分支（"没有任何可保存内容"）被
    // 漏掉或误触发别的分支。这条完全不碰 saveMediaTo/downloadSaveService，
    // 见文件头，可以安全测。
    it('saveMediaEntry: 照片四条分支全部落空时，只经 host.context()，弹"不可用"提示，不碰 store', 0, (): void => {
      const wired: WiredStore = newWiredStore(1);
      pushNewMessage(wired.bridge, singleSizePhotoMessage(10, 1, 500));
      const entry: MessageEntry = wired.store.getMessages()[0];
      expect(entry.contentType).assertEqual('photo');
      expect(entry.photoFullFileId).assertEqual(0); // 前置条件：确实没有可升级的高清版
      expect(entry.photoPath).assertEqual(''); // 前置条件：缩略图也还没下载下来

      const host: FakeHost = new FakeHost();
      const controller: MediaSaveState = controllerOn(host);

      controller.saveMediaEntry(entry, false);

      expect(host.callOrder).assertDeepEquals(['context']);
    });

    // 防的回归：视频"还没下载完，toFiles=false"这条分支漏调
    // store.requestVideoDownload，或者把 register 参数写死成 false（该分支
    // 原文固定传 true——用户点了保存，理应进 TDLib 下载管理器，跨页面持续）。
    it('saveMediaEntry: 视频远程待下载（toFiles=false）经 host.store() 调 requestVideoDownload(register=true)', 0, (): void => {
      const wired: WiredStore = newWiredStore(9);
      pushNewMessage(wired.bridge, videoMessage(5, 9, 777, 778));
      const entry: MessageEntry = wired.store.getMessages()[0];
      expect(entry.videoPath).assertEqual(''); // 前置条件：确实还没下载完

      const host: FakeHost = new FakeHost();
      host.storeValue = wired.store;
      const controller: MediaSaveState = controllerOn(host);

      controller.saveMediaEntry(entry, false);

      expect(host.callOrder).assertDeepEquals(['context', 'store']);
      const sent: TdObject[] = wired.bridge.sent.map((json: string): TdObject => JSON.parse(json) as TdObject);
      const req: TdObject | undefined =
        sent.find((o: TdObject): boolean => o['@type'] === 'addFileToDownloads');
      expect(req !== undefined).assertTrue();
      expect(req !== undefined ? req['file_id'] : 0).assertEqual(777);
    });

    // 同上，图片远程待下载分支，经 requestFullPhoto 发 downloadFile（不进
    // 下载管理器——这条原文没传 register，是普通的按需高清下载）。
    it('saveMediaEntry: 图片远程待下载（toFiles=false）经 host.store() 调 requestFullPhoto', 0, (): void => {
      const wired: WiredStore = newWiredStore(9);
      pushNewMessage(wired.bridge, photoMessage(6, 9, 900, 901));
      const entry: MessageEntry = wired.store.getMessages()[0];
      expect(entry.photoFullFileId).assertEqual(901);
      expect(entry.photoFullPath).assertEqual(''); // 前置条件：高清版确实还没取回

      const host: FakeHost = new FakeHost();
      host.storeValue = wired.store;
      const controller: MediaSaveState = controllerOn(host);

      controller.saveMediaEntry(entry, false);

      expect(host.callOrder).assertDeepEquals(['context', 'store']);
      const sent: TdObject[] = wired.bridge.sent.map((json: string): TdObject => JSON.parse(json) as TdObject);
      const req: TdObject | undefined =
        sent.find((o: TdObject): boolean => o['@type'] === 'downloadFile' && o['file_id'] === 901);
      expect(req !== undefined).assertTrue();
    });

    // ================= onFileTap =================

    it('onFileTap: findMsg 未命中时直接返回，不继续碰 store 之外的任何东西', 0, (): void => {
      const wired: WiredStore = newWiredStore(1);
      const host: FakeHost = new FakeHost();
      host.findMsgResult = undefined;
      host.storeValue = wired.store;
      const controller: MediaSaveState = controllerOn(host);

      // newWiredStore 建 MessageStore 时自己就会发几条请求（拉历史等），
      // 所以断言的是“没有发出新请求”，不是“一条都没发过”。
      const sentBefore: number = wired.bridge.sent.length;
      controller.onFileTap(1);

      expect(host.callOrder).assertDeepEquals(['findMsg:1', 'store']);
      expect(wired.bridge.sent.length).assertEqual(sentBefore);
    });

    it('onFileTap: contentType 不是 file 时直接返回', 0, (): void => {
      const wired: WiredStore = newWiredStore(1);
      pushNewMessage(wired.bridge, videoMessage(1, 1, 5, 6)); // contentType='video'
      const host: FakeHost = new FakeHost();
      host.findMsgResult = wired.store.getMessages()[0];
      host.storeValue = wired.store;
      const controller: MediaSaveState = controllerOn(host);

      // newWiredStore 建 MessageStore 时自己就会发几条请求（拉历史等），
      // 所以断言的是“没有发出新请求”，不是“一条都没发过”。
      const sentBefore: number = wired.bridge.sent.length;
      controller.onFileTap(1);

      expect(host.callOrder).assertDeepEquals(['findMsg:1', 'store']);
      expect(wired.bridge.sent.length).assertEqual(sentBefore);
    });

    it('onFileTap: store 为 null 时直接返回', 0, (): void => {
      const wired: WiredStore = newWiredStore(1);
      pushNewMessage(wired.bridge, documentMessage(1, 1, 5));
      const host: FakeHost = new FakeHost();
      host.findMsgResult = wired.store.getMessages()[0];
      host.storeValue = null;
      const controller: MediaSaveState = controllerOn(host);

      controller.onFileTap(1);

      expect(host.callOrder).assertDeepEquals(['findMsg:1', 'store']);
    });

    // 防的回归：videoFileId===0（文件不可用）分支被漏掉，掉进默认分支去发
    // 一个 file_id=0 的下载请求。
    it('onFileTap: videoFileId===0 时只弹提示，不发任何 TDLib 请求', 0, (): void => {
      const wired: WiredStore = newWiredStore(1);
      pushNewMessage(wired.bridge, documentMessage(9, 1, 0)); // fileId=0
      const host: FakeHost = new FakeHost();
      host.findMsgResult = wired.store.getMessages()[0];
      host.storeValue = wired.store;
      const controller: MediaSaveState = controllerOn(host);

      // newWiredStore 建 MessageStore 时自己就会发几条请求（拉历史等），
      // 所以断言的是“没有发出新请求”，不是“一条都没发过”。
      const sentBefore: number = wired.bridge.sent.length;
      controller.onFileTap(9);

      expect(host.callOrder).assertDeepEquals(['findMsg:9', 'store']);
      expect(wired.bridge.sent.length).assertEqual(sentBefore);

      // 【验收时补的这一段——上面两条断言其实钉不住这个分支】
      // 把 videoFileId===0 那个分支整段删掉，执行会掉进默认分支去调
      // `store.requestVideoDownload(9, true, ...)`；但 MessageStore 对
      // file_id=0 自己也会早退、不发请求，于是 sent.length 照样不变、
      // callOrder 也照样是那两项——上面两条恒绿（验收时真破验证过）。
      //
      // 真正有区别的是**默认分支会把 pendingFileOpenId 设成 9**（"下完了就
      // 自动打开"的意图），而这个分支不该设。用本文件通行的那一手把它逼出来：
      // 再喂一张这条消息"已下载"的快照，看会不会去拉起打开流程。
      host.callOrder = [];
      const doneEntry: MessageEntry = cloneMessage(wired.store.getMessages()[0]);
      doneEntry.videoPath = '/local/should-not-open.pdf';
      controller.onSnapshot([doneEntry], wired.store, 'private');

      // 分支在：意图从没被建立，这张快照什么都不触发。
      // 分支没了：pendingFileOpenId 是 9，这里会经 host.context() 拉起打开。
      expect(host.callOrder.includes('context')).assertFalse();
    });

    // 已下载（videoPath 非空）→ openDownloadedFile → openLocalFile(host.context(), ...)。
    // 假 context 缺 startAbility，JS 语义上必然同步抛错、被 openLocalFile 自
    // 己的 try/catch 吞掉（见文件头），不摸真实系统能力，可以安全测。
    it('onFileTap: 已下载时走 openDownloadedFile，经 host.context()，不发任何 TDLib 请求', 0, (): void => {
      const wired: WiredStore = newWiredStore(1);
      pushNewMessage(wired.bridge, documentMessage(10, 1, 5, '/local/report.pdf'));
      const host: FakeHost = new FakeHost();
      host.findMsgResult = wired.store.getMessages()[0];
      host.storeValue = wired.store;
      const controller: MediaSaveState = controllerOn(host);

      // newWiredStore 建 MessageStore 时自己就会发几条请求（拉历史等），
      // 所以断言的是“没有发出新请求”，不是“一条都没发过”。
      const sentBefore: number = wired.bridge.sent.length;
      controller.onFileTap(10);

      expect(host.callOrder).assertDeepEquals(['findMsg:10', 'store', 'context']);
      expect(wired.bridge.sent.length).assertEqual(sentBefore);
    });

    // 防的回归：openDownloadedFile 内部"同一个文件还没打开完就再点一次"的
    // 并发闸门（fileOpenInFlightId !== 0）被删掉或被削弱。fileOpenInFlightId
    // 在第一次调用里是**同步**赋值的（早于 openLocalFile 内部的 await），
    // 所以紧接着同步再点一次，第二次应该在闸门那一步就被挡住，根本不会
    // 再调 host.context()。
    it('onFileTap: openDownloadedFile 的并发闸门——同一条文件还没打开完时，第二次调用不重复 host.context()', 0, (): void => {
      const wired: WiredStore = newWiredStore(1);
      pushNewMessage(wired.bridge, documentMessage(11, 1, 6, '/local/a.pdf'));
      const host: FakeHost = new FakeHost();
      host.findMsgResult = wired.store.getMessages()[0];
      host.storeValue = wired.store;
      const controller: MediaSaveState = controllerOn(host);

      controller.onFileTap(11);
      expect(host.callOrder).assertDeepEquals(['findMsg:11', 'store', 'context']);

      controller.onFileTap(11); // 立即再点一次：fileOpenInFlightId 还没被异步回调复位
      expect(host.callOrder).assertDeepEquals(
        ['findMsg:11', 'store', 'context', 'findMsg:11', 'store']);
    });

    // 防的回归：下载中再点一次应该是"暂停"（store.pauseFileDownload），如果
    // mediaDownloadActive 判据被删掉，会误落到默认分支重新发起下载。
    it('onFileTap: 下载中再点一次 = 暂停，经 store.pauseFileDownload 发 cancelDownloadFile', 0, (): void => {
      const wired: WiredStore = newWiredStore(2);
      pushNewMessage(wired.bridge, documentMessage(20, 2, 100, '', true)); // active=true
      const entry: MessageEntry = wired.store.getMessages()[0];
      expect(entry.mediaDownloadActive).assertTrue(); // 前置条件
      expect(entry.videoPath).assertEqual('');
      const host: FakeHost = new FakeHost();
      host.findMsgResult = entry;
      host.storeValue = wired.store;
      const controller: MediaSaveState = controllerOn(host);

      controller.onFileTap(20);

      expect(host.callOrder).assertDeepEquals(['findMsg:20', 'store']);
      const sent: TdObject[] = wired.bridge.sent.map((json: string): TdObject => JSON.parse(json) as TdObject);
      const req: TdObject | undefined =
        sent.find((o: TdObject): boolean => o['@type'] === 'cancelDownloadFile');
      expect(req !== undefined).assertTrue();
      expect(req !== undefined ? req['file_id'] : 0).assertEqual(100);
    });

    // 默认分支：发起下载，register=true 进 TDLib 下载管理器（addFileToDownloads
    // 带 chat_id/message_id，与"暂停再点一次能在搜索页下载 tab 看见"这条产品
    // 语义绑定，原文固定传 true）。
    it('onFileTap: 默认分支——发起下载，经 store.requestVideoDownload(register=true) 发 addFileToDownloads', 0, (): void => {
      const wired: WiredStore = newWiredStore(3);
      pushNewMessage(wired.bridge, documentMessage(30, 3, 200));
      const host: FakeHost = new FakeHost();
      host.findMsgResult = wired.store.getMessages()[0];
      host.storeValue = wired.store;
      const controller: MediaSaveState = controllerOn(host);

      controller.onFileTap(30);

      expect(host.callOrder).assertDeepEquals(['findMsg:30', 'store']);
      const sent: TdObject[] = wired.bridge.sent.map((json: string): TdObject => JSON.parse(json) as TdObject);
      const req: TdObject | undefined =
        sent.find((o: TdObject): boolean => o['@type'] === 'addFileToDownloads');
      expect(req !== undefined).assertTrue();
      expect(req !== undefined ? req['file_id'] : 0).assertEqual(200);
      expect(req !== undefined ? req['chat_id'] : 0).assertEqual(3);
      expect(req !== undefined ? req['message_id'] : 0).assertEqual(30);
    });

    // ================= onFileSave（只测三条 guard，见文件头） =================

    it('onFileSave: findMsg 未命中时直接返回', 0, (): void => {
      const wired: WiredStore = newWiredStore(1);
      const host: FakeHost = new FakeHost();
      host.findMsgResult = undefined;
      host.storeValue = wired.store;
      const controller: MediaSaveState = controllerOn(host);

      // newWiredStore 建 MessageStore 时自己就会发几条请求（拉历史等），
      // 所以断言的是“没有发出新请求”，不是“一条都没发过”。
      const sentBefore: number = wired.bridge.sent.length;
      controller.onFileSave(1);

      expect(host.callOrder).assertDeepEquals(['findMsg:1', 'store']);
      expect(wired.bridge.sent.length).assertEqual(sentBefore);
    });

    it('onFileSave: contentType 不是 file 时直接返回', 0, (): void => {
      const wired: WiredStore = newWiredStore(1);
      pushNewMessage(wired.bridge, videoMessage(1, 1, 5, 6));
      const host: FakeHost = new FakeHost();
      host.findMsgResult = wired.store.getMessages()[0];
      host.storeValue = wired.store;
      const controller: MediaSaveState = controllerOn(host);

      controller.onFileSave(1);

      expect(host.callOrder).assertDeepEquals(['findMsg:1', 'store']);
    });

    it('onFileSave: store 为 null 时直接返回', 0, (): void => {
      const wired: WiredStore = newWiredStore(1);
      pushNewMessage(wired.bridge, documentMessage(1, 1, 5));
      const host: FakeHost = new FakeHost();
      host.findMsgResult = wired.store.getMessages()[0];
      host.storeValue = null;
      const controller: MediaSaveState = controllerOn(host);

      controller.onFileSave(1);

      expect(host.callOrder).assertDeepEquals(['findMsg:1', 'store']);
    });

    // ================= onSnapshot：文件打开落地（landPendingFileOpen） =================
    // 这一段完全不摸 saveMediaTo/downloadSaveService（见文件头），可以安全
    // 覆盖全部三个分支。pendingFileOpenId 是私有字段读不到，靠"下一次
    // onSnapshot 是否重新触发 host.context()"这个外部可观察效果侧面验证
    // 复位是否生效——这个验证手段本身是安全的：无论复位对不对，第二次
    // onSnapshot 走到的都只是 openDownloadedFile（经我们自己喂的假
    // context 安全失败），不会意外摸到 saveMediaTo。

    it('onSnapshot: 待打开的文档下载完成——触发 openDownloadedFile（经 host.context()）', 0, (): void => {
      const wired: WiredStore = newWiredStore(4);
      pushNewMessage(wired.bridge, documentMessage(40, 4, 300)); // 还没下载完
      const host: FakeHost = new FakeHost();
      host.findMsgResult = wired.store.getMessages()[0];
      host.storeValue = wired.store;
      const controller: MediaSaveState = controllerOn(host);
      controller.onFileTap(40); // 建立 pendingFileOpenId=40（私有，见上方说明）
      host.callOrder = []; // 只看 onSnapshot 这一步触发的部分

      const doneEntry: MessageEntry = cloneMessage(wired.store.getMessages()[0]);
      doneEntry.videoPath = '/local/done.pdf';
      controller.onSnapshot([doneEntry], wired.store, 'private');

      expect(host.callOrder.includes('context')).assertTrue();
    });

    // 【验收时降级了这条用例的声称范围——它钉不住自己说的那件事】
    // 原意是防 landPendingFileOpen 成功分支忘了把 pendingFileOpenId 复位为 0。
    // 但把那一行 `this.pendingFileOpenId = 0;` 删掉，这条用例照样全绿（验收时
    // 真破验证过）：openDownloadedFile 自己还有一道在途闸门
    // （`fileOpenInFlightId !== 0` 就直接 return），第二次调用被它挡下了，
    // host.context() 因此不会被调第二次——也就是说这条断言实际观测到的是
    // **在途闸门**，不是 pendingFileOpenId 的复位。
    //
    // 两道守卫在这条路径上是重叠的，删掉任意一道，外部行为都不变；要单独钉住
    // 复位那一道，得能观察到 pendingFileOpenId 本身（它是私有的，没有取值器）
    // 或者让在途闸门先自行放开（需要能兑现 openLocalFile 的 Promise，而它不经
    // 宿主注入）。补哪个缝能测：给 MediaSaveStateHost 加一个 openLocalFile 取值器
    // （同 B14 给四个建议控制器加 client、B15 给录音控制器加 newRecorder 的做法），
    // 之后就能让第一次打开先落地、闸门放开，再验第二次会不会重复触发。
    // 本批不动生产代码来做这件事，如实记在这里，并把用例名改成它真正验证得了的
    // 那一半：同一张快照喂两次，不会重复拉起打开流程（不论是哪道守卫拦下的）。
    it('onSnapshot: 同一张已下载快照喂两次，不会重复拉起打开流程', 0, (): void => {
      const wired: WiredStore = newWiredStore(5);
      pushNewMessage(wired.bridge, documentMessage(50, 5, 400));
      const host: FakeHost = new FakeHost();
      host.findMsgResult = wired.store.getMessages()[0];
      host.storeValue = wired.store;
      const controller: MediaSaveState = controllerOn(host);
      controller.onFileTap(50);

      const doneEntry: MessageEntry = cloneMessage(wired.store.getMessages()[0]);
      doneEntry.videoPath = '/local/done.pdf';
      controller.onSnapshot([doneEntry], wired.store, 'private');
      host.callOrder = [];

      controller.onSnapshot([doneEntry], wired.store, 'private'); // 第二次：应该已经是空转
      expect(host.callOrder.includes('context')).assertFalse();
    });

    // 防的回归：快照里彻底找不到那条待打开的消息时，忘了把 pendingFileOpenId
    // 复位——下次这条消息终于出现在快照里（哪怕已经下载完），也不该触发。
    it('onSnapshot: 快照里找不到待打开的消息——pendingFileOpenId 被清空，之后即便消息带着已下载状态出现也不再触发', 0, (): void => {
      const wired: WiredStore = newWiredStore(6);
      pushNewMessage(wired.bridge, documentMessage(60, 6, 500));
      const host: FakeHost = new FakeHost();
      host.findMsgResult = wired.store.getMessages()[0];
      host.storeValue = wired.store;
      const controller: MediaSaveState = controllerOn(host);
      controller.onFileTap(60);
      host.callOrder = [];

      controller.onSnapshot([], wired.store, 'private'); // 快照里没有这条消息
      expect(host.callOrder.includes('context')).assertFalse();

      const doneEntry: MessageEntry = cloneMessage(wired.store.getMessages()[0]);
      doneEntry.videoPath = '/x.pdf';
      controller.onSnapshot([doneEntry], wired.store, 'private');
      expect(host.callOrder.includes('context')).assertFalse(); // 复位确实生效
    });

    // 防的回归：待打开的文档这次下载失败（videoFailed）时忘了把
    // pendingFileOpenId 复位——下次它真的下载完了也不会再触发。
    it('onSnapshot: 待打开的文档下载失败——弹提示，pendingFileOpenId 被清空，不触发 openDownloadedFile', 0, (): void => {
      const wired: WiredStore = newWiredStore(7);
      pushNewMessage(wired.bridge, documentMessage(70, 7, 600));
      const host: FakeHost = new FakeHost();
      host.findMsgResult = wired.store.getMessages()[0];
      host.storeValue = wired.store;
      const controller: MediaSaveState = controllerOn(host);
      controller.onFileTap(70);
      host.callOrder = [];

      const failedEntry: MessageEntry = cloneMessage(wired.store.getMessages()[0]);
      failedEntry.videoFailed = true;
      controller.onSnapshot([failedEntry], wired.store, 'private');
      expect(host.callOrder.includes('context')).assertFalse();

      const doneEntry: MessageEntry = cloneMessage(wired.store.getMessages()[0]);
      doneEntry.videoPath = '/y.pdf';
      controller.onSnapshot([doneEntry], wired.store, 'private'); // 复位验证：不再触发
      expect(host.callOrder.includes('context')).assertFalse();
    });

    // ================= 实例独立性 =================

    it('两个实例互不影响（防的回归：host 字段被误改成模块级共享）', 0, (): void => {
      // S2 后 saveMediaEntry 的第一次跨界调用是 host.context()，用它当探针。
      // entry 用"四条分支全部落空"的那一种：只会走到 context() + 弹提示，
      // 不碰 store、不碰 saveMediaTo/downloadSaveService（见文件头的环境限制）。
      const wired: WiredStore = newWiredStore(1);
      pushNewMessage(wired.bridge, singleSizePhotoMessage(10, 1, 500));
      const entry: MessageEntry = wired.store.getMessages()[0];

      const hostA: FakeHost = new FakeHost();
      const a: MediaSaveState = controllerOn(hostA);
      a.saveMediaEntry(entry, false);
      expect(hostA.callOrder).assertDeepEquals(['context']);

      const hostB: FakeHost = new FakeHost();
      const b: MediaSaveState = controllerOn(hostB);
      b.saveMediaEntry(entry, false);
      expect(hostB.callOrder).assertDeepEquals(['context']);
      expect(hostA.callOrder).assertDeepEquals(['context']); // a 没被 b 的绑定波及
    });

    // ================= 验收时补的：dispose() 与自动保存整簇 =================
    // 这两块原本零覆盖，且都没有出现在文件头的环境限制说明里——等于用沉默
    // 代替了理由（B13 栽过同一个坑）。两块其实都完全可测：
    //  - dispose()：用本文件已经在反复使用的那一手（建立 pendingFileOpenId →
    //    再喂 onSnapshot → 看 host.context() 有没有被调）就能验复位；
    //  - 自动保存：autosaveEnabled 只是读 AppStorage（仓库里 ChatEffects.test.ets
    //    早有直接写 AppStorage 的先例），而所有"跳过/出队"分支根本走不到
    //    saveMediaToGallery，压根不摸 photoAccessHelper。

    // 防的回归：dispose() 被改成空函数体，或漏清 pendingFileOpenId。
    it('dispose(): 清掉待打开的文档意图，之后同一条已下载消息不再触发打开', 0, (): void => {
      const wired: WiredStore = newWiredStore(7);
      pushNewMessage(wired.bridge, documentMessage(70, 7, 700));
      const host: FakeHost = new FakeHost();
      host.findMsgResult = wired.store.getMessages()[0];
      host.storeValue = wired.store;
      const controller: MediaSaveState = controllerOn(host);
      controller.onFileTap(70); // 建立 pendingFileOpenId=70

      controller.dispose();
      host.callOrder = [];

      const doneEntry: MessageEntry = cloneMessage(wired.store.getMessages()[0]);
      doneEntry.videoPath = '/local/done.pdf';
      controller.onSnapshot([doneEntry], wired.store, 'private');

      // dispose() 清了意图：这一张"已下载"快照不该再拉起打开流程。
      expect(host.callOrder.includes('context')).assertFalse();
    });

    // 防的回归：processAutomaticGallerySave 里"这条不该自动保存就出队"的那几条
    // filter 分支被删——消息永远留在队列里，每张新快照都被重扫一遍，而且一旦
    // 它后来带上本地路径，就会被存进相册（用户明明发的是自己的图/或者它压根
    // 不是图片）。这里走的是 isOutgoing 那条分支。
    //
    // 【说明：入队去重（indexOf < 0）那道守卫，本用例**钉不住**，也没有别的
    // 用例钉得住——它对外不可观察】验收时真去删过那道守卫，全绿。原因是出队用的
    // 是 `filter(id => id !== messageId)`，会把重复项**一次全部**移除；而扫描
    // 循环命中第一条可保存项就 break，重复项也只会被处理一次。也就是说队列里
    // 是 [80] 还是 [80, 80]，经由本类的公开面看不出任何差别。如实记在这里，
    // 不给这条用例安一个它担不起的名字。
    it('onSnapshot: 入队后消息变成 isOutgoing 会被出队，之后带着本地路径回来也不保存', 0, (): void => {
      AppStorage.setOrCreate(KEY_AUTOSAVE_PRIVATE, true);
      try {
        const wired: WiredStore = newWiredStore(8);
        pushNewMessage(wired.bridge, photoMessage(80, 8, 800, 801));
        const host: FakeHost = new FakeHost();
        host.storeValue = wired.store;
        const controller: MediaSaveState = controllerOn(host);

        // 第一张快照：消息进 liveIncomingMediaIds、入队；但它还没有本地路径，
        // 所以扫一圈之后 target 仍为 undefined，不会去调 saveMediaToGallery。
        const pending: MessageEntry = cloneMessage(wired.store.getMessages()[0]);
        controller.onSnapshot([pending], wired.store, 'private');
        expect(host.callOrder.includes('context')).assertFalse();

        // 第二张快照：这条消息变成 isOutgoing（走"跳过并出队"那条分支），
        // 队列里那一份被 filter 掉。如果第一步入了两份，这里只出队一份。
        const outgoing: MessageEntry = cloneMessage(wired.store.getMessages()[0]);
        outgoing.isOutgoing = true;
        controller.onSnapshot([outgoing], wired.store, 'private');

        // 第三张快照：同一条消息带着本地路径回来了。队列已空 ⟹ 不该保存。
        // 若第一步入了两份、第二步只出了一份，这里残留的那一份会命中，
        // 从而调到 host.context()——断言随之翻红。
        const done: MessageEntry = cloneMessage(wired.store.getMessages()[0]);
        done.photoFullPath = '/local/full.jpg';
        controller.onSnapshot([done], wired.store, 'private');
        expect(host.callOrder.includes('context')).assertFalse();
      } finally {
        AppStorage.setOrCreate(KEY_AUTOSAVE_PRIVATE, false);
      }
    });

    // 防的回归：autosaveEnabled 那道开关被绕过——关掉自动保存之后，新到的
    // 媒体仍然被排进队列，等它下载完就会被偷偷存进相册。
    it('onSnapshot: 自动保存关闭时不入队，之后带着本地路径出现也不保存', 0, (): void => {
      AppStorage.setOrCreate(KEY_AUTOSAVE_PRIVATE, false);
      const wired: WiredStore = newWiredStore(9);
      pushNewMessage(wired.bridge, photoMessage(90, 9, 900, 901));
      const host: FakeHost = new FakeHost();
      host.storeValue = wired.store;
      const controller: MediaSaveState = controllerOn(host);

      const pending: MessageEntry = cloneMessage(wired.store.getMessages()[0]);
      controller.onSnapshot([pending], wired.store, 'private');

      const done: MessageEntry = cloneMessage(wired.store.getMessages()[0]);
      done.photoFullPath = '/local/full.jpg';
      controller.onSnapshot([done], wired.store, 'private');

      expect(host.callOrder.includes('context')).assertFalse();
    });

    // 阳性对照：证明上面两条挡住的不是"自动保存永远不工作"。开着开关、消息
    // 带着本地路径进来时，确实会走到 saveMediaToGallery（经 host.context()）。
    // 没有这一条，把整个 processAutomaticGallerySave 删空，上面两条照样绿。
    it('onSnapshot: 自动保存开启且已下载时，确实经 host.context() 保存（阳性对照）', 0, (): void => {
      AppStorage.setOrCreate(KEY_AUTOSAVE_PRIVATE, true);
      try {
        const wired: WiredStore = newWiredStore(10);
        pushNewMessage(wired.bridge, photoMessage(100, 10, 1000, 1001));
        const host: FakeHost = new FakeHost();
        host.storeValue = wired.store;
        const controller: MediaSaveState = controllerOn(host);

        const done: MessageEntry = cloneMessage(wired.store.getMessages()[0]);
        done.photoFullPath = '/local/full.jpg';
        controller.onSnapshot([done], wired.store, 'private');

        expect(host.callOrder.includes('context')).assertTrue();
      } finally {
        AppStorage.setOrCreate(KEY_AUTOSAVE_PRIVATE, false);
      }
    });
  });
}
