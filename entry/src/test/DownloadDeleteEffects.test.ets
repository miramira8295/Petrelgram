import { describe, expect, it } from '@ohos/hypium';
import { DownloadDeleteEffects } from '../main/ets/util/downloadDeleteEffects';
import { DeferredRemoval } from '../main/ets/util/deferredRemoval';

export default function downloadDeleteEffectsTest(): void {
  describe('DownloadDeleteEffects', (): void => {
    it('only_current_tab_animates_and_completion_hands_off_once', 0, async (): Promise<void> => {
      const fx = new DownloadDeleteEffects(); const key = fx.rowKey('file-a');
      fx.channel(0).subscribe(key, (): void => {});
      fx.channel(1).subscribe(key, (): void => {});
      let count = 0;
      fx.start(0, ['file-a'], true, (): void => { count++; });
      expect(fx.channel(0).value(key)).assertEqual(1);
      expect(fx.channel(1).value(key)).assertEqual(0);
      expect(fx.isPending('file-a')).assertTrue();
      expect(count).assertEqual(0);
      fx.channel(0).complete(key);
      await Promise.resolve(); await Promise.resolve(); await Promise.resolve();
      expect(count).assertEqual(1);
      expect(fx.isPending('file-a')).assertFalse();
      fx.flush(); expect(count).assertEqual(1);
    });
    it('disabled_animation_hands_off_synchronously', 0, (): void => {
      const fx = new DownloadDeleteEffects(); let done = false;
      fx.start(0, ['file-a'], false, (): void => { done = true; });
      expect(done).assertTrue(); expect(fx.isPending('file-a')).assertFalse();
    });
    it('offscreen_rows_do_not_wait_for_the_timeout', 0, async (): Promise<void> => {
      const fx = new DownloadDeleteEffects(); let done = false;
      fx.start(0, ['file-a'], true, (): void => { done = true; });
      await Promise.resolve();
      expect(done).assertTrue();
    });
    it('next_batch_finishes_the_previous_batch_without_late_double_execution', 0, async (): Promise<void> => {
      const fx = new DownloadDeleteEffects(); let a = 0; let b = 0;
      fx.channel(0).subscribe(fx.rowKey('a'), (): void => {});
      fx.channel(0).subscribe(fx.rowKey('b'), (): void => {});
      fx.start(0, ['a'], true, (): void => { a++; });
      fx.start(0, ['b'], true, (): void => { b++; });
      expect(a).assertEqual(1); expect(b).assertEqual(0);
      await Promise.resolve(); await Promise.resolve(); await Promise.resolve();
      expect(b).assertEqual(0);
      fx.flush();
      await Promise.resolve(); await Promise.resolve(); await Promise.resolve();
      expect(a).assertEqual(1); expect(b).assertEqual(1);
    });
    it('animation_handoff_preserves_undo_and_page_exit_flushes_the_pending_delete', 0, (): void => {
      const fx = new DownloadDeleteEffects(); let commits = 0;
      const removal = new DeferredRemoval((): void => {}, 4000,
        (_run: () => void, _ms: number): number => 1, (_id: number): void => {});
      const schedule = (): void => removal.schedule({ ids: ['a'], message: 'removed',
        commit: (): void => { commits++; } });
      fx.channel(0).subscribe(fx.rowKey('a'), (): void => {});
      fx.start(0, ['a'], true, schedule);
      expect(removal.isHidden('a')).assertFalse();
      fx.flush();
      expect(removal.isHidden('a')).assertTrue(); expect(commits).assertEqual(0);
      removal.undo();
      expect(removal.isHidden('a')).assertFalse(); expect(commits).assertEqual(0);
      fx.start(0, ['a'], true, schedule);
      fx.flush(); removal.flush();
      expect(commits).assertEqual(1);
    });
  });
}
