import { describe, it, expect } from '@ohos/hypium';
import { inlineThumbEntryChanged } from '../main/ets/util/inlineThumbUpdate';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdObject, TdBridge } from '../main/ets/tdkit/TdTypes';
import { UserStore } from '../main/ets/store/UserStore';
import { buildMessageEntry, cloneMessage, MessageEntry } from '../main/ets/store/MessageEntry';

class FakeBridge implements TdBridge {
  onReceive: (json: string) => void = (): void => {};
  init(cb: (json: string) => void): void { this.onReceive = cb; }
  send(json: string): void {}
}

function entryOf(path: string, percent: number, failed: boolean): MessageEntry {
  const bridge = new FakeBridge();
  const client = new TdClient(bridge);
  const users = new UserStore(client);
  client.start();
  const ft: TdObject = { '@type': 'formattedText' };
  ft['text'] = '';
  const content: TdObject = { '@type': 'messageText' };
  content['text'] = ft;
  const sender: TdObject = { '@type': 'messageSenderUser' };
  sender['user_id'] = 7;
  const m: TdObject = { '@type': 'message' };
  m['id'] = 1; m['is_outgoing'] = false; m['sender_id'] = sender; m['date'] = 100;
  m['content'] = content;
  const e = cloneMessage(buildMessageEntry(m, users));
  e.photoFileId = 42;
  e.photoPath = path;
  e.photoProgress = percent;
  e.photoFailed = failed;
  return e;
}

export default function inlineThumbUpdateTest() {
  describe('inlineThumbEntryChanged', () => {
    it('同一个百分比又报一遍：不必克隆', 0, (): void => {
      const e = entryOf('', 40, false);
      expect(inlineThumbEntryChanged(e, 40, false, '')).assertFalse();
    });

    it('百分比推进了：要记进条目', 0, (): void => {
      const e = entryOf('', 40, false);
      expect(inlineThumbEntryChanged(e, 41, false, '')).assertTrue();
    });

    it('路径落地：即使百分比没变也要记', 0, (): void => {
      // 完成那一刻百分比可能已经是 100 了，路径才是新东西。
      const e = entryOf('', 100, false);
      expect(inlineThumbEntryChanged(e, 100, true, '/data/a.jpg')).assertTrue();
    });

    it('同一条路径重复落地：不必克隆', 0, (): void => {
      const e = entryOf('/data/a.jpg', 100, false);
      expect(inlineThumbEntryChanged(e, 100, true, '/data/a.jpg')).assertFalse();
    });

    it('重试成功要清失败位：路径相同也得记', 0, (): void => {
      const e = entryOf('/data/a.jpg', 100, true);
      expect(inlineThumbEntryChanged(e, 100, true, '/data/a.jpg')).assertTrue();
    });

    it('还没下完就不看路径', 0, (): void => {
      const e = entryOf('', 100, true);
      expect(inlineThumbEntryChanged(e, 100, false, '/data/a.jpg')).assertFalse();
    });
  });
}
