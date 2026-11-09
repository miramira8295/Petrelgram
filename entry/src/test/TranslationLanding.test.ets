import { describe, it, expect } from '@ohos/hypium';
import {
  TranslationPresentation, translationLanded
} from '../main/ets/util/translationLanding';

// 「这次旁路更新是不是译文到货」。messageRowPresentationChannel 是所有展示态
// 更新的公共通道（下载完成、缩略图路径、发送态都走它），给译文加动画时必须
// 只认译文这一维——否则一次下载进度跳动也会让气泡跟着动一下。

function p(text: string, hidden: boolean = false): TranslationPresentation {
  return { text: text, hidden: hidden };
}

export default function translationLandingTest() {
  describe('translationLanding', () => {

    it('译文从无到有 → 要动画', 0, (): void => {
      expect(translationLanded(p(''), p('你好'))).assertTrue();
    });

    it('译文被撤掉 → 也要动画（气泡要缩回去）', 0, (): void => {
      expect(translationLanded(p('你好'), p(''))).assertTrue();
    });

    it('折叠/展开译文 → 要动画', 0, (): void => {
      expect(translationLanded(p('你好', false), p('你好', true))).assertTrue();
      expect(translationLanded(p('你好', true), p('你好', false))).assertTrue();
    });

    it('重新翻译成另一种语言 → 要动画', 0, (): void => {
      expect(translationLanded(p('你好'), p('Hello'))).assertTrue();
    });

    it('译文没变 → 不动画（下载进度那类更新走的是同一条通道）', 0, (): void => {
      expect(translationLanded(p('你好'), p('你好'))).assertFalse();
      expect(translationLanded(p(''), p(''))).assertFalse();
      expect(translationLanded(p('你好', true), p('你好', true))).assertFalse();
    });
  });
}
