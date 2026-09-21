import { describe, it, expect } from '@ohos/hypium';
import { composerLineProbe, COMPOSER_PROBE_MAX_CHARS } from '../main/ets/util/composerLineProbe';

export default function composerLineProbeTest() {
  describe('ComposerLineProbe', () => {
    // issue #209 的核心：草稿为空时画的是 placeholder，而 placeholder 里塞的是
    // 「<昵称> 正在输入…」。量 'A' 量不到昵称里的高字符。
    it('草稿为空时量 placeholder', 0, () => {
      expect(composerLineProbe('', 'हिन्दी 正在输入…')).assertEqual('हिन्दी 正在输入…');
    });

    it('草稿非空时量草稿——那时 placeholder 根本不显示', 0, () => {
      expect(composerLineProbe('hello', '某人 正在输入…')).assertEqual('hello');
    });

    it('两者都空时返回空串，调用方拿 A 的高度兜底', 0, () => {
      expect(composerLineProbe('', '')).assertEqual('');
    });

    // 要的是"一行有多高"。带换行的草稿若整段去量，measureTextSize 返回的是多行
    // 高度，再乘以行数就错得离谱。
    it('只取第一行', 0, () => {
      expect(composerLineProbe('first\nsecond\nthird', 'p')).assertEqual('first');
      expect(composerLineProbe('\nsecond', 'p')).assertEqual('');
      expect(composerLineProbe('', 'a\nb')).assertEqual('a');
    });

    it('超长按上限截断：行高只取决于出现了哪些字形，不取决于有多少个', 0, () => {
      const long: string = 'x'.repeat(500);
      expect(composerLineProbe(long, '').length).assertEqual(COMPOSER_PROBE_MAX_CHARS);
    });

    it('恰好等于上限时不截断', 0, () => {
      const exact: string = 'y'.repeat(COMPOSER_PROBE_MAX_CHARS);
      expect(composerLineProbe(exact, '')).assertEqual(exact);
    });

    it('截断发生在取第一行之后，不会把换行符带进来', 0, () => {
      const probe: string = composerLineProbe('a'.repeat(100) + '\n' + 'b'.repeat(100), '');
      expect(probe.indexOf('\n')).assertEqual(-1);
      expect(probe.length).assertEqual(COMPOSER_PROBE_MAX_CHARS);
    });

    it('自定义上限生效；非正数回落到默认值', 0, () => {
      expect(composerLineProbe('abcdef', '', 3)).assertEqual('abc');
      expect(composerLineProbe('z'.repeat(200), '', 0).length).assertEqual(COMPOSER_PROBE_MAX_CHARS);
      expect(composerLineProbe('z'.repeat(200), '', -5).length).assertEqual(COMPOSER_PROBE_MAX_CHARS);
    });

    it('同一段文字反复调用结果稳定——调用方拿它当缓存键', 0, () => {
      const a: string = composerLineProbe('', 'ไทย 正在输入…');
      const b: string = composerLineProbe('', 'ไทย 正在输入…');
      expect(a).assertEqual(b);
    });
  });
}
