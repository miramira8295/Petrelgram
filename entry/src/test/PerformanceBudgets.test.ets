import { describe, expect, it } from '@ohos/hypium';
import {
  CHAT_TOPIC_BAR_HEIGHT, chatChromeHeight, ChatChromeGeometryInput, chatTopBannerRows,
  chatTopicBarHeight
} from '../main/ets/util/ChatChromeGeometry';
import {
  ALPHA_STICKER_CACHE_MAX_BYTES, IMAGE_HOLDER_RELEASE_BATCH, IMAGE_PIXEL_CACHE_MAX_BYTES,
  NATIVE_PIXEL_CACHE_MAX_BYTES, fullNativePixelBudget, pressuredNativePixelBudget
} from '../main/ets/util/NativePixelBudget';

function chrome(searchMode: boolean = false, pinnedVisible: boolean = false,
  liveVisible: boolean = false): ChatChromeGeometryInput {
  return {
    topSafe: 24,
    searchMode,
    pinnedVisible,
    liveVisible
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

    // 话题横条（2026-09-16）：论坛群在顶栏标题行下面多挂一条可横向滚的话题胶囊。
    //
    // 做成**可选字段**是刻意的：上面那四条断言的入参根本不传它，所以老行为
    // 一个数字都不会变——非论坛会话的顶栏高度必须和以前逐像素一致。
    it('topic bar adds its own row only when present', 0, (): void => {
      expect(chatTopicBarHeight(chrome())).assertEqual(0);
      const withBar: ChatChromeGeometryInput = chrome();
      withBar.topicBarVisible = true;
      expect(chatTopicBarHeight(withBar)).assertEqual(CHAT_TOPIC_BAR_HEIGHT);
      expect(chatChromeHeight(withBar)).assertEqual(82 + CHAT_TOPIC_BAR_HEIGHT);
    });

    // 话题横条与置顶/直播横幅可以同时存在：两段高度相加，谁都不能吃掉谁。
    it('topic bar stacks with the banners', 0, (): void => {
      const both: ChatChromeGeometryInput = chrome(false, true, true);
      both.topicBarVisible = true;
      expect(chatChromeHeight(both)).assertEqual(192.5 + CHAT_TOPIC_BAR_HEIGHT);
    });

    // 搜索态顶栏更高，话题横条照样叠在它下面。
    it('topic bar survives search mode', 0, (): void => {
      const searching: ChatChromeGeometryInput = chrome(true);
      searching.topicBarVisible = true;
      expect(chatChromeHeight(searching)).assertEqual(86 + CHAT_TOPIC_BAR_HEIGHT);
    });

    // issue #173：加载中不再占一行（占位卡已去掉），只有确认的内容才占位。
    it('only confirmed banners take rows', 0, (): void => {
      expect(chatTopBannerRows(chrome())).assertEqual(0);
      expect(chatTopBannerRows(chrome(false, true))).assertEqual(1);
      expect(chatTopBannerRows(chrome(false, true, true))).assertEqual(2);
    });

    it('caps both pixel caches at eighty MiB combined', 0, (): void => {
      expect(IMAGE_PIXEL_CACHE_MAX_BYTES).assertEqual(48 * 1024 * 1024);
      expect(ALPHA_STICKER_CACHE_MAX_BYTES).assertEqual(32 * 1024 * 1024);
      expect(NATIVE_PIXEL_CACHE_MAX_BYTES).assertEqual(80 * 1024 * 1024);
      const full = fullNativePixelBudget();
      expect(full.imageBytes + full.alphaBytes).assertEqual(NATIVE_PIXEL_CACHE_MAX_BYTES);
    });

    // 这个值必须**高于滚动时的到达速率**：drainHolderReleases 在队列非空时会
    // setTimeout(...,0) 自我重排，值太小就排不空，定时器变成常驻的每帧定时器
    // （2026-09-09 Frame 录制实测，3 那一版的 setTimeout 开销归一化涨了 65%）。
    it('bounds component image releases per event-loop turn', 0, (): void => {
      expect(IMAGE_HOLDER_RELEASE_BATCH).assertEqual(16);
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

    // issue #201 第 8 条：会话操作条占一行，和置顶/直播横幅同高，叠加计数；
    // 单独存在时也算一行。
    it('action_bar_counts_as_one_banner_row', 0, (): void => {
      const base: ChatChromeGeometryInput = {
        topSafe: 0, searchMode: false, pinnedVisible: false, liveVisible: false,
        actionBarVisible: true
      };
      expect(chatTopBannerRows(base)).assertEqual(1);
      const withPinned: ChatChromeGeometryInput = {
        topSafe: 0, searchMode: false, pinnedVisible: true, liveVisible: false,
        actionBarVisible: true
      };
      expect(chatTopBannerRows(withPinned)).assertEqual(2);
    });
  });
}
