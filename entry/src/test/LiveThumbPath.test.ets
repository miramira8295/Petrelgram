import { describe, expect, it } from '@ohos/hypium';
import { liveThumbPath } from '../main/ets/util/liveThumbPath';

export default function liveThumbPathTest() {
  describe('liveThumbPath', () => {
    it('fileId 为 0 时新路径替换旧消息的图片', 0, (): void => {
      expect(liveThumbPath(0, '', '/old.jpg', '/new.jpg', true)).assertEqual('/new.jpg');
      expect(liveThumbPath(0, '', '/old.jpg', '', true)).assertEqual('');
    });

    it('通道路径对可下载文件具有最高优先级', 0, (): void => {
      expect(liveThumbPath(42, '/landed.jpg', '/old.jpg', '/seed.jpg', true))
        .assertEqual('/landed.jpg');
    });

    it('同一文件跨复用池时保留已有图片', 0, (): void => {
      expect(liveThumbPath(42, '', '/decoded.jpg', '', true)).assertEqual('/decoded.jpg');
    });

    it('换文件且通道未落地时不保留上一张图', 0, (): void => {
      expect(liveThumbPath(99, '', '/old.jpg', '', false)).assertEqual('');
      expect(liveThumbPath(99, '', '/old.jpg', '/new-seed.jpg', false))
        .assertEqual('/new-seed.jpg');
    });
  });
}
