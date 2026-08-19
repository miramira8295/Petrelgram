import { describe, expect, it } from '@ohos/hypium';
import { TdObject } from '../main/ets/tdkit/TdTypes';
import { FlatText, flattenRichMessage } from '../main/ets/util/richMessage';

function plain(text: string): TdObject {
  const o: TdObject = { '@type': 'richTextPlain' };
  o['text'] = text;
  return o;
}

function wrap(type: string, inner: TdObject): TdObject {
  const o: TdObject = { '@type': type };
  o['text'] = inner;
  return o;
}

function para(inner: TdObject): TdObject {
  const o: TdObject = { '@type': 'pageBlockParagraph' };
  o['text'] = inner;
  return o;
}

function message(blocks: TdObject[]): TdObject {
  const m: TdObject = { '@type': 'richMessage' };
  m['blocks'] = blocks;
  const c: TdObject = { '@type': 'messageRichMessage' };
  c['message'] = m;
  return c;
}

function typeOf(e: TdObject): string {
  const t = e['type'] as TdObject;
  return t['@type'] as string;
}

// 摊平的两条硬要求：文字一个字不能丢，实体偏移必须落在对应的那段字上。
export default function richMessageTest() {
  describe('richMessage', () => {
    it('段落之间用换行隔开，首段前不留空行', 0, () => {
      const f: FlatText = flattenRichMessage(message([para(plain('一')), para(plain('二'))]));
      expect(f.text).assertEqual('一\n二');
    });

    it('标题块整段加粗', 0, () => {
      const h: TdObject = { '@type': 'pageBlockSectionHeading' };
      h['text'] = plain('问题');
      const f: FlatText = flattenRichMessage(message([h]));
      expect(f.text).assertEqual('问题');
      expect(f.entities.length).assertEqual(1);
      expect(typeOf(f.entities[0])).assertEqual('textEntityTypeBold');
      expect(f.entities[0]['offset'] as number).assertEqual(0);
      expect(f.entities[0]['length'] as number).assertEqual(2);
    });

    it('richTexts 逐段拼接，样式偏移落在自己那段上', 0, () => {
      const runs: TdObject = { '@type': 'richTexts' };
      runs['texts'] = [plain('图片是 '), wrap('richTextBold', plain('编号')), plain(' 的封面')];
      const f: FlatText = flattenRichMessage(message([para(runs)]));
      expect(f.text).assertEqual('图片是 编号 的封面');
      expect(f.entities.length).assertEqual(1);
      expect(f.entities[0]['offset'] as number).assertEqual(4);
      expect(f.entities[0]['length'] as number).assertEqual(2);
    });

    it('链接带上 url', 0, () => {
      const link: TdObject = { '@type': 'richTextUrl' };
      link['text'] = plain('站点');
      link['url'] = 'https://example.com';
      const f: FlatText = flattenRichMessage(message([para(link)]));
      expect(typeOf(f.entities[0])).assertEqual('textEntityTypeTextUrl');
      const t = f.entities[0]['type'] as TdObject;
      expect(t['url'] as string).assertEqual('https://example.com');
    });

    it('引用块整段标成 blockquote，内部块照常摊平', 0, () => {
      const q: TdObject = { '@type': 'pageBlockBlockQuote' };
      q['blocks'] = [para(plain('这是什么'))];
      const f: FlatText = flattenRichMessage(message([q]));
      expect(f.text).assertEqual('这是什么');
      expect(typeOf(f.entities[0])).assertEqual('textEntityTypeBlockQuote');
      expect(f.entities[0]['length'] as number).assertEqual(4);
    });

    it('认不出的样式包装不吞掉里面的文字', 0, () => {
      const f: FlatText = flattenRichMessage(
        message([para(wrap('richTextSomethingNew', plain('照样显示')))]));
      expect(f.text).assertEqual('照样显示');
    });

    it('实体按偏移升序、同偏移时外层在前', 0, () => {
      const q: TdObject = { '@type': 'pageBlockBlockQuote' };
      const runs: TdObject = { '@type': 'richTexts' };
      runs['texts'] = [wrap('richTextBold', plain('甲')), plain('乙')];
      q['blocks'] = [para(runs)];
      const f: FlatText = flattenRichMessage(message([q]));
      // 引用块覆盖 0..2，内部加粗覆盖 0..1：外层必须排在前面。
      expect(typeOf(f.entities[0])).assertEqual('textEntityTypeBlockQuote');
      expect(f.entities[0]['length'] as number).assertEqual(2);
      expect(typeOf(f.entities[1])).assertEqual('textEntityTypeBold');
      expect(f.entities[1]['length'] as number).assertEqual(1);
    });

    it('没有可显示的文字时返回空串，调用方退回兜底', 0, () => {
      const f: FlatText = flattenRichMessage(message([]));
      expect(f.text).assertEqual('');
      expect(f.entities.length).assertEqual(0);
    });
  });
}
