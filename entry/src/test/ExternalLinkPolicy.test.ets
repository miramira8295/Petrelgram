import { describe, expect, it } from '@ohos/hypium';
import {
  EXT_LINK_ASK, EXT_LINK_COPY, EXT_LINK_DEFAULT, EXT_LINK_OPEN,
  externalLinkDecision, normalizeExternalLinkPolicy
} from '../main/ets/util/externalLinkPolicy';

// 外部链接三档（2026-09-18）。判据只有两个输入：用户选的档位，以及这条链接的
// 显示文字是不是藏着另一个网址（#169 那道防钓鱼）。

export default function externalLinkPolicyTest() {
  describe('ExternalLinkPolicy', () => {
    it('默认是直接打开——加设置之前就是这个行为', 0, (): void => {
      expect(EXT_LINK_DEFAULT).assertEqual(EXT_LINK_OPEN);
      expect(externalLinkDecision(EXT_LINK_DEFAULT, false)).assertEqual(EXT_LINK_OPEN);
    });

    it('认不出来的取值回默认，不能把链接点死', 0, (): void => {
      expect(normalizeExternalLinkPolicy('')).assertEqual(EXT_LINK_DEFAULT);
      expect(normalizeExternalLinkPolicy('whatever')).assertEqual(EXT_LINK_DEFAULT);
      expect(externalLinkDecision('whatever', false)).assertEqual(EXT_LINK_OPEN);
    });

    it('三档各自原样生效', 0, (): void => {
      expect(externalLinkDecision(EXT_LINK_OPEN, false)).assertEqual(EXT_LINK_OPEN);
      expect(externalLinkDecision(EXT_LINK_COPY, false)).assertEqual(EXT_LINK_COPY);
      expect(externalLinkDecision(EXT_LINK_ASK, false)).assertEqual(EXT_LINK_ASK);
    });

    // 这条是这个模块存在的理由：设置不能给钓鱼链接开直通车。
    it('藏链把「直接打开」提级成弹窗', 0, (): void => {
      expect(externalLinkDecision(EXT_LINK_OPEN, true)).assertEqual(EXT_LINK_ASK);
      expect(externalLinkDecision(EXT_LINK_ASK, true)).assertEqual(EXT_LINK_ASK);
    });

    // 复制不出网，是三档里最安全的，所以藏链也不必提级——提了反而多一道无谓的窗。
    it('藏链不提级「复制」', 0, (): void => {
      expect(externalLinkDecision(EXT_LINK_COPY, true)).assertEqual(EXT_LINK_COPY);
    });
  });
}
