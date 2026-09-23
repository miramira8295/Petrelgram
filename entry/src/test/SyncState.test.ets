import { describe, expect, it } from '@ohos/hypium';
import { chatListSyncState } from '../main/ets/util/syncState';

// 首页标题下那行连接状态（#219-7）。
export default function syncStateTest() {
  describe('SyncState', () => {
    it('四种未就绪状态原样显示', 0, () => {
      expect(chatListSyncState('connectionStateWaitingForNetwork'))
        .assertEqual('connectionStateWaitingForNetwork');
      expect(chatListSyncState('connectionStateConnecting')).assertEqual('connectionStateConnecting');
      expect(chatListSyncState('connectionStateConnectingToProxy'))
        .assertEqual('connectionStateConnectingToProxy');
      expect(chatListSyncState('connectionStateUpdating')).assertEqual('connectionStateUpdating');
    });

    it('已就绪不显示', 0, () => {
      expect(chatListSyncState('connectionStateReady')).assertEqual('');
    });

    // 还没收到过任何连接状态（缓存为空）时不显示，不能凭空说"等待网络"。
    it('未知或空串不显示', 0, () => {
      expect(chatListSyncState('')).assertEqual('');
      expect(chatListSyncState('connectionStateSomethingNew')).assertEqual('');
    });
  });
}
