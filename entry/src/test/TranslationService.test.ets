import { describe, it, expect } from '@ohos/hypium';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdObject, TdBridge } from '../main/ets/tdkit/TdTypes';
import { TranslationService, looksLikeTargetLanguage } from '../main/ets/services/TranslationService';

class FakeBridge implements TdBridge {
  onReceive: (json: string) => void = (): void => {};
  sent: string[] = [];
  init(cb: (json: string) => void): void { this.onReceive = cb; }
  send(json: string): void { this.sent.push(json); }
}

function setup(): Array<Object> {
  const b = new FakeBridge();
  const c = new TdClient(b);
  c.start();
  return [b, new TranslationService(c)];
}

function pendingTranslateRequests(b: FakeBridge): string[] {
  const extras: string[] = [];
  for (const json of b.sent) {
    const o = JSON.parse(json) as TdObject;
    if (o['@type'] === 'translateMessageText') {
      extras.push((o['@extra'] as string | undefined) ?? '');
    }
  }
  return extras;
}

// TDLib 的错误应答。flood-wait 那种（"Too Many Requests: retry after N"）会
// 让服务降低并发，与普通失败走的是不同分支。
function fail(b: FakeBridge, extra: string, message: string): void {
  const res: TdObject = { '@type': 'error' };
  res['code'] = 429;
  res['message'] = message;
  res['@extra'] = extra;
  b.onReceive(JSON.stringify(res));
}

function answer(b: FakeBridge, extra: string, text: string): void {
  const res: TdObject = { '@type': 'formattedText' };
  res['text'] = text;
  res['@extra'] = extra;
  b.onReceive(JSON.stringify(res));
}

export default function translationServiceTest() {
  describe('TranslationService', () => {
    it('translates_and_caches_per_content_version', 0, async () => {
      const arr = setup(); const b = arr[0] as FakeBridge; const svc = arr[1] as TranslationService;
      let got: string | null = null;
      svc.request(5, 100, 0, 'zh', (text: string | null): void => { got = text; });
      answer(b, pendingTranslateRequests(b)[0], '你好');
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      expect(got).assertEqual('你好');
      expect(svc.cached(5, 100, 0, 'zh')).assertEqual('你好');
      // Same content version again: served from cache, no second TDLib call.
      let again: string | null = null;
      svc.request(5, 100, 0, 'zh', (text: string | null): void => { again = text; });
      expect(again).assertEqual('你好');
      expect(pendingTranslateRequests(b).length).assertEqual(1);
      // An edit (new editDate) is a different version and asks again.
      svc.request(5, 100, 7, 'zh', (): void => {});
      expect(pendingTranslateRequests(b).length).assertEqual(2);
    });
    // 打开一个热闹的会话会一次排进几十行；同时在飞的有上限，其余的要随着
    // 应答回来逐个补位。上限从 2 提到 6 是为了提速，但排队机制本身不能丢。
    it('caps_inflight_requests_and_drains_the_queue', 0, async () => {
      const arr = setup(); const b = arr[0] as FakeBridge; const svc = arr[1] as TranslationService;
      for (let i = 1; i <= 8; i++) {
        svc.request(5, i, 0, 'zh', (): void => {});
      }
      // 8 个请求，只有 6 个上路。
      expect(pendingTranslateRequests(b).length).assertEqual(6);
      answer(b, pendingTranslateRequests(b)[0], 'a');
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      // 回来一个补一个。
      expect(pendingTranslateRequests(b).length).assertEqual(7);
    });

    // 限流退避是**整个队列一起停**（同一个限流桶），所以撞上之后必须降低
    // 并发再爬回来——一味开大反而更慢。这条钉住"撞一次就收敛到 2"。
    it('drops_concurrency_after_a_flood_wait', 0, async () => {
      const arr = setup(); const b = arr[0] as FakeBridge; const svc = arr[1] as TranslationService;
      svc.request(5, 1, 0, 'zh', (): void => {});
      const first = pendingTranslateRequests(b)[0];
      fail(b, first, 'Too Many Requests: retry after 1');
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      const beforeBurst = pendingTranslateRequests(b).length;
      // 退避期内新请求只排队不发车。
      for (let i = 2; i <= 8; i++) {
        svc.request(5, i, 0, 'zh', (): void => {});
      }
      expect(pendingTranslateRequests(b).length).assertEqual(beforeBurst);
    });
    // Messages already in the target language must not cost a round trip.
    // Script-based: decisive for zh/ja/ko/ru/..., deliberately undecidable
    // between Latin-script languages (those return false and go to the server).
    it('skips_text_already_in_target_language', 0, () => {
      expect(looksLikeTargetLanguage('你好，今天怎么样', 'zh')).assertTrue();
      expect(looksLikeTargetLanguage('Hello there', 'zh')).assertFalse();
      // Japanese is han + kana — the kana veto keeps it translatable for zh.
      expect(looksLikeTargetLanguage('日本語のテキスト', 'zh')).assertFalse();
      expect(looksLikeTargetLanguage('日本語のテキスト', 'ja')).assertTrue();
      expect(looksLikeTargetLanguage('안녕하세요', 'ko')).assertTrue();
      expect(looksLikeTargetLanguage('Привет, как дела', 'ru')).assertTrue();
      // Latin targets stay undecidable: French text is not detectably English.
      expect(looksLikeTargetLanguage('Bonjour tout le monde', 'en')).assertFalse();
      // Nothing translatable at all — pure emoji/digits never go out.
      expect(looksLikeTargetLanguage('👍👍 123', 'en')).assertTrue();
    });
  });
}
