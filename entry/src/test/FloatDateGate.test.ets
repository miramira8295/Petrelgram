import { describe, it, expect } from '@ohos/hypium';
import {
  floatDateNeedsRescan, floatDateShouldRearm, firstRowBelowChrome,
  floatDateScrollMovedEnough, FLOAT_DATE_RESCAN_SCROLL_VP,
  FLOAT_DATE_HIDE_MS, FLOAT_DATE_REARM_MS, FLOAT_DATE_CHROME_SKIP_MAX
} from '../main/ets/util/floatDateGate';

export default function floatDateGateTest() {
  describe('firstRowBelowChrome', () => {
    // 行高 40，chrome 高 100：第 0 行 0..40、第 1 行 40..80 都整行藏在顶栏后面，
    // 第 2 行 80..120 露出来一截。
    const bottomOf = (index: number): number => (index + 1) * 40;

    it('整行藏在浮动顶栏后面的行不算，报第一行露出来的（issue #163）', 0, (): void => {
      expect(firstRowBelowChrome(0, 50, 100, bottomOf)).assertEqual(2);
    });

    it('第一行本来就露着就原样返回', 0, (): void => {
      expect(firstRowBelowChrome(5, 50, 100, (index: number): number => 100 + (index - 5 + 1) * 40))
        .assertEqual(5);
    });

    it('量不到（NaN）按看得见处理，停在当前行', 0, (): void => {
      expect(firstRowBelowChrome(3, 50, 100, (): number => Number.NaN)).assertEqual(3);
    });

    it('最多往下试几行，且不越过最后一行', 0, (): void => {
      expect(firstRowBelowChrome(0, 50, 10000, bottomOf)).assertEqual(FLOAT_DATE_CHROME_SKIP_MAX);
      expect(firstRowBelowChrome(0, 2, 10000, bottomOf)).assertEqual(1);
    });
  });

  describe('floatDateNeedsRescan', () => {
    it('顶行没变就不重扫：onDidScroll 每帧都来，这是主要的省法', 0, (): void => {
      expect(floatDateNeedsRescan(12, 12)).assertFalse();
    });

    it('顶行变了才扫 groups 算日期', 0, (): void => {
      expect(floatDateNeedsRescan(13, 12)).assertTrue();
      expect(floatDateNeedsRescan(11, 12)).assertTrue();
    });

    it('刚隐藏复位过（记的下标是 -1）一律重扫', 0, (): void => {
      // 隐藏定时器烧到底会把下标复位成 -1，下一次滑动必须重新点亮。
      expect(floatDateNeedsRescan(0, -1)).assertTrue();
      expect(floatDateNeedsRescan(12, -1)).assertTrue();
    });
  });

  describe('floatDateShouldRearm', () => {
    it('还没上过定时器就直接上', 0, (): void => {
      expect(floatDateShouldRearm(10000, 0)).assertTrue();
    });

    it('不到 180ms 不续期：省掉每帧一次的定时器建/拆', 0, (): void => {
      expect(floatDateShouldRearm(10000, 10000)).assertFalse();
      expect(floatDateShouldRearm(10000 + FLOAT_DATE_REARM_MS - 1, 10000)).assertFalse();
    });

    it('满 180ms 就续期——长按拖住不放时日期条要一直亮着', 0, (): void => {
      expect(floatDateShouldRearm(10000 + FLOAT_DATE_REARM_MS, 10000)).assertTrue();
      expect(floatDateShouldRearm(10000 + 500, 10000)).assertTrue();
    });

    it('续期间隔必须远小于隐藏时长，否则拖着拖着自己灭了', 0, (): void => {
      expect(FLOAT_DATE_REARM_MS < FLOAT_DATE_HIDE_MS).assertTrue();
    });
  
  // 【issue #163 的另一半】早退闸原来只拿 start（系统上报的顶行下标）当键，
  // 而 start 在顶行的整段行程里恒定 —— 这期间那一行会滑到标题栏底下，
  // chrome 跳过的结果本该跟着变，却被冻在区间开头那一帧的答案上。
  // 位移判据就是补上"现象真正的自变量"。
  describe('floatDateScrollMovedEnough', () => {
    it('位移不够时不重算（那道省布局查询的闸要保住）', 0, () => {
      expect(floatDateScrollMovedEnough(0)).assertFalse();
      expect(floatDateScrollMovedEnough(FLOAT_DATE_RESCAN_SCROLL_VP - 1)).assertFalse();
    });

    it('位移到阈值就重算', 0, () => {
      expect(floatDateScrollMovedEnough(FLOAT_DATE_RESCAN_SCROLL_VP)).assertTrue();
      expect(floatDateScrollMovedEnough(FLOAT_DATE_RESCAN_SCROLL_VP + 100)).assertTrue();
    });

    // 上翻下翻都算数：往回滚同样会让顶行相对标题栏的位置变化。
    it('取绝对值，两个方向对称', 0, () => {
      expect(floatDateScrollMovedEnough(-FLOAT_DATE_RESCAN_SCROLL_VP)).assertTrue();
      expect(floatDateScrollMovedEnough(-(FLOAT_DATE_RESCAN_SCROLL_VP - 1))).assertFalse();
    });

    // 钉语义不钉数值：阈值要明显小于一行（否则一行滑过半截还不重算，
    // 问题照旧），也不能小到退化成每帧都量（那道闸就白加了）。
    it('阈值落在"明显小于一行、又不是每帧"的区间里', 0, () => {
      expect(FLOAT_DATE_RESCAN_SCROLL_VP > 4).assertTrue();
      expect(FLOAT_DATE_RESCAN_SCROLL_VP < 40).assertTrue();
    });
  });
});
}
