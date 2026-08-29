import { describe, expect, it } from '@ohos/hypium';
import { chromeSitsOnLight } from '../main/ets/util/chatChrome';

// 深色下的两种玻璃填充，取自 resources/dark/element/color.json。
const TINT_MATERIAL: string = '#402F3F52';   // 材质档，25% —— 真机上材质不渲染时唯一的一层
const TINT_DOCK: string = '#8C2F3F52';       // 降级档，55%

export default function chatChromeTest() {
  describe('chromeSitsOnLight', () => {
    // 用户报的那一例：深色模式 + 浅紫壁纸，输入栏其实坐在亮底上。
    it('light_wallpaper_puts_chrome_on_light', 0, (): void => {
      expect(chromeSitsOnLight(['#D8D0EA', '#E4D8F0'], TINT_MATERIAL, false)).assertTrue();
      expect(chromeSitsOnLight(['#D8D0EA', '#E4D8F0'], TINT_DOCK, false)).assertTrue();
    });

    // 默认深色壁纸 chat_bg=#0E1621：本来就和主题一致，不该翻。
    it('dark_wallpaper_keeps_chrome_on_dark', 0, (): void => {
      expect(chromeSitsOnLight(['#0E1621'], TINT_MATERIAL, false)).assertFalse();
      expect(chromeSitsOnLight(['#17212B', '#232E3C'], TINT_MATERIAL, false)).assertFalse();
    });

    // 玻璃越厚，越能把亮壁纸压下去——25% 压不住，55% 也压不住，这正是
    // "加厚救不了、只能翻前景"的依据。
    it('thicker_glass_still_cannot_save_a_white_wallpaper', 0, (): void => {
      expect(chromeSitsOnLight(['#FFFFFF'], TINT_MATERIAL, false)).assertTrue();
      expect(chromeSitsOnLight(['#FFFFFF'], TINT_DOCK, false)).assertTrue();
    });

    // 图片壁纸取不到颜色 → 退回按主题判（旧行为）。
    it('image_wallpaper_falls_back_to_theme', 0, (): void => {
      expect(chromeSitsOnLight([], TINT_MATERIAL, false)).assertFalse();
      expect(chromeSitsOnLight([], TINT_MATERIAL, true)).assertTrue();
    });

    // 脏色值不该让 chrome 变色：整条都无效时走 fallback，部分无效时按有效的算。
    it('bad_colors_do_not_flip_chrome', 0, (): void => {
      expect(chromeSitsOnLight(['', 'nope'], TINT_MATERIAL, false)).assertFalse();
      expect(chromeSitsOnLight(['zzz', '#FFFFFF'], TINT_MATERIAL, false)).assertTrue();
    });

    // 阈值按"白色前景还够不够 4.5:1"取（L≈0.183），不是常见的 0.5。
    // #767676 的 L≈0.20，白字在其上只有 4.1:1 —— 必须判成亮底。
    it('threshold_follows_white_text_legibility_not_midpoint', 0, (): void => {
      expect(chromeSitsOnLight(['#767676'], '#00000000', false)).assertTrue();
      expect(chromeSitsOnLight(['#5A5A5A'], '#00000000', false)).assertFalse();
    });
  });
}
