import { describe, it, expect } from '@ohos/hypium';
import { TranslationStatus, TranslationStatusHub } from '../main/ets/util/translationChannel';

// 翻译瞬时态（「翻译中」「翻译失败」）的滑动闸。
//
// 背景（2026-09-14 真机）：瞬时态会让气泡多出/少掉一行，行高一变 List 就要重排
// 整个可视窗口。滑动中网络请求陆续回来，气泡"长高又缩回"，整屏跟着重测。
// 闸的语义：滑动时**不通知已挂着的气泡**（每条只攒最终态），停稳后一次放出；
// 真实状态照常记账，新挂上来的行直接读到它，不受闸影响。
function phaseOf(s: TranslationStatus | null): string {
  return s === null ? 'none' : s.phase;
}

export default function translationStatusHubTest(): void {
  describe('translationStatusHub', (): void => {
    it('没有闸时照旧立即通知', 0, (): void => {
      const hub: TranslationStatusHub = new TranslationStatusHub();
      let seen: string = '';
      hub.subscribe(1, (s: TranslationStatus | null): void => { seen = phaseOf(s); });
      hub.publishTranslating(1);
      expect(seen).assertEqual('loading');
    });

    it('闸的谓词为假（没在滑动）时也照旧立即通知', 0, (): void => {
      const hub: TranslationStatusHub = new TranslationStatusHub();
      hub.pushHold((): boolean => false);
      let seen: string = '';
      hub.subscribe(1, (s: TranslationStatus | null): void => { seen = phaseOf(s); });
      hub.publishTranslating(1);
      expect(seen).assertEqual('loading');
    });

    it('闸住时不通知气泡，但真实状态照常记账（新挂上的行读得到）', 0, (): void => {
      const hub: TranslationStatusHub = new TranslationStatusHub();
      hub.pushHold((): boolean => true);
      let calls: number = 0;
      hub.subscribe(1, (_s: TranslationStatus | null): void => { calls++; });
      hub.publishTranslating(1);
      expect(calls).assertEqual(0);
      expect(phaseOf(hub.statusFor(1))).assertEqual('loading');
    });

    it('闸住期间长高又缩回（loading → 清除），放出时每条只通知一次、给最终态', 0, (): void => {
      const hub: TranslationStatusHub = new TranslationStatusHub();
      hub.pushHold((): boolean => true);
      const seen: string[] = [];
      hub.subscribe(7, (s: TranslationStatus | null): void => { seen.push(phaseOf(s)); });
      hub.publishTranslating(7);
      hub.clear(7);
      hub.flushHeld();
      expect(seen.length).assertEqual(1);
      expect(seen[0]).assertEqual('none');
    });

    it('失败态同样被攒住，放出时带着原始报错', 0, (): void => {
      const hub: TranslationStatusHub = new TranslationStatusHub();
      hub.pushHold((): boolean => true);
      let last: TranslationStatus | null = null;
      let calls: number = 0;
      hub.subscribe(3, (s: TranslationStatus | null): void => { last = s; calls++; });
      hub.publishFailed(3, 'FLOOD');
      expect(calls).assertEqual(0);
      hub.flushHeld();
      expect(calls).assertEqual(1);
      expect(phaseOf(last)).assertEqual('failed');
      expect((last as TranslationStatus | null)?.error ?? '').assertEqual('FLOOD');
    });

    it('摘掉闸时立刻放出攒着的变化', 0, (): void => {
      const hub: TranslationStatusHub = new TranslationStatusHub();
      const release: () => void = hub.pushHold((): boolean => true);
      let seen: string = '';
      hub.subscribe(5, (s: TranslationStatus | null): void => { seen = phaseOf(s); });
      hub.publishTranslating(5);
      expect(seen).assertEqual('');
      release();
      expect(seen).assertEqual('loading');
      expect(hub.heldCount()).assertEqual(0);
    });

    it('两层闸只看最上层；摘掉上层后下层接管（叠页场景）', 0, (): void => {
      const hub: TranslationStatusHub = new TranslationStatusHub();
      let lowerMoving: boolean = false;
      hub.pushHold((): boolean => lowerMoving);
      const releaseTop: () => void = hub.pushHold((): boolean => false);
      let calls: number = 0;
      hub.subscribe(9, (_s: TranslationStatus | null): void => { calls++; });
      lowerMoving = true;
      hub.publishTranslating(9);
      expect(calls).assertEqual(1);   // 上层没在动，下层在动也不算
      releaseTop();
      hub.clear(9);
      expect(calls).assertEqual(1);   // 现在下层接管，它在动 → 攒住
      hub.flushHeld();
      expect(calls).assertEqual(2);
    });

    it('攒着期间退订的气泡，放出时不会被通知', 0, (): void => {
      const hub: TranslationStatusHub = new TranslationStatusHub();
      hub.pushHold((): boolean => true);
      let calls: number = 0;
      const off: () => void = hub.subscribe(4, (_s: TranslationStatus | null): void => { calls++; });
      hub.publishTranslating(4);
      off();
      hub.flushHeld();
      expect(calls).assertEqual(0);
      expect(hub.heldCount()).assertEqual(0);
    });

    it('没有变化时放出是空操作', 0, (): void => {
      const hub: TranslationStatusHub = new TranslationStatusHub();
      hub.pushHold((): boolean => true);
      let calls: number = 0;
      hub.subscribe(2, (_s: TranslationStatus | null): void => { calls++; });
      hub.flushHeld();
      expect(calls).assertEqual(0);
    });
  });
}
