import { describe, expect, it } from '@ohos/hypium';
import {
  MEDIA_WINDOW_PAD, MediaWindow, VisibleRange,
  mediaWindowRange, visibleRangeOrFallback
} from '../main/ets/util/visibleWindow';

// 第 i 行的行首 id 是 100+i，最后一个成员 id 是 100+i+50（模拟相册行更宽）。
const headAt: (i: number) => number = (i: number): number => 100 + i;
const lastAt: (i: number) => number = (i: number): number => 150 + i;

export default function visibleWindowTest() {
  describe('visibleWindow', () => {
    it('有滚动事件时原样返回', 0, () => {
      const r: VisibleRange = visibleRangeOrFallback(5, 12, 40, 8);
      expect(r.start).assertEqual(5);
      expect(r.end).assertEqual(12);
    });

    it('首帧之前用末尾一屏兜底', 0, () => {
      // 聊天默认停在底部，猜末尾比猜开头准。
      const r: VisibleRange = visibleRangeOrFallback(-1, -1, 40, 8);
      expect(r.end).assertEqual(39);
      expect(r.start).assertEqual(31);
    });

    it('end 小于 start 同样算无效', 0, () => {
      // onScrollIndex 还没给过一对有意义的值。
      const r: VisibleRange = visibleRangeOrFallback(10, 3, 40, 8);
      expect(r.start).assertEqual(31);
      expect(r.end).assertEqual(39);
    });

    it('行数比缓存数还少时不出负下标', 0, () => {
      const r: VisibleRange = visibleRangeOrFallback(-1, -1, 3, 8);
      expect(r.start).assertEqual(0);
      expect(r.end).assertEqual(2);
    });

    it('空列表兜底不出负数', 0, () => {
      const r: VisibleRange = visibleRangeOrFallback(-1, -1, 0, 8);
      expect(r.start).assertEqual(0);
      expect(r.end).assertEqual(0);
    });

    it('媒体窗口向两侧各外扩 3 行', 0, () => {
      const w: MediaWindow = mediaWindowRange(10, 20, 100, headAt, lastAt);
      expect(w.valid).assertTrue();
      expect(w.fromId).assertEqual(headAt(10 - MEDIA_WINDOW_PAD));
      // 上界取末行的**最后一个成员**：相册一整行多条，取行首会把更新的那几条
      // 漏在窗外。
      expect(w.toId).assertEqual(lastAt(20 + MEDIA_WINDOW_PAD));
    });

    it('两端都夹住，不越界', 0, () => {
      const w: MediaWindow = mediaWindowRange(1, 98, 100, headAt, lastAt);
      expect(w.fromId).assertEqual(headAt(0));
      expect(w.toId).assertEqual(lastAt(99));
    });

    it('空列表无效', 0, () => {
      expect(mediaWindowRange(0, 0, 0, headAt, lastAt).valid).assertFalse();
    });

    it('区间反了就判无效，不去索引', 0, () => {
      // startIdx 远大于 endIdx：外扩后 from 仍然 > to。
      expect(mediaWindowRange(50, 2, 100, headAt, lastAt).valid).assertFalse();
    });

    it('单行列表也能算出窗口', 0, () => {
      const w: MediaWindow = mediaWindowRange(0, 0, 1, headAt, lastAt);
      expect(w.valid).assertTrue();
      expect(w.fromId).assertEqual(headAt(0));
      expect(w.toId).assertEqual(lastAt(0));
    });
  });
}
