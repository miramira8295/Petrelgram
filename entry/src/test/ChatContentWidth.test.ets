import { describe, expect, it } from '@ohos/hypium';
import {
  CHAT_CONTENT_WIDTH_KEY, chatContentWidth, publishChatContentWidth
} from '../main/ets/util/chatContentWidth';

export default function chatContentWidthTest() {
  describe('chatContentWidth', () => {
    it('没发布过时退回窗口宽', 0, (): void => {
      // 第一帧之前、或在聊天页之外算相册占位：用的正是此前一直在用的值。
      AppStorage.setOrCreate<number>(CHAT_CONTENT_WIDTH_KEY, 0);
      AppStorage.setOrCreate<number>('screenWidthVp', 1440);
      expect(chatContentWidth()).assertEqual(1440);
    });

    it('发布之后以内容列宽为准', 0, (): void => {
      // issue #107：平板窗口 1440，右栏 960，气泡必须按 960 算。
      AppStorage.setOrCreate<number>('screenWidthVp', 1440);
      publishChatContentWidth(960);
      expect(chatContentWidth()).assertEqual(960);
    });

    it('非法宽度不发布', 0, (): void => {
      publishChatContentWidth(960);
      publishChatContentWidth(0);
      publishChatContentWidth(-5);
      publishChatContentWidth(Number.NaN);
      expect(chatContentWidth()).assertEqual(960);
    });

    it('同值不写', 0, (): void => {
      // setOrCreate 即便同值也惊动订阅方；onAreaChange 会连着来几次。
      publishChatContentWidth(900);
      let writes: number = 0;
      const before: number | undefined = AppStorage.get<number>(CHAT_CONTENT_WIDTH_KEY);
      publishChatContentWidth(900);
      if (AppStorage.get<number>(CHAT_CONTENT_WIDTH_KEY) !== before) { writes++; }
      expect(writes).assertEqual(0);
      expect(chatContentWidth()).assertEqual(900);
    });
  });
}
