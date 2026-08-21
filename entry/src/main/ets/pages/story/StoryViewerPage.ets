import { router } from '@kit.ArkUI';
import { getTdClient, getChatStore, getStoryStore } from '../../tdkit/Globals';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import { StoryRingEntry } from '../../store/StoryStore';
import { AvatarView } from '../chatlist/AvatarView';
import { StoryVideoView } from './StoryVideoView';
import { logE } from '../../util/log';

const PHOTO_DISPLAY_MS: number = 5000;

// 全屏故事查看器：分段进度条 + 自动推进 + 点击左右切换 + 观看上报。
// 一个页面实例遍历一个会话的全部活跃故事，看完自动切下一个有故事的会话。
@Entry
@Component
struct StoryViewerPage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State chatId: number = 0;
  @State storyIds: number[] = [];
  @State index: number = 0;
  @State mediaPath: string = '';
  @State isVideo: boolean = false;
  @State caption: string = '';
  @State loadFailed: boolean = false;
  @State progress: number = 0;       // 0..1 当前段进度
  @State paused: boolean = false;
  @State chatTitle: string = '';
  @State chatAvatar: string = '';
  @State chatInitials: string = '?';
  private active: boolean = false;
  private loadSeq: number = 0;
  private progressTimer: number = -1;
  private segmentStartMs: number = 0;
  private segmentDurationMs: number = PHOTO_DISPLAY_MS;
  private pausedElapsedMs: number = 0;

  aboutToAppear(): void {
    this.active = true;
    const params = router.getParams() as Record<string, Object> | undefined;
    const chatId: number = params !== undefined
      ? ((params['chatId'] as number | undefined) ?? 0) : 0;
    this.enterChat(chatId, true);
  }

  aboutToDisappear(): void {
    this.active = false;
    this.stopProgress();
    this.reportClose();
  }

  private currentStoryId(): number {
    return this.index >= 0 && this.index < this.storyIds.length
      ? this.storyIds[this.index] : 0;
  }

  // 进入一个会话的故事组：优先从第一条未读开始。
  private enterChat(chatId: number, initial: boolean): void {
    const entry: StoryRingEntry | undefined = getStoryStore().entryOf(chatId);
    if (chatId === 0 || entry === undefined || entry.storyIds.length === 0) {
      if (initial) {
        this.loadFailed = true;
      } else {
        router.back();
      }
      return;
    }
    this.reportClose();
    this.chatId = chatId;
    this.storyIds = entry.storyIds;
    const firstUnread: number = entry.storyIds.findIndex(
      (id: number): boolean => id > entry.maxReadStoryId);
    this.index = firstUnread >= 0 ? firstUnread : 0;
    const chat = getChatStore().entryOf(chatId);
    this.chatTitle = chat !== undefined ? chat.title : '';
    this.chatAvatar = chat !== undefined ? chat.avatarPath : '';
    this.chatInitials = chat !== undefined ? chat.initials : '?';
    this.loadCurrent();
  }

  private loadCurrent(): void {
    const storyId: number = this.currentStoryId();
    if (storyId === 0) {
      router.back();
      return;
    }
    const seq: number = ++this.loadSeq;
    this.mediaPath = '';
    this.caption = '';
    this.loadFailed = false;
    this.progress = 0;
    this.paused = false;
    this.stopProgress();
    const req: TdRequest = { '@type': 'getStory' };
    req['story_poster_chat_id'] = this.chatId;
    req['story_id'] = storyId;
    req['only_local'] = false;
    getTdClient().send(req).then((story: TdObject): void => {
      if (!this.active || seq !== this.loadSeq) {
        return;
      }
      this.reportOpen(storyId);
      const captionObject = story['caption'] as TdObject | undefined;
      this.caption = captionObject !== undefined
        ? ((captionObject['text'] as string | undefined) ?? '') : '';
      this.resolveMedia(story, seq);
    }).catch((e: TdError): void => {
      if (!this.active || seq !== this.loadSeq) {
        return;
      }
      logE(`StoryViewerPage.getStory(${storyId}) failed: ${e.message}`);
      this.loadFailed = true;
    });
  }

  private resolveMedia(story: TdObject, seq: number): void {
    const content = story['content'] as TdObject | undefined;
    const contentType: string = content !== undefined
      ? ((content['@type'] as string | undefined) ?? '') : '';
    let fileObject: TdObject | undefined = undefined;
    if (contentType === 'storyContentPhoto') {
      const photo = content!['photo'] as TdObject | undefined;
      const sizes: TdObject[] = photo !== undefined
        ? ((photo['sizes'] as TdObject[] | undefined) ?? []) : [];
      const biggest = sizes.length > 0 ? sizes[sizes.length - 1] : undefined;
      fileObject = biggest !== undefined
        ? biggest['photo'] as TdObject | undefined : undefined;
      this.isVideo = false;
    } else if (contentType === 'storyContentVideo') {
      const video = content!['video'] as TdObject | undefined;
      fileObject = video !== undefined
        ? video['video'] as TdObject | undefined : undefined;
      this.isVideo = true;
    } else {
      this.loadFailed = true; // storyContentUnsupported
      return;
    }
    const fileId: number = fileObject !== undefined
      ? ((fileObject['id'] as number | undefined) ?? 0) : 0;
    if (fileId === 0) {
      this.loadFailed = true;
      return;
    }
    const local = fileObject!['local'] as TdObject | undefined;
    const readyPath: string = local !== undefined &&
      ((local['is_downloading_completed'] as boolean | undefined) ?? false)
      ? ((local['path'] as string | undefined) ?? '') : '';
    if (readyPath !== '') {
      this.showMedia(readyPath);
      return;
    }
    // synchronous 下载：promise 在文件完成时回来，避免手工订阅 updateFile。
    const download: TdRequest = { '@type': 'downloadFile' };
    download['file_id'] = fileId;
    download['priority'] = 32;
    download['synchronous'] = true;
    getTdClient().send(download, 60000).then((file: TdObject): void => {
      if (!this.active || seq !== this.loadSeq) {
        return;
      }
      const downloadedLocal = file['local'] as TdObject | undefined;
      const path: string = downloadedLocal !== undefined
        ? ((downloadedLocal['path'] as string | undefined) ?? '') : '';
      if (path !== '') {
        this.showMedia(path);
      } else {
        this.loadFailed = true;
      }
    }).catch((e: TdError): void => {
      if (!this.active || seq !== this.loadSeq) {
        return;
      }
      logE(`StoryViewerPage download failed: ${e.message}`);
      this.loadFailed = true;
    });
  }

  private showMedia(path: string): void {
    this.mediaPath = path;
    if (!this.isVideo) {
      this.startProgress(PHOTO_DISPLAY_MS);
    }
    // 视频：时长由播放器 prepared 后回调 startProgress。
  }

  private startProgress(durationMs: number): void {
    this.stopProgress();
    this.segmentDurationMs = Math.max(1000, durationMs);
    this.segmentStartMs = Date.now();
    this.pausedElapsedMs = 0;
    this.progress = 0;
    this.progressTimer = setInterval((): void => {
      if (this.paused) {
        return;
      }
      const elapsed: number = Date.now() - this.segmentStartMs;
      this.progress = Math.min(1, elapsed / this.segmentDurationMs);
      if (!this.isVideo && elapsed >= this.segmentDurationMs) {
        this.advance(1);
      }
    }, 80);
  }

  private stopProgress(): void {
    if (this.progressTimer !== -1) {
      clearInterval(this.progressTimer);
      this.progressTimer = -1;
    }
  }

  private setPaused(paused: boolean): void {
    if (this.paused === paused) {
      return;
    }
    if (paused) {
      this.pausedElapsedMs = Date.now() - this.segmentStartMs;
    } else {
      this.segmentStartMs = Date.now() - this.pausedElapsedMs;
    }
    this.paused = paused;
  }

  private reportOpen(storyId: number): void {
    const req: TdRequest = { '@type': 'openStory' };
    req['story_poster_chat_id'] = this.chatId;
    req['story_id'] = storyId;
    getTdClient().send(req).catch((): void => {});
  }

  private reportClose(): void {
    const storyId: number = this.currentStoryId();
    if (this.chatId === 0 || storyId === 0) {
      return;
    }
    const req: TdRequest = { '@type': 'closeStory' };
    req['story_poster_chat_id'] = this.chatId;
    req['story_id'] = storyId;
    getTdClient().send(req).catch((): void => {});
  }

  // direction: 1 下一条 / -1 上一条；越界时切换到相邻会话的故事组。
  private advance(direction: number): void {
    this.reportClose();
    const next: number = this.index + direction;
    if (next >= 0 && next < this.storyIds.length) {
      this.index = next;
      this.loadCurrent();
      return;
    }
    const ring: StoryRingEntry[] = getStoryStore().entries();
    const position: number = ring.findIndex(
      (entry: StoryRingEntry): boolean => entry.chatId === this.chatId);
    const neighbor: number = position + direction;
    if (position >= 0 && neighbor >= 0 && neighbor < ring.length) {
      this.enterChat(ring[neighbor].chatId, false);
      return;
    }
    router.back();
  }

  @Builder
  progressBars() {
    Row({ space: 4 }) {
      ForEach(this.storyIds, (_: number, barIndex: number) => {
        Row() {
          Row()
            .width(barIndex < this.index ? '100%'
              : (barIndex === this.index ? `${Math.round(this.progress * 100)}%` : '0%'))
            .height('100%')
            .backgroundColor(Color.White);
        }
        .layoutWeight(1).height(3).borderRadius(2)
        .backgroundColor('#4DFFFFFF')
        .clip(true);
      }, (_: number, barIndex: number): string => `bar_${barIndex}`);
    }
    .width('100%');
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column().width('100%').height('100%').backgroundColor(Color.Black);
      if (this.mediaPath !== '' && !this.isVideo) {
        Image(this.mediaPath).draggable(false)
          .width('100%').height('100%')
          .objectFit(ImageFit.Contain);
      }
      if (this.mediaPath !== '' && this.isVideo) {
        StoryVideoView({
          videoPath: this.mediaPath,
          paused: this.paused,
          onEnded: (): void => { this.advance(1); },
          onDuration: (durationMs: number): void => { this.startProgress(durationMs); }
        });
      }
      if (this.mediaPath === '' && !this.loadFailed) {
        Column() {
          LoadingProgress().width(36).height(36).color(Color.White);
        }
        .width('100%').height('100%').justifyContent(FlexAlign.Center);
      }
      if (this.loadFailed) {
        Column({ space: 10 }) {
          Text($r('app.string.story_unavailable')).fontSize(14).fontColor('#B8C4CF');
          Button($r('app.string.close')).onClick((): void => router.back());
        }
        .width('100%').height('100%').justifyContent(FlexAlign.Center);
      }
      // 点击区：左 1/3 上一条，右 2/3 下一条；长按暂停。
      Row() {
        Column().layoutWeight(1).height('100%')
          .onClick((): void => this.advance(-1));
        Column().layoutWeight(2).height('100%')
          .onClick((): void => this.advance(1));
      }
      .width('100%').height('100%')
      .gesture(LongPressGesture({ fingers: 1, repeat: false, duration: 220 })
        .onAction((): void => this.setPaused(true))
        .onActionEnd((): void => this.setPaused(false))
        .onActionCancel((): void => this.setPaused(false)));
      Column({ space: 8 }) {
        this.progressBars();
        Row({ space: 10 }) {
          AvatarView({
            avatarPath: this.chatAvatar, initials: this.chatInitials,
            colorSeed: this.chatId, avatarSize: 34
          });
          Text(this.chatTitle).fontSize(15).fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1);
          Row() {
            SymbolGlyph($r('sys.symbol.xmark')).fontSize(20).fontColor([Color.White]);
          }
          .width(38).height(38).borderRadius(19)
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#33000000')
          .onClick((): void => router.back());
        }
        .width('100%');
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: this.topSafe + 8 });
      if (this.caption !== '') {
        Text(this.caption)
          .fontSize(14).fontColor(Color.White)
          .maxLines(4).textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .padding({ left: 16, right: 16, top: 10, bottom: this.bottomSafe + 16 })
          .backgroundColor('#66000000')
          .position({ x: 0, y: '86%' });
      }
    }
    .width('100%').height('100%');
  }
}
