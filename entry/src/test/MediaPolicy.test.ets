import { describe, it, expect } from '@ohos/hypium';
import {
  decideMedia, shouldPrefetchNeighbour, MediaContext, MediaSubject
} from '../main/ets/store/MediaPolicy';

// ArkTS 不支持 Partial<T> 工具类型，用等价的「全字段可选」接口代替，
// 断言与用例内容与 brief 逐字一致，只有这个辅助类型的定义方式变了。
interface MediaContextOverrides {
  inWindow?: boolean;
  isPlaySlot?: boolean;
  viewerOpen?: boolean;
  autoplayEnabled?: boolean;
  powerSaving?: boolean;
  networkMetered?: boolean;
  reduceAnimations?: boolean;
}

function ctx(over: MediaContextOverrides): MediaContext {
  const base: MediaContext = {
    inWindow: false, isPlaySlot: false, viewerOpen: false,
    autoplayEnabled: true, powerSaving: false, networkMetered: false,
    reduceAnimations: false
  };
  return {
    inWindow: over.inWindow ?? base.inWindow,
    isPlaySlot: over.isPlaySlot ?? base.isPlaySlot,
    viewerOpen: over.viewerOpen ?? base.viewerOpen,
    autoplayEnabled: over.autoplayEnabled ?? base.autoplayEnabled,
    powerSaving: over.powerSaving ?? base.powerSaving,
    networkMetered: over.networkMetered ?? base.networkMetered,
    reduceAnimations: over.reduceAnimations ?? base.reduceAnimations
  };
}

function photo(): MediaSubject {
  return {
    contentType: 'photo', isAnimation: false,
    needsThumb: true, needsFull: true, needsVideo: false
  };
}

function video(): MediaSubject {
  return {
    contentType: 'video', isAnimation: false,
    needsThumb: true, needsFull: false, needsVideo: true
  };
}

function gif(): MediaSubject {
  return {
    contentType: 'video', isAnimation: true,
    needsThumb: true, needsFull: false, needsVideo: true
  };
}

function voiceSubject(): MediaSubject {
  return {
    contentType: 'voice', isAnimation: false,
    needsThumb: false, needsFull: false, needsVideo: true
  };
}

function videoNoteSubject(): MediaSubject {
  return {
    contentType: 'videoNote', isAnimation: false,
    needsThumb: false, needsFull: false, needsVideo: true
  };
}

