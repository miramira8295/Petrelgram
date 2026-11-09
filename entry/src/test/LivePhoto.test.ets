import { describe, expect, it } from '@ohos/hypium';
import {
  LIVE_PHOTO_MAX_SECONDS, isLivePhotoVideo, livePhotoFileName
} from '../main/ets/util/livePhoto';

export default function livePhotoTest() {
  describe('livePhoto', () => {
    // 发出去的名字必须自己认得回来——这是整条链路的闭环。
    it('own_name_round_trips', 0, (): void => {
      const name: string = livePhotoFileName('20260829_143000_3');
      expect(isLivePhotoVideo(name, 2)).assertTrue();
    });

    // 时长还没探到（0）时不能因此判负：时长是用来排除长视频的，不是必要证据。
    it('unknown_duration_still_counts', 0, (): void => {
      expect(isLivePhotoVideo(livePhotoFileName('x'), 0)).assertTrue();
    });

    // 挡住「别人恰好这么命名的一段长视频」。
    it('long_video_is_not_live', 0, (): void => {
      expect(isLivePhotoVideo(livePhotoFileName('x'), LIVE_PHOTO_MAX_SECONDS + 1)).assertFalse();
      expect(isLivePhotoVideo(livePhotoFileName('x'), 600)).assertFalse();
    });

    it('boundary_duration_counts', 0, (): void => {
      expect(isLivePhotoVideo(livePhotoFileName('x'), LIVE_PHOTO_MAX_SECONDS)).assertTrue();
    });

    // 普通视频一概不算——包括恰好带了 PGLIVE 但没有下划线的。
    it('ordinary_videos_are_not_live', 0, (): void => {
      expect(isLivePhotoVideo('VID_20260829_143000.mp4', 2)).assertFalse();
      expect(isLivePhotoVideo('pglive.mp4', 2)).assertFalse();
      expect(isLivePhotoVideo('my_PGLIVE_holiday.mp4', 2)).assertFalse();
      expect(isLivePhotoVideo('', 2)).assertFalse();
    });

    // 大小写不敏感，且带路径也认得。
    it('case_and_path_insensitive', 0, (): void => {
      expect(isLivePhotoVideo('pglive_abc.MP4', 2)).assertTrue();
      expect(isLivePhotoVideo('/data/storage/el2/base/PGLIVE_abc.mp4', 2)).assertTrue();
    });

    // 扩展名不对不算：标记只对我们自己产出的 mp4 有意义。
    it('non_mp4_is_not_live', 0, (): void => {
      expect(isLivePhotoVideo('PGLIVE_abc.mov', 2)).assertFalse();
      expect(isLivePhotoVideo('PGLIVE_abc', 2)).assertFalse();
    });

    // 负数时长是脏值，不认。
    it('negative_duration_rejected', 0, (): void => {
      expect(isLivePhotoVideo(livePhotoFileName('x'), -1)).assertFalse();
    });
  });
}
