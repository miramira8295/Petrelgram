import { describe, it, expect } from '@ohos/hypium';
import {
  PINNED_FETCH_LIMIT, pinnedCountLabel, pinnedDate, pinnedEntryOf, pinnedSenderId
} from '../main/ets/util/pinnedEntry';
import { TdObject } from '../main/ets/tdkit/TdTypes';

function msg(over: Record<string, Object>): TdObject {
  const base: TdObject = { 'id': 100, 'date': 1700000000 };
  for (const k of Object.keys(over)) {
    base[k] = over[k];
  }
  return base;
}

export default function pinnedEntryTest() {
  describe('PinnedEntry', () => {
    it('取出用户发送者的 id', 0, () => {
      const m = msg({ 'sender_id': { '@type': 'messageSenderUser', 'user_id': 42 } as TdObject });
      expect(pinnedSenderId(m)).assertEqual(42);
    });

    // 「以频道/群身份发言」没有用户 id。显示一个陌生的 chat_id 不如回落到会话名，
    // 所以这里一律当 0，由界面决定怎么显示。
    it('频道身份发言返回 0，交给界面回落', 0, () => {
      const m = msg({ 'sender_id': { '@type': 'messageSenderChat', 'chat_id': -100 } as TdObject });
      expect(pinnedSenderId(m)).assertEqual(0);
    });

    it('缺 sender_id 或形状不对都返回 0，不抛', 0, () => {
      expect(pinnedSenderId(msg({}))).assertEqual(0);
      expect(pinnedSenderId(msg({ 'sender_id': {} as TdObject }))).assertEqual(0);
      expect(pinnedSenderId(msg({ 'sender_id': { '@type': 'messageSenderUser' } as TdObject }))).assertEqual(0);
    });

    it('时间缺失或非正数当 0，界面据此不显示时间', 0, () => {
      const noDate: TdObject = { 'id': 100 };
      expect(pinnedDate(noDate)).assertEqual(0);
      expect(pinnedDate(msg({ 'date': 0 }))).assertEqual(0);
      expect(pinnedDate(msg({ 'date': -5 }))).assertEqual(0);
      expect(pinnedDate(msg({ 'date': 1700000000 }))).assertEqual(1700000000);
    });

    it('正常条目原样组装', 0, () => {
      const m = msg({ 'sender_id': { '@type': 'messageSenderUser', 'user_id': 7 } as TdObject });
      const e = pinnedEntryOf(m, '周会改到周四');
      expect(e !== null).assertTrue();
      expect(e!.id).assertEqual(100);
      expect(e!.preview).assertEqual('周会改到周四');
      expect(e!.senderId).assertEqual(7);
      expect(e!.date).assertEqual(1700000000);
    });

    // 没有 id 就跳不过去，列出来只会让人点了没反应。
    it('缺 id 的条目被丢掉', 0, () => {
      const noId: TdObject = { 'date': 1700000000 };
      expect(pinnedEntryOf(noId, 'x')).assertNull();
      const zeroId: TdObject = { 'id': 0 };
      expect(pinnedEntryOf(zeroId, 'x')).assertNull();
    });

    it('空预览仍然保留：媒体消息的预览可能是空串，但它照样能跳', 0, () => {
      const e = pinnedEntryOf(msg({}), '');
      expect(e !== null).assertTrue();
      expect(e!.preview).assertEqual('');
    });

    // 一次最多取 100 条，再多的我们根本没拉下来。显示真实条数会让人
    // 以为列表不全是 bug，所以到顶就显示 100+。
    it('条数到达抓取上限时显示 100+', 0, () => {
      expect(pinnedCountLabel(0)).assertEqual('0');
      expect(pinnedCountLabel(12)).assertEqual('12');
      expect(pinnedCountLabel(PINNED_FETCH_LIMIT - 1)).assertEqual('99');
      expect(pinnedCountLabel(PINNED_FETCH_LIMIT)).assertEqual('100+');
      expect(pinnedCountLabel(PINNED_FETCH_LIMIT + 30)).assertEqual('100+');
    });
  });
}