export default function mediaPolicyTest() {
  describe('MediaPolicy', () => {
    it('窗口外什么都不下', 0, () => {
      expect(decideMedia(photo(), ctx({})).length).assertEqual(0);
      expect(decideMedia(video(), ctx({})).length).assertEqual(0);
    });

    it('图片进窗口只下缩略图，不下高清', 0, () => {
      const got = decideMedia(photo(), ctx({ inWindow: true }));
      expect(got.length).assertEqual(1);
      expect(got[0]).assertEqual('thumb');
    });

    // I-1：高清图不再由 decideMedia 产出，即使查看器打开——否则 store 的
    // 全量遍历循环会对窗口内每一张照片都发起原图下载。高清下载完全交给
    // MediaViewerOverlay 自己对当前图与左右邻图调 requestFullPhoto 驱动。
    it('查看器打开也不再产出高清意图（改由查看器自驱）', 0, () => {
      const got = decideMedia(photo(), ctx({ inWindow: true, viewerOpen: true }));
      expect(got.indexOf('full') >= 0).assertFalse();
    });

    it('高清已在本地时不再请求', 0, () => {
      const done: MediaSubject = {
        contentType: 'photo', isAnimation: false,
        needsThumb: false, needsFull: false, needsVideo: false
      };
      expect(decideMedia(done, ctx({ inWindow: true, viewerOpen: true })).length).assertEqual(0);
    });

    it('视频进窗口只下封面，不下视频本体', 0, () => {
      const got = decideMedia(video(), ctx({ inWindow: true }));
      expect(got.length).assertEqual(1);
      expect(got[0]).assertEqual('thumb');
    });

    it('视频成为播放位才开流', 0, () => {
      const got = decideMedia(video(), ctx({ inWindow: true, isPlaySlot: true }));
      expect(got.indexOf('stream') >= 0).assertTrue();
    });

    it('关掉自动播放后，播放位也不自动开流', 0, () => {
      const got = decideMedia(video(), ctx({ inWindow: true, isPlaySlot: true, autoplayEnabled: false }));
      expect(got.indexOf('stream') < 0).assertTrue();
    });

    it('省电模式下不自动开流', 0, () => {
      const got = decideMedia(video(), ctx({ inWindow: true, isPlaySlot: true, powerSaving: true }));
      expect(got.indexOf('stream') < 0).assertTrue();
    });

    it('网络类型不影响图片与视频的意图', 0, () => {
      const free = decideMedia(video(), ctx({ inWindow: true, isPlaySlot: true }));
      const metered = decideMedia(video(), ctx({ inWindow: true, isPlaySlot: true, networkMetered: true }));
      expect(metered.join(',')).assertEqual(free.join(','));
    });

    it('GIF 进窗口即整文件下载（保持既有循环播放路径）', 0, () => {
      const got = decideMedia(gif(), ctx({ inWindow: true }));
      expect(got.indexOf('explicit') >= 0).assertTrue();
    });

    it('关掉自动播放后 GIF 也不下', 0, () => {
      const got = decideMedia(gif(), ctx({ inWindow: true, autoplayEnabled: false }));
      expect(got.indexOf('explicit') < 0).assertTrue();
    });

    // I-3：开启「减少动效」时 GIF 不该整文件下载——MessageBubble 反正不播。
    it('开启减少动效后 GIF 也不下', 0, () => {
      const got = decideMedia(gif(), ctx({ inWindow: true, reduceAnimations: true }));
      expect(got.indexOf('explicit') < 0).assertTrue();
    });

    it('语音进窗口自动下（体积小，播放即用）', 0, () => {
      const got = decideMedia(voiceSubject(), ctx({ inWindow: true }));
      expect(got.indexOf('explicit') >= 0).assertTrue();
    });

    // I-2：voice 无条件 eager，省电/关自动播放都不该拦住它。
    it('关掉自动播放后语音仍自动下', 0, () => {
      const got = decideMedia(voiceSubject(), ctx({ inWindow: true, autoplayEnabled: false }));
      expect(got.indexOf('explicit') >= 0).assertTrue();
    });

    it('省电模式下语音仍自动下', 0, () => {
      const got = decideMedia(voiceSubject(), ctx({ inWindow: true, powerSaving: true }));
      expect(got.indexOf('explicit') >= 0).assertTrue();
    });

    // I-2：videoNote 移出 EAGER_TYPES，受 autoAllowed 约束——省电模式/关自动
    // 播放都要拦得住，频道里连续圆形视频不该一次性拉满。
    it('videoNote 默认自动播放允许时自动下', 0, () => {
      const got = decideMedia(videoNoteSubject(), ctx({ inWindow: true }));
      expect(got.indexOf('explicit') >= 0).assertTrue();
    });

    it('关掉自动播放后 videoNote 不再自动下', 0, () => {
      const got = decideMedia(videoNoteSubject(), ctx({ inWindow: true, autoplayEnabled: false }));
      expect(got.indexOf('explicit') < 0).assertTrue();
    });

    it('省电模式下 videoNote 不再自动下', 0, () => {
      const got = decideMedia(videoNoteSubject(), ctx({ inWindow: true, powerSaving: true }));
      expect(got.indexOf('explicit') < 0).assertTrue();
    });

    it('文件与音乐不自动下', 0, () => {
      const doc: MediaSubject = {
        contentType: 'file', isAnimation: false,
        needsThumb: false, needsFull: false, needsVideo: true
      };
      expect(decideMedia(doc, ctx({ inWindow: true })).length).assertEqual(0);
    });

    it('计费网络下不做邻图预取', 0, () => {
      expect(shouldPrefetchNeighbour(ctx({ viewerOpen: true }))).assertTrue();
      expect(shouldPrefetchNeighbour(ctx({ viewerOpen: true, networkMetered: true }))).assertFalse();
      expect(shouldPrefetchNeighbour(ctx({ viewerOpen: false }))).assertFalse();
    });
  });
}
