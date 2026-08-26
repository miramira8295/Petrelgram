import { describe, expect, it } from '@ohos/hypium';
import { canonicalReactionEmoji, stripVariationSelectors } from '../main/ets/util/reactions';

export default function reactionCanonicalTest() {
  describe('canonicalReactionEmoji', () => {
    it('去掉变体选择符', 0, (): void => {
      expect(stripVariationSelectors('❤️')).assertEqual('❤');
      expect(stripVariationSelectors('👍')).assertEqual('👍');
    });
    it('服务端不带 VS16 时改用它的写法', 0, (): void => {
      expect(canonicalReactionEmoji('❤️', ['❤', '👍']))
        .assertEqual('❤');
    });
    it('服务端带 VS16 而我们不带时也能对上', 0, (): void => {
      expect(canonicalReactionEmoji('❤', ['❤️'])).assertEqual('❤️');
    });
    it('精确命中原样返回', 0, (): void => {
      expect(canonicalReactionEmoji('👍', ['👍'])).assertEqual('👍');
    });
    it('还没拉到可用表情时不拦着', 0, (): void => {
      expect(canonicalReactionEmoji('❤️', [])).assertEqual('❤️');
    });
    it('完全不在列表里也照发（由服务端判定）', 0, (): void => {
      expect(canonicalReactionEmoji('🔥', ['❤'])).assertEqual('🔥');
    });
  });
}
