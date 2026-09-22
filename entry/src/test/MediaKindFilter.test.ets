import { describe, it, expect } from '@ohos/hypium';
import {
  MEDIA_KINDS, MEDIA_KIND_ALL, MEDIA_KIND_PHOTO, MEDIA_KIND_VIDEO,
  mediaKindFilterOf, normalizeMediaKind
} from '../main/ets/util/mediaKindFilter';

export default function mediaKindFilterTest() {
  describe('MediaKindFilter', () => {
    it('三档各自映射到 TDLib 的过滤器', 0, () => {
      expect(mediaKindFilterOf(MEDIA_KIND_ALL)).assertEqual('searchMessagesFilterPhotoAndVideo');
      expect(mediaKindFilterOf(MEDIA_KIND_PHOTO)).assertEqual('searchMessagesFilterPhoto');
      expect(mediaKindFilterOf(MEDIA_KIND_VIDEO)).assertEqual('searchMessagesFilterVideo');
    });

    // 脏值不该让媒体页变成空白（过滤器名字打错 TDLib 会直接报错）。
    it('不认识的值回落到全部', 0, () => {
      expect(mediaKindFilterOf('')).assertEqual('searchMessagesFilterPhotoAndVideo');
      expect(mediaKindFilterOf('gif')).assertEqual('searchMessagesFilterPhotoAndVideo');
      expect(normalizeMediaKind('gif')).assertEqual(MEDIA_KIND_ALL);
      expect(normalizeMediaKind('')).assertEqual(MEDIA_KIND_ALL);
    });

    it('三档都在列表里且顺序固定（分段控件按它渲染）', 0, () => {
      expect(MEDIA_KINDS.length).assertEqual(3);
      expect(MEDIA_KINDS[0]).assertEqual(MEDIA_KIND_ALL);
      expect(MEDIA_KINDS[1]).assertEqual(MEDIA_KIND_PHOTO);
      expect(MEDIA_KINDS[2]).assertEqual(MEDIA_KIND_VIDEO);
      for (const k of MEDIA_KINDS) {
        expect(normalizeMediaKind(k)).assertEqual(k);
      }
    });
  });
}
