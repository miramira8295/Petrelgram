import { describe, it, expect } from '@ohos/hypium';
import { shouldOfferFullscreenEdit } from '../main/ets/util/composerExpand';

function repeat(ch: string, n: number): string {
  let s: string = '';
  for (let i = 0; i < n; i++) { s += ch; }
  return s;
}

export default function composerExpandTest() {
  describe('composerExpand', () => {
    it('短的单行不出入口', 0, (): void => {
      expect(shouldOfferFullscreenEdit('', 0)).assertFalse();
      expect(shouldOfferFullscreenEdit('好的', 1)).assertFalse();
      expect(shouldOfferFullscreenEdit(repeat('a', 119), 1)).assertFalse();
    });

    it('字数到阈值就出', 0, (): void => {
      expect(shouldOfferFullscreenEdit(repeat('a', 120), 1)).assertTrue();
    });

    it('折了三行就出（已量到行数）', 0, (): void => {
      expect(shouldOfferFullscreenEdit('abc', 3)).assertTrue();
      expect(shouldOfferFullscreenEdit('abc', 2)).assertFalse();
    });

    it('行数还没量到时按换行符兜底', 0, (): void => {
      expect(shouldOfferFullscreenEdit('a\nb\nc', 0)).assertTrue();
      expect(shouldOfferFullscreenEdit('a\nb', 0)).assertFalse();
    });
  });
}
