import { describe, it, expect, beforeEach } from '@ohos/hypium';
import {
  DOCK_COLLAPSED, DOCK_EXPANDED, DOCK_FULL, dockMiniBarState, dockShowsAlbumBall,
  dockShowsPlayer, dockShowsTabs, nowPlayingTitle
} from '../main/ets/util/dockMiniBar';
import {
  clearNowPlaying, currentNowPlaying, NowPlaying, publishNowPlaying,
  resetNowPlayingChannel, subscribeNowPlaying
} from '../main/ets/util/nowPlayingChannel';

function track(messageId: number): NowPlaying {
  return {
    chatId: 7, messageId, title: 'Espresso', performer: 'Sabrina Carpenter',
    coverPath: '/data/cover.jpg', path: '/data/a.mp3', durationSec: 175
  };
}

export default function dockMiniBarTest() {
  describe('dockMiniBar', () => {
    it('没有播放就是完整四格，展开标志不起作用', 0, (): void => {
      expect(dockMiniBarState(false, false)).assertEqual(DOCK_FULL);
      expect(dockMiniBarState(false, true)).assertEqual(DOCK_FULL);
    });

    it('在播放：默认折叠，展开后是展开态', 0, (): void => {
      expect(dockMiniBarState(true, false)).assertEqual(DOCK_COLLAPSED);
      expect(dockMiniBarState(true, true)).assertEqual(DOCK_EXPANDED);
    });

    // 这条是这个判据存在的主要理由：播放一停必须掉回四格，否则底栏永远停在
    // 「只有一个头像」，用户再也点不到会话页签。
    it('播放结束时即使还标着展开，也必须掉回完整四格', 0, (): void => {
      expect(dockMiniBarState(false, true)).assertEqual(DOCK_FULL);
      expect(dockShowsTabs(dockMiniBarState(false, true))).assertTrue();
    });

    it('三态各画什么', 0, (): void => {
      expect(dockShowsTabs(DOCK_FULL)).assertTrue();
      expect(dockShowsAlbumBall(DOCK_FULL)).assertFalse();
      expect(dockShowsPlayer(DOCK_FULL)).assertFalse();

      expect(dockShowsTabs(DOCK_COLLAPSED)).assertTrue();
      expect(dockShowsAlbumBall(DOCK_COLLAPSED)).assertTrue();
      expect(dockShowsPlayer(DOCK_COLLAPSED)).assertFalse();

      expect(dockShowsTabs(DOCK_EXPANDED)).assertFalse();
      expect(dockShowsAlbumBall(DOCK_EXPANDED)).assertFalse();
      expect(dockShowsPlayer(DOCK_EXPANDED)).assertTrue();
    });

    it('曲名兜底到文件名', 0, (): void => {
      expect(nowPlayingTitle('Espresso', 'a.mp3')).assertEqual('Espresso');
      expect(nowPlayingTitle('   ', 'a.mp3')).assertEqual('a.mp3');
      expect(nowPlayingTitle('', '')).assertEqual('');
    });
  });

  describe('nowPlayingChannel', () => {
    beforeEach((): void => { resetNowPlayingChannel(); });

    // 底栏是在播放开始很久之后才挂上来的（用户从会话页退回列表），所以订阅
    // 必须立刻回灌当前值，否则退回列表时播放条是空的。
    it('订阅时立刻收到当前值', 0, (): void => {
      publishNowPlaying(track(11));
      let got: NowPlaying | null = null;
      subscribeNowPlaying((s: NowPlaying | null): void => { got = s; });
      expect(got !== null).assertTrue();
      expect(currentNowPlaying()?.messageId).assertEqual(11);
    });

    it('退订之后不再收到', 0, (): void => {
      let hits = 0;
      const off = subscribeNowPlaying((): void => { hits++; });
      expect(hits).assertEqual(1);
      off();
      publishNowPlaying(track(12));
      expect(hits).assertEqual(1);
    });

    // 切下一首时旧条目的收尾回调可能晚于新条目的发布到达；无条件清会把刚
    // 开始播的那一首一起抹掉，底栏于是闪一下变空。
    it('只有当前那条能清空自己', 0, (): void => {
      publishNowPlaying(track(11));
      clearNowPlaying(10);
      expect(currentNowPlaying()?.messageId).assertEqual(11);
      clearNowPlaying(11);
      expect(currentNowPlaying() === null).assertTrue();
    });
  });
}
