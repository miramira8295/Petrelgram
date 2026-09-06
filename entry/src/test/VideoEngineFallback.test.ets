import { describe, expect, it } from '@ohos/hypium';
import {
  AV_ERR_UNSUPPORT_CAPABILITY, AV_ERR_UNSUPPORT_FORMAT, classifyVideoError,
  isEngineUnsupportedError, isTransientError, playbackStalled, shouldAutoRetry,
  STALL_FALLBACK_MS
} from '../main/ets/util/videoEngineFallback';

// 全屏播放引擎失败分流判据的测试。
//
// 这一簇的失败模式是"用户看到播放失败"——没有任何本地手段能发现分类写错了，
// 所以判据必须是纯函数并在这里钉住。三档各自钉的是：
//   engine-unsupported —— 换引擎（ijk 兜格式）
//   transient          —— 保持原有退避重试
//   fatal              —— 直接报错
//
// 错误码取自 SDK 的 media.AVErrorCode。测试里也用字面量，且**故意不 import
// 那个枚举**：如果哪天 SDK 改了枚举值，这里的字面量与被测文件的字面量会同时
// 变得过时，而不是一个变一个不变——那样测试仍然绿，但线上判据已经错了。
// 对着 @ohos.multimedia.media.d.ts:1422-1600 核。

export default function videoEngineFallbackTest() {
  describe('VideoEngineFallback', () => {

    // ——— engine-unsupported ———

    it('格式不支持(5400106)判为换引擎', 0, () => {
      expect(isEngineUnsupportedError(5400106)).assertTrue();
      expect(classifyVideoError(5400106)).assertEqual('engine-unsupported');
      // 常量本身也钉一下，防止有人改常量却没改测试
      expect(AV_ERR_UNSUPPORT_FORMAT).assertEqual(5400106);
    });

    it('能力不支持(801)判为换引擎', 0, () => {
      expect(isEngineUnsupportedError(801)).assertTrue();
      expect(classifyVideoError(801)).assertEqual('engine-unsupported');
      expect(AV_ERR_UNSUPPORT_CAPABILITY).assertEqual(801);
    });

    // **这条是本次改动的实质**：确定性失败不该重试。
    // 删掉 shouldAutoRetry 里的 transient 判定，这条立刻红。
    it('换引擎那一档一律不重试，哪怕次数还没用完', 0, () => {
      expect(shouldAutoRetry(5400106, 0, 3)).assertFalse();
      expect(shouldAutoRetry(801, 0, 3)).assertFalse();
    });

    // ——— transient ———

    it('IO(5400103)与超时(5400104)判为暂时性', 0, () => {
      expect(isTransientError(5400103)).assertTrue();
      expect(isTransientError(5400104)).assertTrue();
      expect(classifyVideoError(5400103)).assertEqual('transient');
    });

    // 按号段判而不是逐个列：5411xxx 是官方划给 IO 的段，新增子类天然也该重试。
    it('5411xxx 整段 IO 子类判为暂时性', 0, () => {
      expect(isTransientError(5411001)).assertTrue();  // HOST_NOT_FOUND
      expect(isTransientError(5411004)).assertTrue();  // NETWORK_UNAVAILABLE
      expect(isTransientError(5411009)).assertTrue();  // SSL_CONNECTION_FAILED
      // 段内一个尚未定义的号也该走重试——这正是按段判的目的
      expect(isTransientError(5411999)).assertTrue();
    });

    it('号段边界：5411000 在段内，5412000 在段外', 0, () => {
      expect(isTransientError(5411000)).assertTrue();
      expect(isTransientError(5412000)).assertFalse();
    });

    it('暂时性失败在次数未用完时重试、用完后不再重试', 0, () => {
      expect(shouldAutoRetry(5400103, 0, 3)).assertTrue();
      expect(shouldAutoRetry(5400103, 2, 3)).assertTrue();
      expect(shouldAutoRetry(5400103, 3, 3)).assertFalse();
    });

    // ——— fatal ———

    it('无权限(201)/参数错(401)/服务挂了(5400105)判为致命，不重试也不换引擎', 0, () => {
      expect(classifyVideoError(201)).assertEqual('fatal');
      expect(classifyVideoError(401)).assertEqual('fatal');
      expect(classifyVideoError(5400105)).assertEqual('fatal');
      expect(isEngineUnsupportedError(5400105)).assertFalse();
      expect(shouldAutoRetry(5400105, 0, 3)).assertFalse();
    });

    it('内存不足(5400101)与操作不允许(5400102)判为致命', 0, () => {
      expect(classifyVideoError(5400101)).assertEqual('fatal');
      expect(classifyVideoError(5400102)).assertEqual('fatal');
    });

    // 音频打断(5400107)不是播放失败，不该走到这条链上；万一走到了，
    // 也必须是 fatal 而不是换引擎——换引擎解决不了被打断。
    it('音频打断(5400107)不判为换引擎', 0, () => {
      expect(isEngineUnsupportedError(5400107)).assertFalse();
      expect(classifyVideoError(5400107)).assertEqual('fatal');
    });

    it('未知错误码兜底为致命', 0, () => {
      expect(classifyVideoError(0)).assertEqual('fatal');
      expect(classifyVideoError(999999)).assertEqual('fatal');
      expect(classifyVideoError(-1)).assertEqual('fatal');
    });
  });

  // ——— 静默卡死：AVPlayer 一个错都不报，就是不出帧 ———
  //
  // 用户报「Pad 上自己发的视频点开是黑屏，也不转圈」。错误码那条路对这类
  // 失败完全无效，因为压根没有错误码。
  describe('playbackStalled', () => {
    it('数据齐 + 说在播 + 位置不动够久 ⇒ 换引擎', 0, () => {
      expect(playbackStalled(true, 100, STALL_FALLBACK_MS)).assertTrue();
      expect(playbackStalled(true, 100, STALL_FALLBACK_MS + 5000)).assertTrue();
    });

    it('没到时限不动手', 0, () => {
      expect(playbackStalled(true, 100, STALL_FALLBACK_MS - 1)).assertFalse();
      expect(playbackStalled(true, 100, 0)).assertFalse();
    });

    it('没在播就不算卡死（暂停、实况停在首帧）', 0, () => {
      expect(playbackStalled(false, 100, STALL_FALLBACK_MS * 10)).assertFalse();
    });

    // 这一条是整个判据里最要紧的一道闸：缓冲不足导致的停顿有自己的重试路径，
    // 把它误判成"解不了"会让网络一卡就换引擎。
    it('数据没齐一律不换引擎——那是网络卡顿不是解码失败', 0, () => {
      expect(playbackStalled(true, 99, STALL_FALLBACK_MS * 10)).assertFalse();
      expect(playbackStalled(true, 0, STALL_FALLBACK_MS * 10)).assertFalse();
    });

    it('时限是 4 秒——改这个数会直接改变误判率，钉住它', 0, () => {
      expect(STALL_FALLBACK_MS).assertEqual(4000);
    });
  });
}
