import { describe, it, expect } from '@ohos/hypium';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdObject, TdBridge } from '../main/ets/tdkit/TdTypes';
import {
  TranslatedText, TranslationService, looksLikeTargetLanguage
} from '../main/ets/services/TranslationService';

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

function answer(
  b: FakeBridge, extra: string, text: string, entities: TdObject[] = []
): void {
  const res: TdObject = { '@type': 'formattedText' };
  res['text'] = text;
  res['entities'] = entities;
  res['@extra'] = extra;
  b.onReceive(JSON.stringify(res));
}

// translateMessageText 回的是 formattedText，实体和文本是一对。
function quoteEntity(offset: number, length: number): TdObject {
  const type: TdObject = { '@type': 'textEntityTypeExpandableBlockQuote' };
  const e: TdObject = { '@type': 'textEntity' };
  e['offset'] = offset;
  e['length'] = length;
  e['type'] = type;
  return e;
}

export default function translationServiceTest() {
  describe('TranslationService', () => {
    it('translates_and_caches_per_content_version', 0, async () => {
      const arr = setup(); const b = arr[0] as FakeBridge; const svc = arr[1] as TranslationService;
      let got: TranslatedText | null = null;
      svc.request(5, 100, 0, 'zh', (r: TranslatedText | null): void => { got = r; });
      answer(b, pendingTranslateRequests(b)[0], '你好');
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      expect((got as TranslatedText | null)?.text ?? '').assertEqual('你好');
      expect(svc.cached(5, 100, 0, 'zh')?.text ?? '').assertEqual('你好');
      // Same content version again: served from cache, no second TDLib call.
      let again: TranslatedText | null = null;
      svc.request(5, 100, 0, 'zh', (r: TranslatedText | null): void => { again = r; });
      expect((again as TranslatedText | null)?.text ?? '').assertEqual('你好');
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

    // 2026-09-10 用户报「翻译后可折叠引用被强制展开、样式被破坏」：服务只取了
    // formattedText 的 text，entities 整个扔掉，译文于是变成没有任何结构的白板。
    // 折叠态是 textEntityTypeExpandableBlockQuote 撑着的，实体丢了就没得折叠。
    it('carries_entities_alongside_the_translated_text', 0, async () => {
      const arr = setup(); const b = arr[0] as FakeBridge; const svc = arr[1] as TranslationService;
      let got: TranslatedText | null = null;
      svc.request(9, 200, 0, 'zh', (r: TranslatedText | null): void => { got = r; });
      answer(b, pendingTranslateRequests(b)[0], '标题\n引用正文', [quoteEntity(3, 4)]);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      const done = got as TranslatedText | null;
      expect(done?.entities.length ?? 0).assertEqual(1);
      const type = done?.entities[0]['type'] as TdObject;
      expect(type['@type'] as string).assertEqual('textEntityTypeExpandableBlockQuote');
      // 缓存命中那一路也要带着实体，否则第二次上屏又变白板。
      expect(svc.cached(9, 200, 0, 'zh')?.entities.length ?? 0).assertEqual(1);
    });

    // 2026-09-10 真机回归：一条"中文标题 + 六条短链"的机器人消息被判成拉丁文，
    // 白翻一遍，还把消息样式冲掉。URL 里的 165 个拉丁字母把汉字占比压到 0.26。
    it('links_do_not_vote_in_the_script_census', 0, () => {
      // 形状照搬真机那条（中文标题 + 四条长链），但链接换成 example 域名——
      // 判据只看"拉丁字符压过汉字"这个比例，没必要把第三方推广地址写进仓库。
      const withLinks: string =
        '中文标题：这条消息本身是中文，但正文里塞满了链接\n' +
        '【资源一】https://example.com/a-fairly-long-path\n' +
        '【资源二】https://www.example.org/another-long-path\n' +
        '【资源三】https://cdn.example.net/channel/AbCdEfGhIjKlMnOpQrStUv/join\n' +
        '【资源四】https://example.com/xYzAbC';
      // 没有实体也要靠正则兜底认出来。
      expect(looksLikeTargetLanguage(withLinks, 'zh')).assertTrue();
      // 有实体时走实体，结论一致。
      const ents: TdObject[] = [];
      let at: number = withLinks.indexOf('https://');
      while (at >= 0) {
        let end: number = withLinks.indexOf('\n', at);
        if (end < 0) { end = withLinks.length; }
        const type: TdObject = { '@type': 'textEntityTypeUrl' };
        const e: TdObject = { '@type': 'textEntity' };
        e['offset'] = at;
        e['length'] = end - at;
        e['type'] = type;
        ents.push(e);
        at = withLinks.indexOf('https://', end);
      }
      expect(ents.length).assertEqual(4);
      expect(looksLikeTargetLanguage(withLinks, 'zh', ents)).assertTrue();
      // 摘链接不能把"真的是外文"也一并放过：正文换成英文就该继续翻。
      const englishBody: string =
        'Free setup guide for everyone\nMore: https://example.com/a-fairly-long-path';
      expect(looksLikeTargetLanguage(englishBody, 'zh')).assertFalse();
      // 纯链接消息没什么可翻的。
      expect(looksLikeTargetLanguage('https://example.com/23618.html', 'zh')).assertTrue();
    });
  });
}
