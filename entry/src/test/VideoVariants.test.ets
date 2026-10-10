import { describe, expect, it } from '@ohos/hypium';
import {
  QUALITY_AUTO, VideoVariant, pickVideoVariant, playableVariants, variantLabelHeight, variantsOwnFile, pickInlineVariant
} from '../main/ets/util/videoVariants';

function v(fileId: number, w: number, h: number, size: number, codec: string): VideoVariant {
  return { fileId: fileId, width: w, height: h, size: size, codec: codec };
}

const ORIGINAL: VideoVariant = v(1, 1920, 1080, 50_000_000, '');

export default function videoVariantsTest() {
  describe('videoVariants', () => {
    it('清晰度按短边算（竖屏 1080x1920 也是 1080p）', 0, (): void => {
      expect(variantLabelHeight(v(1, 1080, 1920, 1, 'h264'))).assertEqual(1080);
      expect(variantLabelHeight(v(1, 1280, 720, 1, 'h264'))).assertEqual(720);
    });

    it('可选档：原片打头，去掉 AV1，同档留文件最小的，按清晰度从高到低', 0, (): void => {
      const alts: VideoVariant[] = [
        v(2, 1280, 720, 9_000_000, 'h264'), v(3, 1280, 720, 6_000_000, 'h265'),
        v(4, 854, 480, 3_000_000, 'av1'), v(5, 640, 360, 2_000_000, 'h264')
      ];
      const list: VideoVariant[] = playableVariants(ORIGINAL, alts);
      expect(list.map((x: VideoVariant): number => x.fileId).join(',')).assertEqual('1,3,5');
    });

    it('与原片同档的不重复列出（原片总在）', 0, (): void => {
      const list: VideoVariant[] = playableVariants(ORIGINAL, [v(2, 1920, 1080, 30_000_000, 'h264')]);
      expect(list.length).assertEqual(1);
      expect(list[0].fileId).assertEqual(1);
    });

    it('自动：Wi-Fi 用原片，流量选不超过 720p 的最高一档', 0, (): void => {
      const list: VideoVariant[] = playableVariants(ORIGINAL,
        [v(2, 1280, 720, 9_000_000, 'h264'), v(5, 640, 360, 2_000_000, 'h264')]);
      expect(pickVideoVariant(list, QUALITY_AUTO, false).fileId).assertEqual(1);
      expect(pickVideoVariant(list, QUALITY_AUTO, true).fileId).assertEqual(2);
      // 流量下没有 ≤720 的档：退回最低的那档
      expect(pickVideoVariant([ORIGINAL], QUALITY_AUTO, true).fileId).assertEqual(1);
    });

    it('手动选档：有就用；没有就取不高于它的最高一档，再没有取最低', 0, (): void => {
      const list: VideoVariant[] = playableVariants(ORIGINAL,
        [v(2, 1280, 720, 9_000_000, 'h264'), v(5, 640, 360, 2_000_000, 'h264')]);
      expect(pickVideoVariant(list, 360, false).fileId).assertEqual(5);
      expect(pickVideoVariant(list, 480, false).fileId).assertEqual(5);
      expect(pickVideoVariant(list, 240, false).fileId).assertEqual(5);
      expect(pickVideoVariant(list, 1080, true).fileId).assertEqual(1);
    });

    // 列表的提前下载（自动播放、后台缓存）下的都是原片：原片已经整份在本地时，
    // 「自动」不该再去下别的档——白花流量，离线时更是根本播不了。
    it('原片已在本地：自动档用原片，手动档照选', 0, (): void => {
      const list: VideoVariant[] = playableVariants(ORIGINAL,
        [v(2, 1280, 720, 9_000_000, 'h264'), v(5, 640, 360, 2_000_000, 'h264')]);
      expect(pickVideoVariant(list, QUALITY_AUTO, true, true).fileId).assertEqual(1);
      expect(pickVideoVariant(list, 360, true, true).fileId).assertEqual(5);
      expect(pickVideoVariant(list, QUALITY_AUTO, true, false).fileId).assertEqual(2);
    });

    it('这个文件是不是这条视频的某一档（原片或任一清晰度）', 0, (): void => {
      const alts: VideoVariant[] = [v(2, 1280, 720, 9_000_000, 'h264')];
      expect(variantsOwnFile(1, alts, 1)).assertTrue();
      expect(variantsOwnFile(1, alts, 2)).assertTrue();
      expect(variantsOwnFile(1, alts, 3)).assertFalse();
      expect(variantsOwnFile(1, alts, 0)).assertFalse();
    });

    // 会话里的自动播放小窗：取不低于 480p 的最低一档（小窗看不出更高的清晰度，省下载、省解码）。
    it('小窗：不低于 480p 的最低一档；没有就取低于 480p 的最高一档；原片在本地用原片', 0, (): void => {
      const list: VideoVariant[] = playableVariants(ORIGINAL, [
        v(2, 1280, 720, 9_000_000, 'h264'), v(3, 854, 480, 4_000_000, 'h264'), v(5, 640, 360, 2_000_000, 'h264')
      ]);
      expect(pickInlineVariant(list, false).fileId).assertEqual(3);
      expect(pickInlineVariant(list, true).fileId).assertEqual(1);
      const noLow: VideoVariant[] = playableVariants(ORIGINAL, [v(2, 1280, 720, 9_000_000, 'h264')]);
      expect(pickInlineVariant(noLow, false).fileId).assertEqual(2);
      const onlyTiny: VideoVariant[] = playableVariants(v(1, 400, 300, 1, ''), [v(5, 320, 240, 1, 'h264')]);
      expect(pickInlineVariant(onlyTiny, false).fileId).assertEqual(1);
    });
  });
}
