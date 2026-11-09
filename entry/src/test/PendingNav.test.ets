import { describe, it, expect, beforeEach } from '@ohos/hypium';
import {
  queuePendingNav, takePendingNavs, clearPendingNavs, pendingNavCount,
  MAX_PENDING_NAVS, PendingNav
} from '../main/ets/util/pendingNav';

function nav(tab: string, kind: string, chatId: number = 0): PendingNav {
  const params: Record<string, Object> = {};
  if (chatId !== 0) { params['chatId'] = chatId; }
  return { tab: tab, kind: kind, dest: 'ChatPage', params: params, origin: 'navbar' };
}

export default function pendingNavTest() {
  describe('pendingNav', () => {
    beforeEach((): void => { clearPendingNavs(); });

    it('挂起后按页签取走，取走即清空', 0, (): void => {
      queuePendingNav(nav('chat', 'chat', 7));
      queuePendingNav(nav('settings', 'settings'));
      const chat: PendingNav[] = takePendingNavs('chat');
      expect(chat.length).assertEqual(1);
      expect(chat[0].params['chatId'] as number).assertEqual(7);
      expect(takePendingNavs('chat').length).assertEqual(0);
      // 别的页签那条还在
      expect(pendingNavCount()).assertEqual(1);
    });

    it('同一个 kind 只留最后一次（连点两条通知，开后点的那条）', 0, (): void => {
      queuePendingNav(nav('chat', 'chat', 1));
      queuePendingNav(nav('chat', 'chat', 2));
      const got: PendingNav[] = takePendingNavs('chat');
      expect(got.length).assertEqual(1);
      expect(got[0].params['chatId'] as number).assertEqual(2);
    });

    it('不同 kind 各留一条，顺序按挂起先后', 0, (): void => {
      queuePendingNav(nav('chat', 'chat', 1));
      queuePendingNav(nav('chat', 'search'));
      const got: PendingNav[] = takePendingNavs('chat');
      expect(got.length).assertEqual(2);
      expect(got[0].kind).assertEqual('chat');
      expect(got[1].kind).assertEqual('search');
    });

    it('超上限丢最老的', 0, (): void => {
      for (let i = 0; i < MAX_PENDING_NAVS + 2; i++) {
        queuePendingNav(nav('chat', `k${i}`));
      }
      const got: PendingNav[] = takePendingNavs('chat');
      expect(got.length).assertEqual(MAX_PENDING_NAVS);
      expect(got[0].kind).assertEqual('k2');
    });

    it('切账号清空', 0, (): void => {
      queuePendingNav(nav('chat', 'chat', 5));
      clearPendingNavs();
      expect(pendingNavCount()).assertEqual(0);
    });
  });
}
