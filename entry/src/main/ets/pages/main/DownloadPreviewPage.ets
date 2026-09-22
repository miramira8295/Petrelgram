import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { MediaViewerOverlay, VIEWER_CHROME_ON_OPEN } from '../chat/MediaViewerOverlay';
import { MessageEntry, buildMessageEntry } from '../../store/MessageEntry';
import { getUserStore } from '../../tdkit/Globals';
import { AlbumGroup, collapseAlbums } from '../../util/collapseAlbums';
import { DC_KIND_VIDEO, DC_STATE_COMPLETE, DownloadCenterItem } from '../../util/downloadCenterModel';
import { viewerBaseMessage, viewerEntryFor, viewerIndexOf, viewerMessageIdAt } from '../../util/downloadViewerSet';
import { saveFileToDownloads, saveMediaToGallery } from '../../util/mediaSaver';
import { initVideoPosterStore } from '../../util/videoPosterStore';
import { logChatNavFailure, navigateToChat } from '../../util/chatNav';
import { str } from '../../util/strings';
import { logE, logI } from '../../util/log';

@Builder
export function DownloadPreviewPageBuilder(): void {
  DownloadPreviewPage();
}

// 下载中心的全屏查看（2026-09-15 第三版）：直接挂聊天详情的 MediaViewerOverlay。
// 下载中心把当前页签 + 搜索下能看的图片 / 视频拼成一组传进来（util/downloadViewerSet），这里转成临时消息、拼成一个
// 相册——查看器本来就在相册成员之间左右滑。没有会话 store：文件已经在本地，没下完的视频按 fileId 流式播。
// 仍然是推一层独立的 NavDestination（第一版挂 bindContentCover 在 HdsSubDestination 里，真机上点了没反应）。
@ComponentV2
export struct DownloadPreviewPage {
  @Local private messages: MessageEntry[] = [];
  @Local private groups: AlbumGroup[] = [];
  @Local private viewerMsgId: number = 0;
  @Local private initIdx: number = 0;
  // 与会话详情那边同一个初值（issue #217）：同一个查看器组件、同一个"点一下
  // 放大到全屏"的手势，两个入口不该一个默认带 chrome、一个不带。
  @Local private chromeVisible: boolean = VIEWER_CHROME_ON_OPEN;
  @Local private videoLandscape: boolean = false;
  @Local private topSafe: number = 0;
  private items: DownloadCenterItem[] = [];
  private navStack: NavPathStack | undefined = undefined;

  private ctx(): common.UIAbilityContext {
    return getContext(this) as common.UIAbilityContext;
  }

  private close(): void {
    const stack: NavPathStack | undefined = this.navStack;
    if (stack === undefined) {
      logE('DownloadPreviewPage.close: navStack missing');
      return;
    }
    stack.pop();
  }

  private applyParams(param: Object | undefined): void {
    const p = param as Record<string, Object> | undefined;
    const items: DownloadCenterItem[] = p !== undefined ? ((p['items'] as DownloadCenterItem[] | undefined) ?? []) : [];
    const start: number = p !== undefined ? ((p['startIndex'] as number | undefined) ?? 0) : 0;
    if (items.length === 0 || start < 0 || start >= items.length) {
      logE(`[DC] viewer: bad params items=${items.length} start=${start}`);
      this.close();
      return;
    }
    const base: MessageEntry = buildMessageEntry(viewerBaseMessage(), getUserStore());
    const entries: MessageEntry[] = items.map((it: DownloadCenterItem, i: number): MessageEntry =>
      viewerEntryFor(base, it, viewerMessageIdAt(i)));
    initVideoPosterStore(this.ctx().cacheDir);
    this.items = items;
    this.messages = entries;
    this.groups = collapseAlbums(entries);
    this.topSafe = AppStorage.get<number>('topSafeHeight') ?? 0;
    this.initIdx = start;
    this.viewerMsgId = viewerMessageIdAt(start);
    logI(`[DC] viewer items=${items.length} start=${start} kind=${items[start].kind}`);
  }

  private current(): DownloadCenterItem | null {
    const index: number = viewerIndexOf(this.viewerMsgId);
    return index >= 0 && index < this.items.length ? this.items[index] : null;
  }

  private saveCurrent(toFiles: boolean): void {
    const it: DownloadCenterItem | null = this.current();
    if (it === null || it.state !== DC_STATE_COMPLETE || it.path === '') {
      promptAction.showToast({ message: str('media_file_unavailable'), duration: 1800 });
      return;
    }
    if (toFiles) {
      saveFileToDownloads(this.ctx(), it.path, it.name);
      return;
    }
    saveMediaToGallery(this.ctx(), it.path, it.kind === DC_KIND_VIDEO).catch((e: Object): void => {
      logE(`[DC] viewer save failed: ${JSON.stringify(e)}`);
    });
  }

  // 这一条是不是还能回到原消息。判据与列表长按菜单一致（downloadCenterRowVM.canJump）。
  private canShowInChat(): boolean {
    const it: DownloadCenterItem | null = this.current();
    return it !== null && it.chatId !== 0 && it.messageId !== 0;
  }

  private showInChat(): void {
    const it: DownloadCenterItem | null = this.current();
    if (it === null || it.chatId === 0 || it.messageId === 0) {
      // 走到这里说明菜单项不该出现却出现了（或条目在这一瞬被换掉）。菜单已按
      // canShowInChat 隐藏，所以正常路径到不了这儿——只记一行，不为一个够不着的
      // 分支新增一个要翻译进全部 locale 的资源键。
      logE('[DC] viewer: show-in-chat without a source message');
      return;
    }
    const params: Record<string, Object> = { 'chatId': it.chatId, 'jumpTo': it.messageId };
    navigateToChat(params).catch(logChatNavFailure);
  }

  build() {
    NavDestination() {
      Stack() {
        if (this.viewerMsgId !== 0) {
          MediaViewerOverlay({
            topSafe: this.topSafe,
            viewerMsgId: this.viewerMsgId,
            onViewerMsgIdChange: (msgId: number): void => { this.viewerMsgId = msgId; },
            chromeVisible: this.chromeVisible,
            onChromeVisibleChange: (visible: boolean): void => { this.chromeVisible = visible; },
            videoLandscape: this.videoLandscape,
            onVideoLandscapeChange: (landscape: boolean): void => { this.videoLandscape = landscape; },
            messages: this.messages,
            groups: this.groups,
            initIdx: this.initIdx,
            store: null,
            chatId: 0,
            chatTitle: '',
            nowSec: Math.floor(Date.now() / 1000),
            downloadsMode: true,
            canShowInChat: this.canShowInChat(),
            onRequestClose: (): void => { this.close(); },
            onSaveMedia: (): void => { this.saveCurrent(false); },
            onSaveMediaToFiles: (): void => { this.saveCurrent(true); },
            onShowInChat: (): void => { this.showInChat(); }
          });
        }
      }
      .width('100%').height('100%')
      .backgroundColor(Color.Black);
    }
    .hideTitleBar(true)
    .backgroundColor(Color.Black)
    .onReady((ctx: NavDestinationContext): void => {
      this.navStack = ctx.pathStack;
      this.applyParams(ctx.pathInfo.param as Object | undefined);
    });
  }
}
