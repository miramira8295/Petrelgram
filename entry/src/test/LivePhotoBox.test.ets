import { describe, expect, it } from '@ohos/hypium';
import {
  LIVE_BOX_MAGIC, LIVE_BOX_OVERHEAD, LiveStillSlice,
  buildLiveStillBox, findLiveStillBox
} from '../main/ets/util/livePhotoBox';

// 实况照片把全尺寸静图夹带在 mp4 尾部的 free 盒里（issue #193 的后半：动态部分
// 只有 1080p，静图那一半在协议里没有位置可放）。这一组钉住编解码的自洽与抗误判。

function bytes(values: number[]): Uint8Array {
  const out: Uint8Array = new Uint8Array(values.length);
  for (let i = 0; i < values.length; i++) { out[i] = values[i]; }
  return out;
}

function concat(a: Uint8Array, b: Uint8Array): Uint8Array {
  const out: Uint8Array = new Uint8Array(a.length + b.length);
  out.set(a, 0);
  out.set(b, a.length);
  return out;
}

// 一段假装是 mp4 的前缀。内容无所谓，只要不含魔数。
function fakeMp4(): Uint8Array {
  return bytes([0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, 1, 2, 3, 4, 5, 6, 7, 8]);
}

export default function livePhotoBoxTest() {
  describe('livePhotoBox', () => {

    it('往返：写进去再找回来，字节完全一致', 0, (): void => {
      const jpeg: Uint8Array = bytes([0xFF, 0xD8, 0xFF, 0xE0, 42, 7, 0xFF, 0xD9]);
      const file: Uint8Array = concat(fakeMp4(), buildLiveStillBox(jpeg));
      const found: LiveStillSlice | null = findLiveStillBox(file);
      expect(found !== null).assertTrue();
      const slice: LiveStillSlice = found as LiveStillSlice;
      expect(slice.length).assertEqual(jpeg.length);
      for (let i = 0; i < jpeg.length; i++) {
        expect(file[slice.start + i]).assertEqual(jpeg[i]);
      }
    });

    it('盒长 = 固定开销 + jpeg 长度', 0, (): void => {
      const jpeg: Uint8Array = bytes([1, 2, 3, 4, 5]);
      const box: Uint8Array = buildLiveStillBox(jpeg);
      expect(box.length).assertEqual(LIVE_BOX_OVERHEAD + jpeg.length);
      // 盒头前四字节是大端盒长
      const declared: number = (box[0] << 24) + (box[1] << 16) + (box[2] << 8) + box[3];
      expect(declared).assertEqual(box.length);
    });

    it('盒类型是 free —— 合规解析器会跳过，别家播放不受影响', 0, (): void => {
      const box: Uint8Array = buildLiveStillBox(bytes([9]));
      expect(String.fromCharCode(box[4], box[5], box[6], box[7])).assertEqual('free');
    });

    it('空 jpeg 返回空盒，调用方据此不追加', 0, (): void => {
      expect(buildLiveStillBox(new Uint8Array(0)).length).assertEqual(0);
    });

    it('没有夹带时返回 null', 0, (): void => {
      expect(findLiveStillBox(fakeMp4()) === null).assertTrue();
      expect(findLiveStillBox(new Uint8Array(0)) === null).assertTrue();
    });

    it('视频数据里恰好出现魔数也不误判——盒头对不上就跳过', 0, (): void => {
      // 裸魔数，前面没有合法的 free 盒头
      const decoy: Uint8Array = new Uint8Array(LIVE_BOX_MAGIC.length + 12);
      for (let i = 0; i < LIVE_BOX_MAGIC.length; i++) {
        decoy[i + 4] = LIVE_BOX_MAGIC.charCodeAt(i);
      }
      expect(findLiveStillBox(decoy) === null).assertTrue();
    });

    it('盒长与 jpeg 长度对不上就跳过（截断/损坏的文件）', 0, (): void => {
      const jpeg: Uint8Array = bytes([1, 2, 3, 4]);
      const box: Uint8Array = buildLiveStillBox(jpeg);
      // 把声明的盒长改坏
      box[3] = (box[3] + 3) & 0xff;
      expect(findLiveStillBox(concat(fakeMp4(), box)) === null).assertTrue();
    });

    it('尾部被截掉一半时不越界读', 0, (): void => {
      const jpeg: Uint8Array = bytes([1, 2, 3, 4, 5, 6, 7, 8]);
      const full: Uint8Array = concat(fakeMp4(), buildLiveStillBox(jpeg));
      const truncated: Uint8Array = full.slice(0, full.length - 4);
      expect(findLiveStillBox(truncated) === null).assertTrue();
    });

    it('后面还跟着别的字节时仍能找到（倒着扫的意义）', 0, (): void => {
      const jpeg: Uint8Array = bytes([0xAA, 0xBB]);
      const file: Uint8Array =
        concat(concat(fakeMp4(), buildLiveStillBox(jpeg)), bytes([0, 0, 0, 8, 1, 2, 3, 4]));
      const found: LiveStillSlice | null = findLiveStillBox(file);
      expect(found !== null).assertTrue();
      expect((found as LiveStillSlice).length).assertEqual(2);
    });
  });
}
