import { IjkMediaPlayer } from '@ohos/ijkplayer';
import { VideoStreamSession } from './VideoStreamSession';
import { logW } from '../util/log';

// 边下边播的「直读」数据源（2026-10-10），取代 VideoRangeServer 那层本机 HTTP。
//
// 原来：播放器按 HTTP Range 向本机 socket 要数据 → 我们从 TDLib 的文件里读进 JS → 写回
// socket。视频的每个字节都要过一遍 JS。
//
// 现在：播放器（自编的 ijkplayer，见 libs/ 与隔壁 ohos_ijkplayer 仓库的
// cpp/ijkplayer/tdstream/）在原生层直接 pread TDLib 正在写的那个文件。这里只做两件事：
//   1. 把「文件路径 + 已下载的字节段」推给它（session 有新进度就推一次）；
//   2. 它读到还没下载的位置、或往前读了一段时，转给 session 去调度 TDLib 下载。
// 下载调度（分块、水位、预读、抢占）仍然全在 VideoStreamSession，没动。
export class VideoTdSource {
  private player: IjkMediaPlayer;
  private session: VideoStreamSession;
  private totalSize: number;
  private id: number = 0;
  private closed: boolean = false;
  private unsubProgress: (() => void) | null = null;

  constructor(player: IjkMediaPlayer, session: VideoStreamSession, totalSize: number) {
    this.player = player;
    this.session = session;
    this.totalSize = totalSize;
  }

  // 返回交给 setDataSource 的地址；'' = 这个播放器不支持（调用方走回 HTTP 或报错）。
  start(): string {
    this.id = this.player.tdStreamCreate(this.totalSize, (offset: number, urgent: boolean): void => {
      if (!this.closed) {
        this.session.noteReadHead(offset, urgent);
      }
    });
    if (this.id <= 0) {
      logW('VideoTdSource: tdStreamCreate unavailable');
      return '';
    }
    this.unsubProgress = this.session.subscribeProgress((): void => {
      this.push();
    });
    return `tdfile:${this.id}`;
  }

  private push(): void {
    if (this.closed || this.id <= 0) {
      return;
    }
    this.player.tdStreamUpdate(this.id, this.session.playerFilePath(), this.totalSize,
      this.session.bufferedRangesFlat());
  }

  // 播放器释放之后调用（顺序同原来的 HTTP 服务）。正在等数据的读取会立刻返回。
  close(): void {
    if (this.closed) {
      return;
    }
    this.closed = true;
    if (this.unsubProgress !== null) {
      this.unsubProgress();
      this.unsubProgress = null;
    }
    if (this.id > 0) {
      this.player.tdStreamClose(this.id);
      this.id = 0;
    }
  }
}
