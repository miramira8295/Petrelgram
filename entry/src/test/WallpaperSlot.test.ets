import { describe, expect, it } from '@ohos/hypium';
import {
  SLOT_APP_DARK, SLOT_APP_LIGHT, SLOT_CHAT_DARK, SLOT_CHAT_LIGHT, WALLPAPER_SLOTS,
  slotHasDim, slotIsApp, slotIsDark, wallpaperSlotKeys, WallpaperSlotKeys
} from '../main/ets/util/wallpaperSlot';

export default function wallpaperSlotTest() {
  describe('wallpaperSlot', () => {
    it('four_slots', 0, (): void => {
      expect(WALLPAPER_SLOTS.length).assertEqual(4);
    });

    it('app_and_dark_are_orthogonal', 0, (): void => {
      expect(slotIsApp(SLOT_APP_LIGHT)).assertTrue();
      expect(slotIsApp(SLOT_CHAT_DARK)).assertFalse();
      expect(slotIsDark(SLOT_APP_DARK)).assertTrue();
      expect(slotIsDark(SLOT_CHAT_LIGHT)).assertFalse();
    });

    // 只有 APP 槽位在本地存壁纸状态；聊天槽位的壁纸由 TDLib 下发，本地再存一份
    // 两边会打架。
    it('only_app_slots_store_state_locally', 0, (): void => {
      expect(wallpaperSlotKeys(SLOT_APP_LIGHT).state !== '').assertTrue();
      expect(wallpaperSlotKeys(SLOT_APP_DARK).state !== '').assertTrue();
      expect(wallpaperSlotKeys(SLOT_CHAT_LIGHT).state).assertEqual('');
      expect(wallpaperSlotKeys(SLOT_CHAT_DARK).state).assertEqual('');
    });

    // 这是这张表存在的全部理由：四个槽位的每一根滑杆都必须落在**不同**的键上，
    // 否则会出现"调了浅色、深色跟着变"这种极难查的错。
    it('no_two_slots_share_a_slider_key', 0, (): void => {
      const seen: string[] = [];
      for (const slot of WALLPAPER_SLOTS) {
        const k: WallpaperSlotKeys = wallpaperSlotKeys(slot);
        // 遮罩只在深色槽位参与渲染，两个 APP 槽位共用同一个遮罩/模糊键是有意的
        // （见 wallpaperSlotKeys 的注释），所以这里只断言**纹理**互不相同。
        expect(seen.indexOf(k.pattern) < 0).assertTrue();
        seen.push(k.pattern);
      }
      expect(seen.length).assertEqual(4);
    });

    // 聊天两侧的模糊必须是两个键——旧版共用一个，四槽位下会串。
    it('chat_light_and_dark_blur_are_separate', 0, (): void => {
      expect(wallpaperSlotKeys(SLOT_CHAT_LIGHT).blur === wallpaperSlotKeys(SLOT_CHAT_DARK).blur)
        .assertFalse();
    });

    it('dim_only_matters_for_dark_slots', 0, (): void => {
      expect(slotHasDim(SLOT_APP_DARK)).assertTrue();
      expect(slotHasDim(SLOT_CHAT_DARK)).assertTrue();
      expect(slotHasDim(SLOT_APP_LIGHT)).assertFalse();
      expect(slotHasDim(SLOT_CHAT_LIGHT)).assertFalse();
    });

    // 未知槽位不能返回空键，否则读写会落到 undefined 上。
    it('unknown_slot_falls_back_to_valid_keys', 0, (): void => {
      const k: WallpaperSlotKeys = wallpaperSlotKeys('nope');
      expect(k.pattern !== '' && k.blur !== '' && k.dim !== '').assertTrue();
    });
  });
}
