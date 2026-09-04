import { describe, expect, it } from '@ohos/hypium';
import { HDR_BADGE_TEXT, isHdrTrackValue } from '../main/ets/util/hdrBadge';

export default function hdrBadgeTest() {
  describe('hdrBadge', () => {
    it('AV_HDR_TYPE_NONE(0) 不亮', 0, () => {
      expect(isHdrTrackValue('0')).assertFalse();
    });

    it('AV_HDR_TYPE_VIVID(1) 亮', 0, () => {
      expect(isHdrTrackValue('1')).assertTrue();
    });

    // 轨道里没有这个键时取到空串——不确定就不标。
    it('取不到值时不亮', 0, () => {
      expect(isHdrTrackValue('')).assertFalse();
      expect(isHdrTrackValue('   ')).assertFalse();
    });

    it('字符串形式的 none 不亮，vivid 亮', 0, () => {
      expect(isHdrTrackValue('none')).assertFalse();
      expect(isHdrTrackValue('NONE')).assertFalse();
      expect(isHdrTrackValue('vivid')).assertTrue();
    });

    it('角标文案是短的那种，不占控制条', 0, () => {
      expect(HDR_BADGE_TEXT).assertEqual('HDR');
    });
  });
}
