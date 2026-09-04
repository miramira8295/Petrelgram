import { describe, expect, it } from '@ohos/hypium';
import {
  MEDIA_PREFETCH_PRIORITY, MEDIA_USER_PRIORITY, THUMBNAIL_PRIORITY, mediaDownloadPriority
} from '../main/ets/util/downloadPriority';

export default function downloadPriorityTest() {
  describe('downloadPriority', () => {
    // 这条钉住本次回归：点开要看的视频走 exempt=true / manage=false，
    // 过去按 manage 挑优先级，发出去的是预取档 8。
    it('为看而下（exempt）拿用户档，不是预取档', 0, () => {
      expect(mediaDownloadPriority(false, true)).assertEqual(MEDIA_USER_PRIORITY);
    });

    it('为存而下（manage）拿用户档', 0, () => {
      expect(mediaDownloadPriority(true, false)).assertEqual(MEDIA_USER_PRIORITY);
    });

    it('又看又存也只是用户档', 0, () => {
      expect(mediaDownloadPriority(true, true)).assertEqual(MEDIA_USER_PRIORITY);
    });

    it('两者都不是才是背景预取', 0, () => {
      expect(mediaDownloadPriority(false, false)).assertEqual(MEDIA_PREFETCH_PRIORITY);
    });

    // 用户在等的东西必须排在后台缩略图前面——这正是「点开全屏加载很久」的成因。
    it('用户档高于缩略图档，缩略图档高于预取档', 0, () => {
      expect(MEDIA_USER_PRIORITY > THUMBNAIL_PRIORITY).assertTrue();
      expect(THUMBNAIL_PRIORITY > MEDIA_PREFETCH_PRIORITY).assertTrue();
    });

    it('分档都落在 TDLib 的 1..32 区间内', 0, () => {
      const tiers: number[] = [MEDIA_PREFETCH_PRIORITY, THUMBNAIL_PRIORITY, MEDIA_USER_PRIORITY];
      for (const t of tiers) {
        expect(t >= 1 && t <= 32).assertTrue();
      }
    });
  });
}
