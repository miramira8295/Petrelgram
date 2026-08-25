import { describe, expect, it } from '@ohos/hypium';
import { customEmojiIdOfStatus, emojiStatusIdsOf } from '../main/ets/util/emojiStatus';
import { TdObject } from '../main/ets/tdkit/TdTypes';

export default function emojiStatusIdTest() {
  describe('customEmojiIdOfStatus', () => {
    it('新 schema：id 在 type 里', 0, (): void => {
      const type: TdObject = { '@type': 'emojiStatusTypeCustomEmoji' }; type['custom_emoji_id'] = '5368324170671202286';
      const es: TdObject = { '@type': 'emojiStatus' }; es['type'] = type;
      expect(customEmojiIdOfStatus(es)).assertEqual('5368324170671202286');
    });
    it('老 schema：id 平铺在 emojiStatus 上（issue #120，会员只看到「清除」）', 0, (): void => {
      const es: TdObject = { '@type': 'emojiStatus' }; es['custom_emoji_id'] = '5368324170671202286';
      expect(customEmojiIdOfStatus(es)).assertEqual('5368324170671202286');
    });
    it('认不出的返回空串', 0, (): void => {
      expect(customEmojiIdOfStatus(undefined)).assertEqual('');
      expect(customEmojiIdOfStatus({ '@type': 'emojiStatus' } as TdObject)).assertEqual('');
      const es: TdObject = { '@type': 'emojiStatus' }; es['custom_emoji_id'] = '0';
      expect(customEmojiIdOfStatus(es)).assertEqual('');
    });
    it('回包新 schema：emoji_statuses 数组', 0, (): void => {
      const type: TdObject = { '@type': 'emojiStatusTypeCustomEmoji' }; type['custom_emoji_id'] = '11';
      const es: TdObject = { '@type': 'emojiStatus' }; es['type'] = type;
      const r: TdObject = { '@type': 'emojiStatuses' }; r['emoji_statuses'] = [es];
      expect(emojiStatusIdsOf(r).join(',')).assertEqual('11');
    });
    it('回包老 schema：custom_emoji_ids 一串 id（捆绑 TDLib 的形状，issue #120）', 0, (): void => {
      const r: TdObject = { '@type': 'emojiStatuses' }; r['custom_emoji_ids'] = ['11', '22', '11'];
      expect(emojiStatusIdsOf(r).join(',')).assertEqual('11,22');
    });
    it('回包没有任何一种字段时为空', 0, (): void => {
      expect(emojiStatusIdsOf({ '@type': 'emojiStatuses' } as TdObject).length).assertEqual(0);
      expect(emojiStatusIdsOf(undefined).length).assertEqual(0);
    });
  });
}
