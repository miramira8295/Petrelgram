import { describe, it, expect } from '@ohos/hypium';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdBridge, TdObject } from '../main/ets/tdkit/TdTypes';
import { VideoHeadPrefetcher, VideoPrefetchHost, VideoRef } from '../main/ets/services/VideoHeadPrefetcher';
import { MAX_CONCURRENT_VIDEO_PREFETCH, VIDEO_PREFETCH_HEAD_BYTES } from '../main/ets/util/videoPrefetchPolicy';
import { THUMBNAIL_PRIORITY, VIDEO_HEAD_PREFETCH_PRIORITY } from '../main/ets/util/downloadPriority';

class FakeBridge implements TdBridge {
  onReceive: (json: string) => void = (): void => {};
  sent: string[] = [];
  init(cb: (json: string) => void): void { this.onReceive = cb; }
  send(json: string): void { this.sent.push(json); }

  requests(type: string): TdObject[] {
    return this.sent
      .map((j: string): TdObject => JSON.parse(j) as TdObject)
      .filter((r: TdObject): boolean => r['@type'] === type);
  }

  // 给最近一条 type 请求回一个成功应答（按 @extra 配对）。
  replyLast(type: string): void {
    const all: TdObject[] = this.requests(type);
    const last: TdObject = all[all.length - 1];
    const reply: TdObject = { '@type': 'file' };
    reply['@extra'] = last['@extra'];
    this.onReceive(JSON.stringify(reply));
  }
}

class FakeHost implements VideoPrefetchHost {
  bridge: FakeBridge;
  tdClient: TdClient;
  videos: Map<number, VideoRef> = new Map();
  claimed: Set<number> = new Set();
  networkValue: string = 'wifi';
  saving: boolean = false;

  // 字段初始化器里不能引用 this（ArkTS 报成"不支持结构类型"），照 ChatStore.test
  // 的样板在构造函数里装配。
  constructor() {
    this.bridge = new FakeBridge();
    this.tdClient = new TdClient(this.bridge);
    this.tdClient.start();
  }

  client: () => TdClient = (): TdClient => this.tdClient;
  videoAt: (messageId: number, albumIndex: number) => VideoRef | null =
    (messageId: number, _albumIndex: number): VideoRef | null => this.videos.get(messageId) ?? null;
  fileClaimed: (fileId: number) => boolean = (fileId: number): boolean => this.claimed.has(fileId);
  network: () => string = (): string => this.networkValue;
  powerSaving: () => boolean = (): boolean => this.saving;

  // 默认 200MB：要明显大于头块（20MB），才走"头 + 尾"两块的路径。
  video(messageId: number, fileId: number, size: number = 200 * 1024 * 1024, local: boolean = false): void {
    this.videos.set(messageId, { fileId: fileId, fileSize: size, local: local });
  }
}

// 单测里驻留取 0：同步起下载，断言不用等计时器。驻留本身单独有一条用例。
function prefetcherOn(host: FakeHost, dwellMs: number = 0): VideoHeadPrefetcher {
  const p: VideoHeadPrefetcher = new VideoHeadPrefetcher();
  p.bind(host, dwellMs);
  return p;
}

function tick(ms: number = 0): Promise<void> {
  return new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), ms));
}

const MB: number = 1024 * 1024;

