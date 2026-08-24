import { describe, it, expect } from '@ohos/hypium';
import {
  cacheDestPath, fileExtension, fileNameFromUri, isAnimationPath, isVideoPath
} from '../main/ets/util/mediaPick';

export default function mediaPickTest() {
  describe('mediaPick', () => {
    it('extension is lowercased and dot-free', 0, () => {
      expect(fileExtension('/a/b/clip.MP4')).assertEqual('mp4');
      expect(fileExtension('clip.mov')).assertEqual('mov');
      expect(fileExtension('/a/b/photo.jpeg')).assertEqual('jpeg');
    });

    it('extension handles names without one', 0, () => {
      expect(fileExtension('/a/b/README')).assertEqual('');
      expect(fileExtension('/a/b/trailing.')).assertEqual('');
      expect(fileExtension('')).assertEqual('');
    });

    it('extension ignores dots in directories', 0, () => {
      expect(fileExtension('/a.b/c.d/plain')).assertEqual('');
      expect(fileExtension('/a.b/c.d/clip.mkv')).assertEqual('mkv');
    });

    it('a leading dot is a hidden file, not an extension', 0, () => {
      expect(fileExtension('/a/b/.gitignore')).assertEqual('');
    });

    it('recognises every container the send path accepts', 0, () => {
      expect(isVideoPath('/x/a.mp4')).assertTrue();
      expect(isVideoPath('/x/a.mov')).assertTrue();
      expect(isVideoPath('/x/a.mkv')).assertTrue();
      expect(isVideoPath('/x/a.avi')).assertTrue();
      expect(isVideoPath('/x/a.webm')).assertTrue();
    });

    it('is case-insensitive', 0, () => {
      expect(isVideoPath('/x/A.MKV')).assertTrue();
      expect(isVideoPath('/x/A.MoV')).assertTrue();
    });

    // issue #105：从图库选的 GIF 原来按 inputMessagePhoto 发出去，服务器存成
    // 静态图，动画帧就此丢失——自己看不动、官版看也不动且没有 GIF 角标。
    it('GIF 认成 animation，不能当照片发', 0, () => {
      expect(isAnimationPath('/x/a.gif')).assertTrue();
      expect(isAnimationPath('/x/A.GIF')).assertTrue();
      // 它不是视频：两条规则各管各的，别让 GIF 掉进 inputMessageVideo。
      expect(isVideoPath('/x/a.gif')).assertFalse();
    });

    it('静态图与视频都不算 animation', 0, () => {
      // webp/apng 同一个扩展名下静态的居多，误判会把普通贴图变成 GIF。
      expect(isAnimationPath('/x/a.jpg')).assertFalse();
      expect(isAnimationPath('/x/a.png')).assertFalse();
      expect(isAnimationPath('/x/a.webp')).assertFalse();
      expect(isAnimationPath('/x/a.mp4')).assertFalse();
      expect(isAnimationPath('/x/noext')).assertFalse();
    });

    it('rejects stills and documents', 0, () => {
      expect(isVideoPath('/x/a.jpg')).assertFalse();
      expect(isVideoPath('/x/a.png')).assertFalse();
      expect(isVideoPath('/x/a.pdf')).assertFalse();
      expect(isVideoPath('/x/a')).assertFalse();
    });

    it('decodes a percent-encoded file name', 0, () => {
      expect(fileNameFromUri('file://docs/my%20clip.mp4')).assertEqual('my clip.mp4');
      expect(fileNameFromUri('file://docs/%E8%A7%86%E9%A2%91.mp4')).assertEqual('视频.mp4');
    });

    it('falls back to the raw segment on a malformed escape', 0, () => {
      // A stray '%' makes decodeURIComponent throw; a pick must not fail there.
      expect(fileNameFromUri('file://docs/100%.mp4')).assertEqual('100%.mp4');
    });

    it('cache destination carries both timestamp and sequence', 0, () => {
      expect(cacheDestPath('/cache', 'file://d/a.mp4', 3, 1700))
        .assertEqual('/cache/send_1700_3_a.mp4');
    });

    it('same-millisecond picks do not collide', 0, () => {
      const first = cacheDestPath('/cache', 'file://d/a.jpg', 1, 1700);
      const second = cacheDestPath('/cache', 'file://d/a.jpg', 2, 1700);
      expect(first === second).assertFalse();
    });
  });
}
