import { describe, expect, it } from '@ohos/hypium';
import {
  chatChromeHeight, ChatChromeGeometryInput, chatTopBannerRows
} from '../main/ets/util/ChatChromeGeometry';
import {
  ALPHA_STICKER_CACHE_MAX_BYTES, IMAGE_HOLDER_RELEASE_BATCH, IMAGE_PIXEL_CACHE_MAX_BYTES,
  NATIVE_PIXEL_CACHE_MAX_BYTES, fullNativePixelBudget, pressuredNativePixelBudget
} from '../main/ets/util/NativePixelBudget';

function chrome(searchMode: boolean = false, pinnedVisible: boolean = false,
  liveVisible: boolean = false, loadingVisible: boolean = false): ChatChromeGeometryInput {
  return {
    topSafe: 24,
    searchMode,
    pinnedVisible,
    liveVisible,
    loadingVisible
  };
}

export default function performanceBudgetsTest() {
  describe('performanceBudgets', () => {
    it('keeps title content out of chat chrome geometry', 0, (): void => {
      expect(chatChromeHeight(chrome())).assertEqual(82);
      expect(chatChromeHeight(chrome(true))).assertEqual(86);
      expect(chatChromeHeight(chrome(false, true))).assertEqual(138);
      expect(chatChromeHeight(chrome(false, true, true))).assertEqual(192.5);
    });

    it('uses loading as a fallback row instead of an extra banner', 0, (): void => {
      expect(chatTopBannerRows(chrome(false, false, false, true))).assertEqual(1);
      expect(chatTopBannerRows(chrome(false, true, false, true))).assertEqual(1);
      expect(chatTopBannerRows(chrome(false, true, true, true))).assertEqual(2);
    });

    it('caps both pixel caches at eighty MiB combined', 0, (): void => {
      expect(IMAGE_PIXEL_CACHE_MAX_BYTES).assertEqual(48 * 1024 * 1024);
      expect(ALPHA_STICKER_CACHE_MAX_BYTES).assertEqual(32 * 1024 * 1024);
      expect(NATIVE_PIXEL_CACHE_MAX_BYTES).assertEqual(80 * 1024 * 1024);
      const full = fullNativePixelBudget();
      expect(full.imageBytes + full.alphaBytes).assertEqual(NATIVE_PIXEL_CACHE_MAX_BYTES);
    });

    it('bounds component image releases per event-loop turn', 0, (): void => {
      expect(IMAGE_HOLDER_RELEASE_BATCH).assertEqual(3);
    });

    it('shrinks progressively and drops background caches', 0, (): void => {
      const moderate = pressuredNativePixelBudget(0, true);
      expect(moderate.imageBytes).assertEqual(24 * 1024 * 1024);
      expect(moderate.alphaBytes).assertEqual(16 * 1024 * 1024);
      const low = pressuredNativePixelBudget(1, true);
      expect(low.imageBytes).assertEqual(12 * 1024 * 1024);
      expect(low.alphaBytes).assertEqual(8 * 1024 * 1024);
      const critical = pressuredNativePixelBudget(2, true);
      expect(critical.imageBytes + critical.alphaBytes).assertEqual(0);
      const background = pressuredNativePixelBudget(0, false);
      expect(background.imageBytes + background.alphaBytes).assertEqual(0);
    });
  });
}
