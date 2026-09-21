import { describe, it, expect } from '@ohos/hypium';
import { pixelCacheKey } from '../main/ets/util/pixelCacheKey';

export default function pixelCacheKeyTest() {
  describe('PixelCacheKey', () => {
    it('同一张图的两种像素格式是两个键', 0, () => {
      const rgba: string = pixelCacheKey('/a/b.jpg', 320, 480, false);
      const rgb565: string = pixelCacheKey('/a/b.jpg', 320, 480, true);
      expect(rgba === rgb565).assertFalse();
    });

    // 这条是本次改动真正的风险点：漏了它，相册解出来的 565 位图会被喂给单张大图
    // 或头像那条路（它们要 8888），表现为"先看过相册之后图片掉色阶"。
    it('默认档（8888）的键不带格式后缀，565 才带', 0, () => {
      expect(pixelCacheKey('/a/b.jpg', 320, 480, false)).assertEqual('/a/b.jpg@320x480');
      expect(pixelCacheKey('/a/b.jpg', 320, 480, true)).assertEqual('/a/b.jpg@320x480#565');
    });

    it('尺寸取整：浮点尾数不该分裂成两份解码', 0, () => {
      expect(pixelCacheKey('/a/b.jpg', 320.4, 480.2, false))
        .assertEqual(pixelCacheKey('/a/b.jpg', 320, 480, false));
      expect(pixelCacheKey('/a/b.jpg', 319.6, 479.5, true))
        .assertEqual(pixelCacheKey('/a/b.jpg', 320, 480, true));
    });

    it('路径、宽、高任一不同都是不同的键', 0, () => {
      const base: string = pixelCacheKey('/a/b.jpg', 320, 480, false);
      expect(pixelCacheKey('/a/c.jpg', 320, 480, false) === base).assertFalse();
      expect(pixelCacheKey('/a/b.jpg', 321, 480, false) === base).assertFalse();
      expect(pixelCacheKey('/a/b.jpg', 320, 481, false) === base).assertFalse();
    });

    // 尺寸段与格式段之间不能有歧义：一个 320x480#565 不能和某个宽高恰好拼出
    // 同样字符串的请求撞上。分隔符固定为 '@' 与 '#'，这里钉住形状。
    it('键的形状固定为 path@WxH[#565]', 0, () => {
      const key: string = pixelCacheKey('/x/y z.jpg', 12, 34, true);
      expect(key).assertEqual('/x/y z.jpg@12x34#565');
      expect(key.indexOf('@') > 0).assertTrue();
      expect(key.endsWith('#565')).assertTrue();
    });

    it('空路径照样产生确定的键（调用方自己拦空路径，这里不抛）', 0, () => {
      expect(pixelCacheKey('', 0, 0, false)).assertEqual('@0x0');
    });
  });
}
