import { describe, it, expect } from '@ohos/hypium';
import {
  MAX_CONCURRENT_VIDEO_PREFETCH, PrefetchDecisionInput, VIDEO_PREFETCH_DWELL_MS, VIDEO_PREFETCH_HEAD_BYTES,
  VideoPrefetchRange, prefetchAllowed, prefetchRanges, prefetchRefusalReason
} from '../main/ets/util/videoPrefetchPolicy';
import { HIGH_WATER_BYTES, PREPARE_TAIL_BYTES } from '../main/ets/services/VideoStreamSession';

function input(over: Partial<PrefetchDecisionInput>): PrefetchDecisionInput {
  const base: PrefetchDecisionInput = {
    network: 'wifi', powerSaving: false,
    alreadyLocal: false, fileClaimed: false, fileId: 42
  };
  return {
    network: over.network ?? base.network,
    powerSaving: over.powerSaving ?? base.powerSaving,
    alreadyLocal: over.alreadyLocal ?? base.alreadyLocal,
    fileClaimed: over.fileClaimed ?? base.fileClaimed,
    fileId: over.fileId ?? base.fileId
  };
}

export default function videoPrefetchPolicyTest() {
  describe('videoPrefetchPolicy', () => {
    // ── 流量闸 ────────────────────────────────────────────────────────
    it('wifi_always_prefetches', 0, () => {
      expect(prefetchAllowed(input({ network: 'wifi' }))).assertTrue();
    });

    // 蜂窝也预取（用户 2026-09-09："蜂窝网络也下载"）。
    it('mobile_prefetches_too', 0, () => {
      expect(prefetchAllowed(input({ network: 'mobile' }))).assertTrue();
    });

    // 默认网络走 VPN 时承载是 BEARER_VPN；底下找不到物理承载就报 'vpn'——放行。
    // 真机上状态栏常年挂 VPN，30/30 次都被 network=other 拒掉过。
    it('vpn_prefetches_too', 0, () => {
      expect(prefetchAllowed(input({ network: 'vpn' }))).assertTrue();
    });

    it('roaming_none_and_other_never_prefetch', 0, () => {
      expect(prefetchAllowed(input({ network: 'roaming' }))).assertFalse();
      expect(prefetchAllowed(input({ network: 'none' }))).assertFalse();
      expect(prefetchAllowed(input({ network: 'other' }))).assertFalse();
    });

    it('power_saving_disables_prefetch', 0, () => {
      expect(prefetchAllowed(input({ powerSaving: true }))).assertFalse();
    });

    // ── 归属 ──────────────────────────────────────────────────────────
    // 带 limit 的 downloadFile 会**覆盖**同一文件正在进行的下载参数。播放器正在
    // 整份下的时候我们一发，就把它夹成 2MB。所以被认领的文件一律不碰。
    it('claimed_files_are_never_touched', 0, () => {
      expect(prefetchAllowed(input({ fileClaimed: true }))).assertFalse();
    });

    it('local_files_need_nothing', 0, () => {
      expect(prefetchAllowed(input({ alreadyLocal: true }))).assertFalse();
    });

    it('zero_file_id_is_not_a_video', 0, () => {
      expect(prefetchAllowed(input({ fileId: 0 }))).assertFalse();
    });

    // 日志要能一眼看出是哪一条拒的；放行给空串。
    it('refusal_reason_names_the_gate', 0, () => {
      expect(prefetchRefusalReason(input({}))).assertEqual('');
      expect(prefetchRefusalReason(input({ network: 'other' }))).assertEqual('network=other');
      expect(prefetchRefusalReason(input({ fileClaimed: true }))).assertEqual('claimed');
      expect(prefetchRefusalReason(input({ alreadyLocal: true }))).assertEqual('local');
      expect(prefetchRefusalReason(input({ powerSaving: true }))).assertEqual('power-saving');
      expect(prefetchRefusalReason(input({ fileId: 0 }))).assertEqual('not-video');
    });

    // ── 取哪几块 ──────────────────────────────────────────────────────
    // 头块必须覆盖 VideoStreamSession.start() 起手要的 HIGH_WATER（6MB）：低于它，
    // 起播那一刻播放器自己还得补，预取就白做。现在是 20MB（用户拍的）。
    it('head_block_covers_what_the_stream_session_asks_for_at_start', 0, () => {
      expect(VIDEO_PREFETCH_HEAD_BYTES >= HIGH_WATER_BYTES).assertTrue();
      expect(VIDEO_PREFETCH_HEAD_BYTES).assertEqual(20 * 1024 * 1024);
    });

    it('ranges_are_head_plus_tail', 0, () => {
      const r: VideoPrefetchRange[] = prefetchRanges(50 * 1024 * 1024);
      expect(r.length).assertEqual(2);
      expect(r[0].offset).assertEqual(0);
      expect(r[0].limit).assertEqual(VIDEO_PREFETCH_HEAD_BYTES);
      expect(r[1].offset).assertEqual(50 * 1024 * 1024 - PREPARE_TAIL_BYTES);
      expect(r[1].limit).assertEqual(PREPARE_TAIL_BYTES);
    });

    it('small_files_take_a_single_full_range', 0, () => {
      const r: VideoPrefetchRange[] = prefetchRanges(300 * 1024);
      expect(r.length).assertEqual(1);
      expect(r[0].offset).assertEqual(0);
      expect(r[0].limit).assertEqual(300 * 1024);
    });

    // 尺寸未知（0）：TDLib 的 limit=0 是"到文件末尾"，那就不是预取了。只要头块。
    it('unknown_size_takes_only_the_head', 0, () => {
      const r: VideoPrefetchRange[] = prefetchRanges(0);
      expect(r.length).assertEqual(1);
      expect(r[0].offset).assertEqual(0);
      expect(r[0].limit).assertEqual(VIDEO_PREFETCH_HEAD_BYTES);
    });

    // 一屏同时出现好几条视频时不能齐发：预取优先级低，但并发连接和内存不低。
    // 驻留要能挡住快速滑过（几百毫秒），又不能让用户停下来还等半天。
    it('dwell_is_a_few_hundred_ms', 0, () => {
      expect(VIDEO_PREFETCH_DWELL_MS >= 200 && VIDEO_PREFETCH_DWELL_MS <= 1000).assertTrue();
    });

    it('concurrency_cap_is_small', 0, () => {
      expect(MAX_CONCURRENT_VIDEO_PREFETCH >= 1 && MAX_CONCURRENT_VIDEO_PREFETCH <= 3).assertTrue();
    });
  });
}
