import { describe, expect, it } from '@ohos/hypium';
import { chromeDarkMaskOf, chromeIconColorOf, chromeOnLightBgOf, chromeSitsOnLight,
  chromeTextColorOf } from '../main/ets/util/chatChrome';
import { COLOR_ICON_ON_DARK, COLOR_ICON_ON_LIGHT, COLOR_ICON_SECONDARY, COLOR_TEXT_ON_LIGHT,
  COLOR_TEXT_PRIMARY } from '../main/ets/util/theme';

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

    // **漏算遮罩曾经把深色壁纸判成亮底**（用户实报）：Telegram 图案壁纸的填充色
    // 常常是浅的，但深色模式下整层还压着一层黑（dark_theme_dimming + 用户滑杆）。
    it('dark_mask_makes_a_light_fill_render_dark', 0, (): void => {
      const lightFill: string[] = ['#DBDDBB', '#6BA587', '#D5D88D', '#88B884'];
      // 不算遮罩：判成亮底（这就是当时的错）。
      expect(chromeSitsOnLight(lightFill, TINT_MATERIAL, false, 0)).assertTrue();
      // 算上壁纸自带的 55% 遮罩：其实是暗底，前景应当保持亮色。
      expect(chromeSitsOnLight(lightFill, TINT_MATERIAL, false, 0.55)).assertFalse();
    });

    // 遮罩拉满时无论什么壁纸都是暗底。
    it('full_mask_is_always_dark', 0, (): void => {
      expect(chromeSitsOnLight(['#FFFFFF'], TINT_MATERIAL, false, 1)).assertFalse();
    });

    // 脏遮罩值不该翻转结论。
    it('mask_is_clamped', 0, (): void => {
      expect(chromeSitsOnLight(['#FFFFFF'], TINT_MATERIAL, false, -1)).assertTrue();
      expect(chromeSitsOnLight(['#FFFFFF'], TINT_MATERIAL, false, 9)).assertFalse();
    });

    // 阈值按"白色前景还够不够 4.5:1"取（L≈0.183），不是常见的 0.5。
    // #767676 的 L≈0.20，白字在其上只有 4.1:1 —— 必须判成亮底。
    it('threshold_follows_white_text_legibility_not_midpoint', 0, (): void => {
      expect(chromeSitsOnLight(['#767676'], '#00000000', false)).assertTrue();
      expect(chromeSitsOnLight(['#5A5A5A'], '#00000000', false)).assertFalse();
    });
  });

  // ── 下面三组是从 ChatPage 下沉的 chrome 前景色判据（B3）。它们全都只是
  // 「给定字段值算出结果」，页面侧只剩薄包装——所以判据的每一条都钉在这里。

  describe('chromeDarkMaskOf', () => {
    // 两层黑要按不透明度**叠加**（1-(1-s)(1-u)），不是相加：ChatBackdrop 分两层
    // 画，相加会在 0.6+0.6 这种常见组合上算出 1.2（全黑），把亮壁纸误判成暗底。
    it('composites_the_two_masks_instead_of_adding_them', 0, (): void => {
      expect(chromeDarkMaskOf(0.5, 0.5)).assertEqual(0.75);
      expect(chromeDarkMaskOf(0.6, 0.6)).assertEqual(1 - 0.4 * 0.4);
      expect(chromeDarkMaskOf(0.55, 0)).assertEqual(0.55);
      expect(chromeDarkMaskOf(0, 0.4)).assertEqual(0.4);
    });

    it('no_mask_at_all_is_zero', 0, (): void => {
      expect(chromeDarkMaskOf(0, 0)).assertEqual(0);
    });

    // 任一层拉满就是全黑，另一层再怎么样都不改变结论。
    it('either_layer_at_full_opacity_wins', 0, (): void => {
      expect(chromeDarkMaskOf(1, 0)).assertEqual(1);
      expect(chromeDarkMaskOf(0, 1)).assertEqual(1);
    });

    // 服务端下发的 dimming 和用户滑杆都可能给出范围外的值，先各自夹紧再合成
    // ——否则负数会让叠加公式把遮罩算成"提亮"。
    it('clamps_both_inputs_before_compositing', 0, (): void => {
      expect(chromeDarkMaskOf(-1, 0)).assertEqual(0);
      expect(chromeDarkMaskOf(9, 0)).assertEqual(1);
      expect(chromeDarkMaskOf(0, -0.5)).assertEqual(0);
      expect(chromeDarkMaskOf(0.5, 9)).assertEqual(1);
    });
  });

  describe('chromeOnLightBgOf', () => {
    // **浅色模式永不翻**：浅色的前景本来就是给亮底挑的。这条闸保证整套机制
    // 对浅色模式零影响——壁纸再白也不翻。
    it('never_flips_in_light_mode', 0, (): void => {
      expect(chromeOnLightBgOf(false, ['#FFFFFF'], TINT_MATERIAL, 0)).assertFalse();
      expect(chromeOnLightBgOf(false, ['#D8D0EA', '#E4D8F0'], TINT_MATERIAL, 0)).assertFalse();
      expect(chromeOnLightBgOf(false, [], TINT_MATERIAL, 0)).assertFalse();
    });

    // 用户报的那一例：深色模式 + 浅紫壁纸，合成底 RGB(174,172,196)，
    // 图标 1.13:1、白字 2.22:1 —— 必须翻成深色前景。
    it('flips_in_dark_mode_on_a_light_wallpaper', 0, (): void => {
      expect(chromeOnLightBgOf(true, ['#D8D0EA', '#E4D8F0'], TINT_MATERIAL, 0)).assertTrue();
      expect(chromeOnLightBgOf(true, ['#AEACC4'], TINT_MATERIAL, 0)).assertTrue();
    });

    // 默认深色壁纸：本来就和主题一致，不该翻。
    it('keeps_dark_foreground_on_a_dark_wallpaper', 0, (): void => {
      expect(chromeOnLightBgOf(true, ['#0E1621'], TINT_MATERIAL, 0)).assertFalse();
    });

    // 遮罩必须一路传到判据里：图案壁纸填充浅 + 遮罩重 = 屏幕上其实是深的。
    // 参数顺序写反（把 mask 当 tint 之类）会在这条上炸。
    it('passes_the_dark_mask_through_to_the_verdict', 0, (): void => {
      const lightFill: string[] = ['#DBDDBB', '#6BA587', '#D5D88D', '#88B884'];
      expect(chromeOnLightBgOf(true, lightFill, TINT_MATERIAL, 0)).assertTrue();
      expect(chromeOnLightBgOf(true, lightFill, TINT_MATERIAL,
        chromeDarkMaskOf(0.55, 0))).assertFalse();
    });

    // 图片壁纸取不到颜色 → fallback 恒为 false（暗底），即这条路径的旧行为。
    it('image_wallpaper_stays_on_dark', 0, (): void => {
      expect(chromeOnLightBgOf(true, [], TINT_MATERIAL, 0)).assertFalse();
      expect(chromeOnLightBgOf(true, ['', 'nope'], TINT_MATERIAL, 0)).assertFalse();
    });
  });

  describe('chromeIconColorOf / chromeTextColorOf', () => {
    // 站到亮底上时两者都换成为"亮底"挑的那对固定值，与 app 处于哪个模式无关。
    it('on_a_light_background_both_use_the_on_light_pair', 0, (): void => {
      expect(chromeIconColorOf(true, true) === COLOR_ICON_ON_LIGHT).assertTrue();
      expect(chromeIconColorOf(true, false) === COLOR_ICON_ON_LIGHT).assertTrue();
      expect(chromeTextColorOf(true) === COLOR_TEXT_ON_LIGHT).assertTrue();
    });

    // 暗底 + 深色模式：亮白，不是列表里那种次级灰（灰会糊进壁纸）。
    it('dark_mode_on_a_dark_background_uses_bright_white_icons', 0, (): void => {
      expect(chromeIconColorOf(false, true) === COLOR_ICON_ON_DARK).assertTrue();
    });

    // 浅色模式保持原来的次级灰与主文字资源色：白色在浅色底上等于没有。
    it('light_mode_keeps_the_original_theme_colors', 0, (): void => {
      expect(chromeIconColorOf(false, false) === COLOR_ICON_SECONDARY).assertTrue();
      expect(chromeTextColorOf(false) === COLOR_TEXT_PRIMARY).assertTrue();
    });
  });

  // ── B3 收尾：把「叠加而非相加」「永不在浅色模式翻」「必须先合成再问」从注释
  // 升级成断言。上面几组钉的是各函数自身的输出；下面钉的是它们**串起来之后**
  // 仍然成立——页面侧只剩薄包装，接错线不会编译报错，只会静默把前景色翻反。

  describe('chromeDarkMaskOf 的叠加语义', () => {
    // 相加不只是"数值不同"，它会**翻转结论**：浅紫壁纸 + 服务端 dimming 19% +
    // 用户滑杆 19%，叠加得 0.3439（屏幕上仍是亮底，该翻前景），相加得 0.38
    // （越过阈值，判成暗底、前景不翻）——那就是浅紫底配白字，1.x:1 的原 bug。
    // 不写死 0.3439（浮点），只钉"严格小于相加、且严格大于任一单层"。
    it('adding_the_masks_instead_of_compositing_flips_the_verdict', 0, (): void => {
      const purple: string[] = ['#D8D0EA', '#E4D8F0'];
      const composited: number = chromeDarkMaskOf(0.19, 0.19);
      expect(composited < 0.19 + 0.19).assertTrue();
      expect(composited > 0.19).assertTrue();
      expect(chromeOnLightBgOf(true, purple, TINT_MATERIAL, composited)).assertTrue();
      expect(chromeOnLightBgOf(true, purple, TINT_MATERIAL, 0.19 + 0.19)).assertFalse();
    });

    // 再压一层黑只能更暗、不可能更亮：0.5 上叠 0.2 得 0.6——不是 0.1（写成相乘）
    // 也不是 0.3（写成相减）。拖用户滑杆时这条保证方向不反。
    it('a_second_layer_can_only_darken', 0, (): void => {
      expect(chromeDarkMaskOf(0.5, 0.2)).assertEqual(0.6);
      expect(chromeDarkMaskOf(0.5, 0.2) > chromeDarkMaskOf(0.5, 0)).assertTrue();
      expect(chromeDarkMaskOf(0.5, 0.2) <= 1).assertTrue();
    });

    // 两层黑谁先压谁后压都一样，所以**这个**函数的两参写反无害；真正怕写反的
    // 是 chromeOnLightBgOf 的四参（见下一组）。
    it('the_two_layers_commute', 0, (): void => {
      expect(chromeDarkMaskOf(0.6, 0.3)).assertEqual(chromeDarkMaskOf(0.3, 0.6));
    });
  });

  describe('chrome 前景的整条接线', () => {
    // 页面薄包装必须是 chromeOnLightBgOf(appDark, colors, glassTintHex(true),
    // chromeDarkMask())——**两层遮罩先合成再传**。只传其中一层就漏掉另一层的压暗
    // 量，把屏幕上其实很深的图案壁纸判成亮底（真机那组填充色）：
    //   · 只传用户滑杆 0.10、漏掉服务端 dimming 0.55 → 误判亮底；
    //   · 只传服务端 dimming 0.20、漏掉用户滑杆 0.50 → 同样误判。
    // 两种漏法都会让深色模式下的顶栏/输入栏换成深色前景，压在深壁纸上不可读。
    it('one_mask_layer_alone_is_not_enough', 0, (): void => {
      const patternFill: string[] = ['#DBDDBB', '#6BA587', '#D5D88D', '#88B884'];
      expect(chromeOnLightBgOf(true, patternFill, TINT_MATERIAL, 0.10)).assertTrue();
      expect(chromeOnLightBgOf(true, patternFill, TINT_MATERIAL,
        chromeDarkMaskOf(0.55, 0.10))).assertFalse();
      expect(chromeOnLightBgOf(true, patternFill, TINT_MATERIAL, 0.20)).assertTrue();
      expect(chromeOnLightBgOf(true, patternFill, TINT_MATERIAL,
        chromeDarkMaskOf(0.20, 0.50))).assertFalse();
    });

    // 前景色的第一参必须喂 chromeOnLightBgOf 的结果，**不是 appDark**。深色模式 +
    // 默认深色壁纸就是这条的哨兵：onLight=false → 亮白图标；误传 appDark(true)
    // 会拿到为亮底挑的深色图标，正好反了，而且编译不会报错。
    it('the_foreground_follows_the_wallpaper_not_the_mode', 0, (): void => {
      const onDarkWallpaper: boolean =
        chromeOnLightBgOf(true, ['#0E1621'], TINT_MATERIAL, chromeDarkMaskOf(0, 0));
      expect(onDarkWallpaper).assertFalse();
      expect(chromeIconColorOf(onDarkWallpaper, true) === COLOR_ICON_ON_DARK).assertTrue();
      expect(chromeTextColorOf(onDarkWallpaper) === COLOR_TEXT_PRIMARY).assertTrue();

      const onLightWallpaper: boolean = chromeOnLightBgOf(true, ['#D8D0EA', '#E4D8F0'],
        TINT_MATERIAL, chromeDarkMaskOf(0, 0));
      expect(onLightWallpaper).assertTrue();
      expect(chromeIconColorOf(onLightWallpaper, true) === COLOR_ICON_ON_LIGHT).assertTrue();
      expect(chromeTextColorOf(onLightWallpaper) === COLOR_TEXT_ON_LIGHT).assertTrue();
    });

    // 上面那些 === 断言只在四个常量确实互不相同时才有意义：谁要是把 on-light
    // 那一对改回主题色，整组会变成同义反复地全绿。
    it('the_two_foreground_pairs_are_distinct', 0, (): void => {
      expect(COLOR_ICON_ON_LIGHT === COLOR_ICON_ON_DARK).assertFalse();
      expect(COLOR_ICON_ON_LIGHT === COLOR_ICON_SECONDARY).assertFalse();
      expect(COLOR_TEXT_ON_LIGHT === COLOR_TEXT_PRIMARY).assertFalse();
    });
  });

  describe('chromeOnLightBgOf 的遮罩边界', () => {
    // 遮罩 0 = 壁纸没有 dark_theme_dimming、用户滑杆也归零：只剩填充色说了算。
    it('zero_mask_lets_the_raw_fill_decide', 0, (): void => {
      expect(chromeOnLightBgOf(true, ['#FFFFFF'], TINT_MATERIAL, 0)).assertTrue();
      expect(chromeOnLightBgOf(true, ['#0E1621'], TINT_MATERIAL, 0)).assertFalse();
    });

    // 遮罩 1 = 整层压成黑，任何壁纸都是暗底，前景一律不翻。
    it('full_mask_never_flips_any_wallpaper', 0, (): void => {
      expect(chromeOnLightBgOf(true, ['#FFFFFF'], TINT_MATERIAL, 1)).assertFalse();
      expect(chromeOnLightBgOf(true, ['#D8D0EA', '#E4D8F0'], TINT_MATERIAL, 1)).assertFalse();
      expect(chromeOnLightBgOf(true, ['#DBDDBB', '#6BA587'], TINT_MATERIAL, 1)).assertFalse();
    });

    // 图片壁纸（颜色数组为空）走 fallback，遮罩多重都不参与——短路发生在遮罩
    // 参与合成之前，所以 0 和 1 必须给出同一个答案。
    it('an_empty_color_list_ignores_the_mask', 0, (): void => {
      expect(chromeOnLightBgOf(true, [], TINT_MATERIAL, 0)).assertFalse();
      expect(chromeOnLightBgOf(true, [], TINT_MATERIAL, 1)).assertFalse();
      expect(chromeOnLightBgOf(false, [], TINT_MATERIAL, 1)).assertFalse();
    });
  });
}
