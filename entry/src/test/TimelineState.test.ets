import { describe, expect, it } from '@ohos/hypium';
import {
  TL_NEWER_ERROR, TL_NEWER_LOADING, TL_NONE, TL_OLDER_ERROR, TL_OLDER_LOADING,
  TL_SYNC_ERROR, TL_SYNC_LOADING,
  timelineError, timelineLoading, timelineStateMode, timelineStateText
} from '../main/ets/util/timelineState';

export default function timelineStateTest() {
  describe('timelineState', () => {
    it('列表还空着时不出胶囊——空状态卡片已经在说同样的话', 0, () => {
      expect(timelineStateMode(0, 'loading', 'idle', 'idle')).assertEqual(TL_NONE);
      expect(timelineStateMode(0, 'error', 'error', 'error')).assertEqual(TL_NONE);
    });

    it('什么都不在发生时不出胶囊', 0, () => {
      expect(timelineStateMode(9, 'ready', 'idle', 'idle')).assertEqual(TL_NONE);
    });

    it('整段历史盖过分页：两边同时出事只说整段的', 0, () => {
      // 否则用户看到"正在加载更旧"，而实际上整个会话都没拉起来。
      expect(timelineStateMode(9, 'error', 'error', 'error')).assertEqual(TL_SYNC_ERROR);
      expect(timelineStateMode(9, 'loading', 'loading', 'loading')).assertEqual(TL_SYNC_LOADING);
      expect(timelineStateMode(9, 'error', 'loading', 'loading')).assertEqual(TL_SYNC_ERROR);
    });

    it('失败盖过加载中', 0, () => {
      expect(timelineStateMode(9, 'ready', 'error', 'loading')).assertEqual(TL_OLDER_ERROR);
      expect(timelineStateMode(9, 'ready', 'loading', 'error')).assertEqual(TL_NEWER_ERROR);
    });

    it('更旧盖过更新（同档时）', 0, () => {
      expect(timelineStateMode(9, 'ready', 'error', 'error')).assertEqual(TL_OLDER_ERROR);
      expect(timelineStateMode(9, 'ready', 'loading', 'loading')).assertEqual(TL_OLDER_LOADING);
    });

    it('单独一路出事时如实报出', 0, () => {
      expect(timelineStateMode(9, 'ready', 'loading', 'idle')).assertEqual(TL_OLDER_LOADING);
      expect(timelineStateMode(9, 'ready', 'idle', 'loading')).assertEqual(TL_NEWER_LOADING);
      expect(timelineStateMode(9, 'ready', 'idle', 'error')).assertEqual(TL_NEWER_ERROR);
    });

    it('加载/失败的分类是显式列表，不靠名字里带不带某个词', 0, () => {
      expect(timelineLoading(TL_SYNC_LOADING)).assertTrue();
      expect(timelineLoading(TL_OLDER_LOADING)).assertTrue();
      expect(timelineLoading(TL_NEWER_LOADING)).assertTrue();
      expect(timelineLoading(TL_SYNC_ERROR)).assertFalse();
      expect(timelineError(TL_SYNC_ERROR)).assertTrue();
      expect(timelineError(TL_OLDER_ERROR)).assertTrue();
      expect(timelineError(TL_NEWER_ERROR)).assertTrue();
      expect(timelineError(TL_OLDER_LOADING)).assertFalse();
      // 空档两边都不算——胶囊根本不该出现。
      expect(timelineLoading(TL_NONE)).assertFalse();
      expect(timelineError(TL_NONE)).assertFalse();
      // 没见过的档也不该被猜成加载中。
      expect(timelineLoading('reloadingTail')).assertFalse();
      expect(timelineError('recoverableError')).assertFalse();
    });

    it('任何一档要么加载要么失败，不会两者皆是', 0, () => {
      const modes: string[] = [TL_NONE, TL_SYNC_ERROR, TL_SYNC_LOADING,
        TL_OLDER_ERROR, TL_NEWER_ERROR, TL_OLDER_LOADING, TL_NEWER_LOADING];
      for (const m of modes) {
        expect(timelineLoading(m) && timelineError(m)).assertFalse();
      }
    });

    it('每一档有自己的文案，没有两档共用', 0, () => {
      expect(timelineStateText(TL_SYNC_ERROR)).assertEqual('cp_sync_failed');
      expect(timelineStateText(TL_SYNC_LOADING)).assertEqual('cp_syncing_latest');
      expect(timelineStateText(TL_OLDER_ERROR)).assertEqual('cp_older_failed');
      expect(timelineStateText(TL_NEWER_ERROR)).assertEqual('cp_newer_failed');
      expect(timelineStateText(TL_OLDER_LOADING)).assertEqual('cp_loading_older');
      expect(timelineStateText(TL_NEWER_LOADING)).assertEqual('cp_loading_newer');
      const texts: string[] = [
        timelineStateText(TL_SYNC_ERROR), timelineStateText(TL_SYNC_LOADING),
        timelineStateText(TL_OLDER_ERROR), timelineStateText(TL_NEWER_ERROR),
        timelineStateText(TL_OLDER_LOADING), timelineStateText(TL_NEWER_LOADING)
      ];
      for (let a = 0; a < texts.length; a++) {
        for (let b = a + 1; b < texts.length; b++) {
          expect(texts[a] === texts[b]).assertFalse();
        }
      }
    });
  });
}
