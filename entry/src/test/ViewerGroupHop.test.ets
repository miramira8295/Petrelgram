import { describe, expect, it } from '@ohos/hypium';
import { hopDirection, hopProgress, nextMediaGroupIndex } from '../main/ets/util/viewerGroupHop';

export default function viewerGroupHopTest() {
  describe('viewerGroupHop', () => {
    // 符号跟 Swiper 的 currentOffset 走：内容往左拖（露出下一页）是负数。
    it('停在尾页继续往左拖 = 去下一组', 0, () => {
      expect(hopDirection(2, 3, -40)).assertEqual(1);
    });

    it('停在首页继续往右拖 = 去上一组', 0, () => {
      expect(hopDirection(0, 3, 40)).assertEqual(-1);
    });

    // 拖向组内还存在的那一侧，是正常翻页，不是越界。
    it('中间页怎么拖都不算越界', 0, () => {
      expect(hopDirection(1, 3, -40)).assertEqual(0);
      expect(hopDirection(1, 3, 40)).assertEqual(0);
    });

    it('尾页往右拖 / 首页往左拖 = 正常翻页，不算越界', 0, () => {
      expect(hopDirection(2, 3, 40)).assertEqual(0);
      expect(hopDirection(0, 3, -40)).assertEqual(0);
    });

    // 单图消息没有组内翻页，两侧都该能拉去邻组——这是故意的。
    it('只有一页时两侧都算越界', 0, () => {
      expect(hopDirection(0, 1, -40)).assertEqual(1);
      expect(hopDirection(0, 1, 40)).assertEqual(-1);
    });

    it('空列表不越界', 0, () => {
      expect(hopDirection(0, 0, -40)).assertEqual(0);
    });

    it('进度按阈值夹到 0..1', 0, () => {
      expect(hopProgress(0, 100)).assertEqual(0);
      expect(hopProgress(-50, 100)).assertEqual(0.5);
      expect(hopProgress(-100, 100)).assertEqual(1);
      expect(hopProgress(-400, 100)).assertEqual(1);
    });

    // threshold 为 0 时不能除出 Infinity，否则气泡一碰就满格。
    it('阈值无效时进度为 0', 0, () => {
      expect(hopProgress(-50, 0)).assertEqual(0);
      expect(hopProgress(-50, -10)).assertEqual(0);
    });

    // 中间隔着几十条文字消息，不该让"看下一组媒体"这个动作失效。
    it('往后找下一组媒体：跳过非媒体行', 0, () => {
      const media: boolean[] = [true, false, false, true, false, true];
      const isMedia = (i: number): boolean => media[i];
      expect(nextMediaGroupIndex(6, 0, 1, isMedia)).assertEqual(3);
      expect(nextMediaGroupIndex(6, 3, 1, isMedia)).assertEqual(5);
    });

    it('往前找上一组媒体：跳过非媒体行', 0, () => {
      const media: boolean[] = [true, false, false, true, false, true];
      const isMedia = (i: number): boolean => media[i];
      expect(nextMediaGroupIndex(6, 5, -1, isMedia)).assertEqual(3);
      expect(nextMediaGroupIndex(6, 3, -1, isMedia)).assertEqual(0);
    });

    it('没有下一组时返回 -1', 0, () => {
      const media: boolean[] = [true, false, false];
      const isMedia = (i: number): boolean => media[i];
      expect(nextMediaGroupIndex(3, 0, -1, isMedia)).assertEqual(-1);
      expect(nextMediaGroupIndex(3, 0, 1, isMedia)).assertEqual(-1);
    });

    it('方向为 0 或起点越界时返回 -1', 0, () => {
      const isMedia = (_i: number): boolean => true;
      expect(nextMediaGroupIndex(3, 1, 0, isMedia)).assertEqual(-1);
      expect(nextMediaGroupIndex(3, -1, 1, isMedia)).assertEqual(-1);
      expect(nextMediaGroupIndex(3, 3, 1, isMedia)).assertEqual(-1);
    });
  });
}
