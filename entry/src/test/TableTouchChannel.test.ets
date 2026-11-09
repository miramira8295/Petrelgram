import { describe, it, expect } from '@ohos/hypium';
import {
  resetTableScrollTouchForTest, setTableScrollTouch, tableScrollTouched
} from '../main/ets/util/tableTouchChannel';

export default function tableTouchChannelTest() {
  describe('TableTouchChannel', () => {
    it('默认没人按着', 0, () => {
      resetTableScrollTouchForTest();
      expect(tableScrollTouched()).assertFalse();
    });

    it('按下打开、抬手关掉', 0, () => {
      resetTableScrollTouchForTest();
      setTableScrollTouch(true);
      expect(tableScrollTouched()).assertTrue();
      setTableScrollTouch(false);
      expect(tableScrollTouched()).assertFalse();
    });

    // 抬手事件丢了的话，标记会一直挂着，之后所有消息都滑不动回复。
    it('重复关闭是幂等的', 0, () => {
      resetTableScrollTouchForTest();
      setTableScrollTouch(false);
      setTableScrollTouch(false);
      expect(tableScrollTouched()).assertFalse();
    });
  });
}
