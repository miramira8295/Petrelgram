import { describe, expect, it } from '@ohos/hypium';
import {
  ReplyThumbInput, replyDiceLayers, replyThumbIsSticker, replyThumbOf, replyThumbSrc
} from '../main/ets/util/replyThumb';

function input(contentType: string, photoPath: string, locked: boolean): ReplyThumbInput {
  return { contentType: contentType, photoPath: photoPath, paidMediaLocked: locked };
}

export default function replyThumbTest() {
  describe('replyThumb', () => {
    it('贴纸、图片、视频封面都从同一个 photoPath 取', 0, () => {
      expect(replyThumbOf(input('sticker', '/data/s.webp', false))).assertEqual('/data/s.webp');
      expect(replyThumbOf(input('photo', '/data/p.jpg', false))).assertEqual('/data/p.jpg');
      expect(replyThumbOf(input('video', '/data/poster.jpg', false))).assertEqual('/data/poster.jpg');
    });

    it('没有位图就没有缩略图（文件还没下完 / 纯文本）', 0, () => {
      expect(replyThumbOf(input('photo', '', false))).assertEqual('');
      expect(replyThumbOf(input('text', '', false))).assertEqual('');
      expect(replyThumbOf(input('voice', '', false))).assertEqual('');
    });

    it('只有空白字符不算路径', 0, () => {
      expect(replyThumbOf(input('photo', '   ', false))).assertEqual('');
    });

    // 没解锁的付费媒体，封面就是要花钱看的东西，引用块不能白送。
    it('付费媒体没解锁一律不给图，解锁了才给', 0, () => {
      expect(replyThumbOf(input('paidMedia', '/data/paid.jpg', true))).assertEqual('');
      expect(replyThumbOf(input('paidMedia', '/data/paid.jpg', false))).assertEqual('/data/paid.jpg');
    });

    // paidMediaLocked 只对 paidMedia 有意义，别的类型不受它影响。
    it('别的类型不看 paidMediaLocked', 0, () => {
      expect(replyThumbOf(input('photo', '/data/p.jpg', true))).assertEqual('/data/p.jpg');
    });

    it('本地绝对路径补 file://，已是 URL 的不动', 0, () => {
      expect(replyThumbSrc('/data/x.jpg')).assertEqual('file:///data/x.jpg');
      expect(replyThumbSrc('https://a/b.png')).assertEqual('https://a/b.png');
      expect(replyThumbSrc('')).assertEqual('');
    });

    it('只有贴纸走 Contain，其余走 Cover', 0, () => {
      expect(replyThumbIsSticker('sticker')).assertTrue();
      expect(replyThumbIsSticker('photo')).assertFalse();
      expect(replyThumbIsSticker('video')).assertFalse();
    });
  });
  // 引用骰子/老虎机显示结尾帧（2026-10-10）：缩略图是动画第一帧（空转轮），看不出结果。
  describe('replyDiceLayers', () => {
    it('老虎机 5 层都在本地：给 5 层', 0, (): void => {
      const layers: string[] = ['/a', '/b', '/c', '/d', '/e'];
      expect(replyDiceLayers('dice', '/x', layers).join(',')).assertEqual('/a,/b,/c,/d,/e');
    });
    it('层没下全：退回单张结果动画；也没有就空', 0, (): void => {
      expect(replyDiceLayers('dice', '/x', ['/a', '', '/c', '/d', '/e']).join(',')).assertEqual('/x');
      expect(replyDiceLayers('dice', '/x', []).join(',')).assertEqual('/x');
      expect(replyDiceLayers('dice', '', ['/a']).length).assertEqual(0);
    });
    it('不是骰子一律空', 0, (): void => {
      expect(replyDiceLayers('sticker', '/x', []).length).assertEqual(0);
    });
  });
}
