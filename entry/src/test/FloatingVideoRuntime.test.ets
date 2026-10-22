import { describe, expect, it } from '@ohos/hypium';
import {
  closeFloatingVideo, collapseFloatingVideo, registerFloatingVideo, validVideoSnapshot,
  handoffVideoPlayback, VideoPlaybackControls, VideoPlaybackSnapshot
} from '../main/ets/util/floatingVideoRuntime';

export default function floatingVideoRuntimeTest() {
  describe('FloatingVideoRuntime', (): void => {
    it('close unregisters the owned session', 0, (): void => {
      let closed = 0;
      const off = registerFloatingVideo((): void => { closed++; off(); }, (): boolean => false);
      closeFloatingVideo();
      closeFloatingVideo();
      expect(closed).assertEqual(1);
      expect(collapseFloatingVideo()).assertFalse();
    });
    it('old teardown cannot unregister a replacement session', 0, (): void => {
      const old = registerFloatingVideo((): void => {}, (): boolean => false);
      let closed = false;
      const current = registerFloatingVideo((): void => { closed = true; }, (): boolean => true);
      old();
      expect(collapseFloatingVideo()).assertTrue();
      closeFloatingVideo();
      expect(closed).assertTrue();
      current();
    });
    it('back only consumes expanded playback', 0, (): void => {
      let expanded = true;
      const off = registerFloatingVideo((): void => {}, (): boolean => {
        const wasExpanded = expanded;
        expanded = false;
        return wasExpanded;
      });
      expect(collapseFloatingVideo()).assertTrue();
      expect(collapseFloatingVideo()).assertFalse();
      off();
    });
    it('snapshot preserves paused position and speed', 0, (): void => {
      expect(validVideoSnapshot({ positionMs: 12500, speedIndex: 3, playing: false })).assertTrue();
      expect(validVideoSnapshot({ positionMs: 0, speedIndex: 0, playing: true })).assertTrue();
    });
    it('unprepared playback cannot be handed off', 0, (): void => {
      expect(validVideoSnapshot(null)).assertFalse();
    });
    it('invalid position or speed is rejected', 0, (): void => {
      expect(validVideoSnapshot({ positionMs: -1, speedIndex: 1, playing: true })).assertFalse();
      expect(validVideoSnapshot({ positionMs: Number.NaN, speedIndex: 1, playing: true })).assertFalse();
      expect(validVideoSnapshot({ positionMs: 0, speedIndex: 4, playing: true })).assertFalse();
      expect(validVideoSnapshot({ positionMs: 0, speedIndex: 1.5, playing: true })).assertFalse();
    });
    it('mount then stop then activate prevents overlapping decoders', 0, (): void => {
      const events: string[] = [];
      const controls: VideoPlaybackControls = {
        snapshot: (): VideoPlaybackSnapshot => ({ positionMs: 12000, speedIndex: 2, playing: false }),
        stop: (): void => { events.push('stop'); }, toggle: (): void => {}
      };
      const ok = handoffVideoPlayback(controls, (snapshot: VideoPlaybackSnapshot): boolean => {
        expect(snapshot.positionMs).assertEqual(12000);
        expect(snapshot.speedIndex).assertEqual(2);
        expect(snapshot.playing).assertFalse();
        events.push('mount'); return true;
      }, (): void => { events.push('activate'); });
      expect(ok).assertTrue();
      expect(events.join(',')).assertEqual('mount,stop,activate');
    });
    it('failed mount leaves original playback running', 0, (): void => {
      let stopped = false;
      let activated = false;
      const controls: VideoPlaybackControls = {
        snapshot: (): VideoPlaybackSnapshot => ({ positionMs: 12, speedIndex: 1, playing: true }),
        stop: (): void => { stopped = true; }, toggle: (): void => {}
      };
      expect(handoffVideoPlayback(controls, (_snapshot: VideoPlaybackSnapshot): boolean => false,
        (): void => { activated = true; })).assertFalse();
      expect(stopped).assertFalse();
      expect(activated).assertFalse();
    });
    it('not prepared does not mount or stop anything', 0, (): void => {
      let mutated = false;
      const controls: VideoPlaybackControls = {
        snapshot: (): VideoPlaybackSnapshot | null => null,
        stop: (): void => { mutated = true; }, toggle: (): void => {}
      };
      expect(handoffVideoPlayback(controls, (_snapshot: VideoPlaybackSnapshot): boolean => {
        mutated = true; return true;
      }, (): void => { mutated = true; })).assertFalse();
      expect(mutated).assertFalse();
    });
  });
}
