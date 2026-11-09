import { describe, expect, it } from '@ohos/hypium';
import { TdLanguageSync, telegramLanguageId } from '../main/ets/util/tdLanguageSync';
import { reportDisplayText } from '../main/ets/util/reportLabels';
import { TdObject, TdRequest } from '../main/ets/tdkit/TdTypes';

class LanguagePending {
  resolve: (value: TdObject) => void = (): void => {};
  reject: (error: Error) => void = (): void => {};
  promise: Promise<TdObject> = new Promise<TdObject>((resolve, reject): void => {
    this.resolve = resolve; this.reject = reject;
  });
}
class LanguageHarness {
  sent: TdRequest[] = [];
  pending: LanguagePending[] = [];
  sync: TdLanguageSync = new TdLanguageSync((req: TdRequest): Promise<TdObject> => {
    this.sent.push(req);
    const pending: LanguagePending = new LanguagePending();
    this.pending.push(pending);
    return pending.promise;
  });
  ok(index: number): void { this.pending[index].resolve({ '@type': 'ok' }); }
  value(index: number): string { return (this.sent[index]['value'] as TdObject)['value'] as string; }
}
async function flushLanguage(): Promise<void> {
  for (let i: number = 0; i < 12; i++) { await Promise.resolve(); }
}

export default function tdLanguageTest(): void {
  describe('TdLanguage', (): void => {
    it('maps_scripts_and_regions_to_telegram_chinese_packs', 0, (): void => {
      expect(telegramLanguageId('zh-Hans-CN')).assertEqual('zh-hans');
      expect(telegramLanguageId('zh-Hant-TW')).assertEqual('zh-hant');
      expect(telegramLanguageId('zh_HK')).assertEqual('zh-hant');
      expect(telegramLanguageId('zh-MO')).assertEqual('zh-hant');
      expect(telegramLanguageId('zh-Hans-HK')).assertEqual('zh-hans');
      expect(telegramLanguageId('zh-CN')).assertEqual('zh-hans');
    });
    it('maps_supported_locales_and_rejects_arbitrary_pack_identifiers', 0, (): void => {
      expect(telegramLanguageId('en-US')).assertEqual('en');
      expect(telegramLanguageId('pt-BR')).assertEqual('pt');
      expect(telegramLanguageId('ru-RU')).assertEqual('ru');
      expect(telegramLanguageId('ja')).assertEqual('ja');
      expect(telegramLanguageId('unknown')).assertEqual('en');
      expect(telegramLanguageId('')).assertEqual('en');
    });
    it('sets_target_before_language_and_deduplicates_same_language', 0, async (): Promise<void> => {
      const h: LanguageHarness = new LanguageHarness();
      const work: Promise<void> = h.sync.sync('en-US');
      expect(h.sent[0]['name']).assertEqual('localization_target');
      expect(h.value(0)).assertEqual('tdesktop');
      expect(h.sent.length).assertEqual(1);
      h.ok(0); await flushLanguage();
      expect(h.sent[1]['name']).assertEqual('language_pack_id');
      expect(h.value(1)).assertEqual('en');
      h.ok(1); await work;
      await h.sync.sync('en-GB');
      expect(h.sent.length).assertEqual(2);
    });
    it('coalesces_changes_while_initial_target_is_pending', 0, async (): Promise<void> => {
      const h: LanguageHarness = new LanguageHarness();
      const first: Promise<void> = h.sync.sync('en');
      const second: Promise<void> = h.sync.sync('zh-Hant');
      h.ok(0); await flushLanguage();
      expect(h.value(1)).assertEqual('zh-hant');
      h.ok(1); await first; await second;
      expect(h.sent.length).assertEqual(2);
    });
    it('serializes_rapid_switches_and_waits_until_latest_language_is_applied', 0, async (): Promise<void> => {
      const h: LanguageHarness = new LanguageHarness();
      const first: Promise<void> = h.sync.sync('en');
      h.ok(0); await flushLanguage();
      const second: Promise<void> = h.sync.sync('zh-Hans');
      const third: Promise<void> = h.sync.sync('de');
      expect(h.sent.length).assertEqual(2);
      h.ok(1); await flushLanguage();
      expect(h.value(2)).assertEqual('de');
      h.ok(2); await first; await second; await third;
      expect(h.sent.length).assertEqual(3);
    });
    it('target_failure_is_retried_on_next_trigger', 0, async (): Promise<void> => {
      const h: LanguageHarness = new LanguageHarness();
      const first: Promise<boolean> = h.sync.sync('en').then((): boolean => true).catch((): boolean => false);
      h.pending[0].reject(new Error('timeout'));
      expect(await first).assertFalse();
      const retry: Promise<void> = h.sync.sync('en');
      expect(h.sent[1]['name']).assertEqual('localization_target');
      h.ok(1); await flushLanguage();
      h.ok(2); await retry;
    });
    it('language_failure_does_not_cache_success_or_repeat_completed_target', 0, async (): Promise<void> => {
      const h: LanguageHarness = new LanguageHarness();
      const first: Promise<boolean> = h.sync.sync('en').then((): boolean => true).catch((): boolean => false);
      h.ok(0); await flushLanguage();
      h.pending[1].reject(new Error('timeout'));
      expect(await first).assertFalse();
      const retry: Promise<void> = h.sync.sync('fr');
      expect(h.sent[2]['name']).assertEqual('language_pack_id');
      expect(h.value(2)).assertEqual('fr');
      h.ok(2); await retry;
    });
    it('detached_runtime_does_not_continue_after_late_target_ack', 0, async (): Promise<void> => {
      const h: LanguageHarness = new LanguageHarness();
      const work: Promise<void> = h.sync.sync('en');
      h.sync.stop(); h.ok(0); await work;
      await h.sync.sync('zh-Hans');
      expect(h.sent.length).assertEqual(1);
    });
    it('new_account_has_its_own_target_and_language_state', 0, async (): Promise<void> => {
      const old: LanguageHarness = new LanguageHarness();
      const first: Promise<void> = old.sync.sync('en');
      old.ok(0); await flushLanguage(); old.ok(1); await first;
      old.sync.stop();
      const next: LanguageHarness = new LanguageHarness();
      const second: Promise<void> = next.sync.sync('en');
      expect(next.sent[0]['name']).assertEqual('localization_target');
      next.ok(0); await flushLanguage(); next.ok(1); await second;
      expect(next.sent.length).assertEqual(2);
    });
    it('same_tick_change_after_cached_sync_is_not_lost', 0, async (): Promise<void> => {
      const h: LanguageHarness = new LanguageHarness();
      const first: Promise<void> = h.sync.sync('en');
      h.ok(0); await flushLanguage(); h.ok(1); await first;
      const cached: Promise<void> = h.sync.sync('en');
      const change: Promise<void> = h.sync.sync('ja');
      expect(h.value(2)).assertEqual('ja');
      h.ok(2); await cached; await change;
    });
  });
  describe('ReportLabels', (): void => {
    it('known_english_labels_use_current_local_resource', 0, (): void => {
      expect(reportDisplayText('Spam', (key: string): string => `zh:${key}`)).assertEqual('zh:rf_reason_spam');
      expect(reportDisplayText('Spam', (key: string): string => `de:${key}`)).assertEqual('de:rf_reason_spam');
      expect(reportDisplayText('  Child Abuse ', (key: string): string => key)).assertEqual('rf_reason_child_abuse');
    });
    it('unknown_or_already_localized_server_labels_are_preserved_exactly', 0, (): void => {
      const translate = (_key: string): string => 'wrong';
      expect(reportDisplayText('New category', translate)).assertEqual('New category');
      expect(reportDisplayText('版权问题', translate)).assertEqual('版权问题');
      expect(reportDisplayText('Spam involving something else', translate)).assertEqual('Spam involving something else');
    });
    it('known_titles_localize_without_overwriting_unknown_substep_questions', 0, (): void => {
      const translate = (key: string): string => key;
      expect(reportDisplayText('', translate, true)).assertEqual('cpp_report_reason');
      expect(reportDisplayText('Choose a reason', translate, true)).assertEqual('cpp_report_reason');
      expect(reportDisplayText('Report', translate, true)).assertEqual('mb_report');
      expect(reportDisplayText('Which law does this violate?', translate, true)).assertEqual('Which law does this violate?');
    });
  });
}
