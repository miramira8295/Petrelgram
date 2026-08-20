import { describe, expect, it } from '@ohos/hypium';
import {
  PENDING_MEDIA_MAX, PendingMediaAppend, PendingMediaCounts, PendingMediaItem,
  appendPendingMedia, clearPendingMedia, hasPendingMedia, pendingMediaCanSend,
  movePendingMedia, pendingMediaCounts, removePendingMedia
} from '../main/ets/util/pendingMedia';

function photo(name: string): PendingMediaItem {
  return { path: `/cache/${name}.jpg`, isVideo: false };
}

function video(name: string): PendingMediaItem {
  return { path: `/cache/${name}.mp4`, isVideo: true };
}

function paths(items: PendingMediaItem[]): string {
  return items.map((item: PendingMediaItem): string => item.path).join(',');
}

function many(count: number): PendingMediaItem[] {
  const out: PendingMediaItem[] = [];
  for (let i = 0; i < count; i++) {
    out.push(photo(`p${i}`));
  }
  return out;
}

export default function pendingMediaTest() {
  describe('pendingMedia', () => {
    it('追加接在后面，保持选择顺序', 0, () => {
      const a: PendingMediaAppend = appendPendingMedia([photo('a')], [photo('b'), video('c')]);
      expect(paths(a.items)).assertEqual('/cache/a.jpg,/cache/b.jpg,/cache/c.mp4');
      expect(a.dropped).assertEqual(0);
    });

    it('封顶九张，超出的部分报告 dropped 而不是悄悄丢掉', 0, () => {
      const a: PendingMediaAppend = appendPendingMedia(many(7), many(4));
      expect(a.items.length).assertEqual(PENDING_MEDIA_MAX);
      expect(a.dropped).assertEqual(2);
    });

    it('已经满了再追加：一张都不进，全部计入 dropped', 0, () => {
      const a: PendingMediaAppend = appendPendingMedia(many(PENDING_MEDIA_MAX), [photo('x')]);
      expect(a.items.length).assertEqual(PENDING_MEDIA_MAX);
      expect(a.dropped).assertEqual(1);
    });

    it('不修改传入的数组', 0, () => {
      const src: PendingMediaItem[] = [photo('a')];
      appendPendingMedia(src, [photo('b')]);
      removePendingMedia(src, 0);
      expect(src.length).assertEqual(1);
    });

    it('按下标移除；越界原样返回', 0, () => {
      const three: PendingMediaItem[] = [photo('a'), photo('b'), photo('c')];
      expect(paths(removePendingMedia(three, 1))).assertEqual('/cache/a.jpg,/cache/c.jpg');
      expect(removePendingMedia(three, -1).length).assertEqual(3);
      expect(removePendingMedia(three, 3).length).assertEqual(3);
    });

    it('图片和视频分开数（中文量词不同，不能合成一句）', 0, () => {
      const c: PendingMediaCounts = pendingMediaCounts([photo('a'), video('b'), video('c')]);
      expect(c.photos).assertEqual(1);
      expect(c.videos).assertEqual(2);
    });

    it('清空与判空', 0, () => {
      expect(clearPendingMedia().length).assertEqual(0);
      expect(hasPendingMedia([])).assertFalse();
      expect(hasPendingMedia([photo('a')])).assertTrue();
    });

    // 有媒体时正文可以为空——媒体本身就是内容，说明是可选的。
    it('发送键的判据：有媒体或有非空正文', 0, () => {
      expect(pendingMediaCanSend([], '')).assertFalse();
      expect(pendingMediaCanSend([], '   ')).assertFalse();
      expect(pendingMediaCanSend([], 'hi')).assertTrue();
      expect(pendingMediaCanSend([photo('a')], '')).assertTrue();
    });

    // 发送顺序 = 相册里的排列顺序，所以换序不是装饰。
    it('拖拽换序：先摘再插，中间的项依次让位', 0, () => {
      const four: PendingMediaItem[] = [photo('a'), photo('b'), photo('c'), photo('d')];
      // 头挪到尾
      expect(paths(movePendingMedia(four, 0, 3)))
        .assertEqual('/cache/b.jpg,/cache/c.jpg,/cache/d.jpg,/cache/a.jpg');
      // 尾挪到头
      expect(paths(movePendingMedia(four, 3, 0)))
        .assertEqual('/cache/d.jpg,/cache/a.jpg,/cache/b.jpg,/cache/c.jpg');
      // 相邻互换
      expect(paths(movePendingMedia(four, 1, 2)))
        .assertEqual('/cache/a.jpg,/cache/c.jpg,/cache/b.jpg,/cache/d.jpg');
    });

    it('换序：越界或原地不动时原样返回，且不修改入参', 0, () => {
      const three: PendingMediaItem[] = [photo('a'), photo('b'), photo('c')];
      expect(movePendingMedia(three, 1, 1).length).assertEqual(3);
      expect(movePendingMedia(three, -1, 1).length).assertEqual(3);
      expect(movePendingMedia(three, 0, 3).length).assertEqual(3);
      movePendingMedia(three, 0, 2);
      expect(paths(three)).assertEqual('/cache/a.jpg,/cache/b.jpg,/cache/c.jpg');
    });
  });
}