export default function videoHeadPrefetcherTest() {
  describe('VideoHeadPrefetcher', () => {
    // 视频气泡一出现，先要头块——synchronous，应答回来才发尾块。
    // TDLib 对同一文件只保留一组 offset/limit，并发发头和尾就是尾把头顶掉。
    it('visible_video_requests_head_first_then_tail_after_it_lands', 0, async () => {
      const h = new FakeHost();
      h.video(100, 7, 200 * MB);
      const p = prefetcherOn(h);

      p.reportMedia(100, -1, 0.6);

      let dl: TdObject[] = h.bridge.requests('downloadFile');
      expect(dl.length).assertEqual(1);
      expect(dl[0]['file_id']).assertEqual(7);
      expect(dl[0]['offset']).assertEqual(0);
      expect(dl[0]['limit']).assertEqual(VIDEO_PREFETCH_HEAD_BYTES);
      // 与缩略图同档，仍低于用户主动要的 24 和正在看的 32
      expect(dl[0]['priority']).assertEqual(VIDEO_HEAD_PREFETCH_PRIORITY);
      expect(VIDEO_HEAD_PREFETCH_PRIORITY).assertEqual(THUMBNAIL_PRIORITY);
      expect(dl[0]['synchronous']).assertEqual(true);

      h.bridge.replyLast('downloadFile');
      await tick();
      dl = h.bridge.requests('downloadFile');
      expect(dl.length).assertEqual(2);
      expect(dl[1]['offset'] as number > 0).assertTrue();
      expect(dl[1]['limit']).assertEqual(1 * MB);
    });

    // 头块还没回来就划走了：取消，且头块之后回来也不再发尾块。
    it('leaving_before_the_head_lands_pauses_and_skips_the_tail', 0, async () => {
      const h = new FakeHost();
      h.video(100, 7);
      const p = prefetcherOn(h);

      p.reportMedia(100, -1, 0.6);
      p.dropMedia(100, -1);

      const cancels: TdObject[] = h.bridge.requests('cancelDownloadFile');
      expect(cancels.length).assertEqual(1);
      expect(cancels[0]['file_id']).assertEqual(7);
      expect(cancels[0]['only_if_pending']).assertEqual(false);
      expect(p.activeCount()).assertEqual(0);

      h.bridge.replyLast('downloadFile');
      await tick();
      expect(h.bridge.requests('downloadFile').length).assertEqual(1);
    });

    // 同一格反复上报 ratio（滚动时每帧都可能来）只发一次。
    it('repeated_ratio_reports_send_once', 0, () => {
      const h = new FakeHost();
      h.video(100, 7);
      const p = prefetcherOn(h);

      p.reportMedia(100, -1, 0.2);
      p.reportMedia(100, -1, 0.5);
      p.reportMedia(100, -1, 1.0);

      expect(h.bridge.requests('downloadFile').length).assertEqual(1);
    });

    // ratio 归零等同划走。
    it('zero_ratio_counts_as_gone', 0, () => {
      const h = new FakeHost();
      h.video(100, 7);
      const p = prefetcherOn(h);

      p.reportMedia(100, -1, 0.6);
      p.reportMedia(100, -1, 0);

      expect(h.bridge.requests('cancelDownloadFile').length).assertEqual(1);
    });

    // **被认领的文件既不发也不取消。** 发了会把播放器的整份下载夹成 20MB；
    // 取消了会把用户正在看的东西掐断。
    it('claimed_files_are_neither_requested_nor_cancelled', 0, () => {
      const h = new FakeHost();
      h.video(100, 7);
      h.claimed.add(7);
      const p = prefetcherOn(h);

      p.reportMedia(100, -1, 0.6);
      p.dropMedia(100, -1);

      expect(h.bridge.requests('downloadFile').length).assertEqual(0);
      expect(h.bridge.requests('cancelDownloadFile').length).assertEqual(0);
    });

    // 预取期间被播放器认领（用户点了播放）：划走时也不能取消。
    it('a_file_claimed_after_prefetch_started_is_not_cancelled_on_leave', 0, () => {
      const h = new FakeHost();
      h.video(100, 7);
      const p = prefetcherOn(h);

      p.reportMedia(100, -1, 0.6);
      h.claimed.add(7);
      p.dropMedia(100, -1);

      expect(h.bridge.requests('cancelDownloadFile').length).assertEqual(0);
    });

    it('local_files_are_skipped', 0, () => {
      const h = new FakeHost();
      h.video(100, 7, 200 * MB, true);
      const p = prefetcherOn(h);

      p.reportMedia(100, -1, 0.6);

      expect(h.bridge.requests('downloadFile').length).assertEqual(0);
    });

    it('non_video_rows_are_ignored', 0, () => {
      const h = new FakeHost();
      const p = prefetcherOn(h);

      p.reportMedia(100, -1, 0.6);
      p.dropMedia(100, -1);

      expect(h.bridge.sent.length).assertEqual(0);
    });

    it('roaming_does_not_prefetch', 0, () => {
      const h = new FakeHost();
      h.video(100, 7);
      h.networkValue = 'roaming';
      const p = prefetcherOn(h);

      p.reportMedia(100, -1, 0.6);

      expect(h.bridge.requests('downloadFile').length).assertEqual(0);
    });

    // 相册：每一格是不同的消息 / 不同的文件，各自预取；超过并发上限的排队，
    // 前面的划走后补位。
    it('album_videos_queue_past_the_concurrency_cap', 0, () => {
      const h = new FakeHost();
      const total: number = MAX_CONCURRENT_VIDEO_PREFETCH + 1;
      for (let i = 0; i < total; i++) {
        h.video(100 + i, 7 + i);
      }
      const p = prefetcherOn(h);

      for (let i = 0; i < total; i++) {
        p.reportMedia(100 + i, i, 0.6);
      }
      expect(p.activeCount()).assertEqual(MAX_CONCURRENT_VIDEO_PREFETCH);
      // 每个文件先只发头块，所以请求数 = 并发数
      expect(h.bridge.requests('downloadFile').length).assertEqual(MAX_CONCURRENT_VIDEO_PREFETCH);

      // 第一个划走 → 排队的那个补上来
      p.dropMedia(100, 0);
      expect(p.activeCount()).assertEqual(MAX_CONCURRENT_VIDEO_PREFETCH);
      const ids: number[] = h.bridge.requests('downloadFile').map((r: TdObject): number => r['file_id'] as number);
      expect(ids.indexOf(7 + total - 1) >= 0).assertTrue();
    });

    // 页面隐藏 / 查看器打开：**不取消**在途预取（查看器自己的流下载不经过归属集合，
    // 取消会把用户刚点开的那条掐断），只是不再开新的；回来按可见表重发。
    it('suspend_does_not_cancel_and_resume_restarts_visible_ones', 0, () => {
      const h = new FakeHost();
      h.video(100, 7);
      h.video(101, 8);
      const p = prefetcherOn(h);

      p.reportMedia(100, -1, 0.6);
      p.reportMedia(101, -1, 0.6);
      p.suspend();
      expect(h.bridge.requests('cancelDownloadFile').length).assertEqual(0);
      expect(p.activeCount()).assertEqual(0);

      p.resume();
      expect(p.activeCount()).assertEqual(2);
      expect(h.bridge.requests('downloadFile').length).assertEqual(2 + 2);
    });

    // suspend 之后旧的头块应答回来了：那条链已换代，不发尾块。
    it('a_head_landing_after_suspend_does_not_issue_a_tail', 0, async () => {
      const h = new FakeHost();
      h.video(100, 7);
      const p = prefetcherOn(h);

      p.reportMedia(100, -1, 0.6);
      p.suspend();
      h.bridge.replyLast('downloadFile');
      await tick();

      expect(h.bridge.requests('downloadFile').length).assertEqual(1);
    });

    // 页面销毁：没被认领的在途预取取消掉，且之后的上报一律忽略。
    it('dispose_cancels_and_ignores_later_reports', 0, () => {
      const h = new FakeHost();
      h.video(100, 7);
      const p = prefetcherOn(h);

      p.reportMedia(100, -1, 0.6);
      p.dispose();
      const before: number = h.bridge.sent.length;
      expect(h.bridge.requests('cancelDownloadFile').length).assertEqual(1);

      p.reportMedia(100, -1, 0.6);
      expect(h.bridge.sent.length).assertEqual(before);
    });

    // 驻留：快速滑过的气泡不开下载；停够了才开。
    it('dwell_skips_bubbles_that_leave_quickly', 0, async () => {
      const h = new FakeHost();
      h.video(100, 7);
      h.video(101, 8);
      const p = prefetcherOn(h, 30);

      p.reportMedia(100, -1, 0.6);
      p.dropMedia(100, -1);
      await tick(50);
      expect(h.bridge.requests('downloadFile').length).assertEqual(0);
      expect(h.bridge.requests('cancelDownloadFile').length).assertEqual(0);

      p.reportMedia(101, -1, 0.6);
      expect(h.bridge.requests('downloadFile').length).assertEqual(0);
      await tick(50);
      expect(h.bridge.requests('downloadFile').length).assertEqual(1);
      expect(h.bridge.requests('downloadFile')[0]['file_id']).assertEqual(8);
    });
  });
}
