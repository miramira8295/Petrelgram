import { describe, expect, it } from '@ohos/hypium';
import {
  buildEmojiStatusValue, customEmojiIdOfStatus, emojiStatusIdsOf, emojiStatusSkipsDownload, emojiStatusVisible,
  stickerFormatOf
} from '../main/ets/util/emojiStatus';
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

  describe('buildEmojiStatusValue', () => {
    it('新旧两种形状一起带上：老 so 只认平铺的 custom_emoji_id，新 so 只认 type', 0, (): void => {
      const es = buildEmojiStatusValue('5368324170671202286') as TdObject;
      expect(es['@type']).assertEqual('emojiStatus');
      expect(es['custom_emoji_id']).assertEqual('5368324170671202286');
      const type = es['type'] as TdObject;
      expect(type['@type']).assertEqual('emojiStatusTypeCustomEmoji');
      expect(type['custom_emoji_id']).assertEqual('5368324170671202286');
    });
    it('空 id 表示清除：不带 emoji_status', 0, (): void => {
      expect(buildEmojiStatusValue('')).assertUndefined();
    });
  });
  // 帧缓存命中就不下载（2026-10-10）：只有 webm 有按唯一 ID 的帧缓存。
  describe('emojiStatusSkipsDownload', () => {
    it('webm + 有 ID + 帧缓存在：跳过下载', 0, (): void => {
      expect(emojiStatusSkipsDownload('webm', 'AgADBQAD', true)).assertTrue();
    });
    it('缓存不在、没有 ID、不是 webm：照常下载', 0, (): void => {
      expect(emojiStatusSkipsDownload('webm', 'AgADBQAD', false)).assertFalse();
      expect(emojiStatusSkipsDownload('webm', '', true)).assertFalse();
      expect(emojiStatusSkipsDownload('tgs', 'AgADBQAD', true)).assertFalse();
      expect(emojiStatusSkipsDownload('webp', 'AgADBQAD', true)).assertFalse();
    });
  });

  describe('emojiStatusVisible', () => {
    it('有本地文件，或靠帧缓存播（没路径但有 ID）都显示', 0, (): void => {
      expect(emojiStatusVisible('/data/a.webm', '')).assertTrue();
      expect(emojiStatusVisible('', 'AgADBQAD')).assertTrue();
      expect(emojiStatusVisible('', '')).assertFalse();
    });
  });

  describe('stickerFormatOf', () => {
    it('三种格式，认不出按 webm', 0, (): void => {
      const tgs: TdObject = { '@type': 'sticker' }; tgs['format'] = { '@type': 'stickerFormatTgs' } as TdObject;
      const webp: TdObject = { '@type': 'sticker' }; webp['format'] = { '@type': 'stickerFormatWebp' } as TdObject;
      const webm: TdObject = { '@type': 'sticker' }; webm['format'] = { '@type': 'stickerFormatWebm' } as TdObject;
      expect(stickerFormatOf(tgs)).assertEqual('tgs');
      expect(stickerFormatOf(webp)).assertEqual('webp');
      expect(stickerFormatOf(webm)).assertEqual('webm');
      expect(stickerFormatOf({ '@type': 'sticker' })).assertEqual('webm');
    });
  });
}
