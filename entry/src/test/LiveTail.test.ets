import { describe, it, expect } from '@ohos/hypium';
import { reachedLiveTail } from '../main/ets/util/liveTail';

export default function liveTailTest() {
  describe('liveTail', () => {
    // 窗口最新一条就是会话最后一条：确定到底了，分页该关。
    it('window_newest_equals_chat_last_is_tail', 0, () => {
      expect(reachedLiveTail(11472555999232, 11472555999232)).assertTrue();
    });

    // 窗口比会话记录的还新：新消息先进了窗口、updateChatLastMessage 慢一拍。
    // 这同样是尾部——用 >= 而不是 ===，否则这半拍里判定会翻回"没到底"。
    it('window_newer_than_chat_last_is_tail', 0, () => {
      expect(reachedLiveTail(11472556000000, 11472555999232)).assertTrue();
    });

    // 窗口还落在后面：确实有更新的没加载，分页必须继续。
    it('window_older_than_chat_last_is_not_tail', 0, () => {
      expect(reachedLiveTail(11472273932288, 11472555999232)).assertFalse();
    });

    // **不知道会话最后一条是哪条时不能下结论**。返回 false 让分页照常走——
    // 误判成"到底了"会把 hasMoreNewer 关掉，用户就再也翻不到更新的消息，
    // 比多翻几页严重得多。
    it('unknown_chat_last_is_not_conclusive', 0, () => {
      expect(reachedLiveTail(11472555999232, 0)).assertFalse();
    });

    // 空窗口同理，没有判据。
    it('empty_window_is_not_conclusive', 0, () => {
      expect(reachedLiveTail(0, 11472555999232)).assertFalse();
      expect(reachedLiveTail(0, 0)).assertFalse();
    });

    // 负数是脏数据，不能当成"到底了"。
    it('negative_input_is_not_tail', 0, () => {
      expect(reachedLiveTail(-1, 11472555999232)).assertFalse();
      expect(reachedLiveTail(11472555999232, -1)).assertFalse();
    });
  });
}
