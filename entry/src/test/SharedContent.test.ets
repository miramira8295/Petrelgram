import { describe, it, expect } from '@ohos/hypium';
import {
  SharedItem, SharedPayload, SharedRecordLike,
  classifyRecord, extensionOf, itemOf, kindFromAncestor, previewOf, splitPayload,
  ShareHandoff, HANDOFF_VERSION, parseHandoff, serializeHandoff
} from '../main/ets/util/sharedContent';

// 系统分享送进来的 UTD → 我们的发送分类。这一组钉住的核心是
// **任何认不出来的东西都必须退回"当文件发"，绝不丢数据**。

function rec(utd: string, uri: string = '', content: string = ''): SharedRecordLike {
  return { utd: utd, uri: uri, content: content };
}

export default function sharedContentTest() {
  describe('sharedContent', () => {

    // ---- 扩展名 ----

    it('扩展名：普通路径', 0, (): void => {
      expect(extensionOf('/data/a/b.JPG')).assertEqual('jpg');
    });
    it('扩展名：带查询串的内容 URI', 0, (): void => {
      expect(extensionOf('file://media/Photo/1/IMG.png?networkid=x')).assertEqual('png');
    });
    it('扩展名：没有点', 0, (): void => {
      expect(extensionOf('/data/nofile')).assertEqual('');
    });
    it('扩展名：隐藏文件不算扩展名', 0, (): void => {
      expect(extensionOf('/data/.bashrc')).assertEqual('');
    });
    it('扩展名：点在结尾', 0, (): void => {
      expect(extensionOf('/data/a.')).assertEqual('');
    });
    it('扩展名：空串', 0, (): void => {
      expect(extensionOf('')).assertEqual('');
    });

    // ---- 直判 ----

    it('jpeg 判为图片', 0, (): void => {
      expect(classifyRecord(rec('general.jpeg', '/a.jpg'))).assertEqual('image');
    });
    it('mpeg-4 判为视频', 0, (): void => {
      expect(classifyRecord(rec('general.mpeg-4', '/a.mp4'))).assertEqual('video');
    });
    it('mp3 判为音频', 0, (): void => {
      expect(classifyRecord(rec('general.mp3', '/a.mp3'))).assertEqual('audio');
    });
    it('纯文本判为文本', 0, (): void => {
      expect(classifyRecord(rec('general.plain-text', '', '你好'))).assertEqual('text');
    });
    it('超链接判为链接', 0, (): void => {
      expect(classifyRecord(rec('general.hyperlink', '', 'https://a.b'))).assertEqual('link');
    });
    it('pdf 判为文件', 0, (): void => {
      expect(classifyRecord(rec('general.pdf', '/a.pdf'))).assertEqual('file');
    });

    // ---- 退化路径：认不出来也不能丢 ----

    it('完全不认识的 UTD + 认识的扩展名 → 按扩展名', 0, (): void => {
      expect(classifyRecord(rec('com.example.weird', '/x/holiday.mp4'))).assertEqual('video');
    });
    it('完全不认识的 UTD + 不认识的扩展名 → 当文件发', 0, (): void => {
      expect(classifyRecord(rec('com.example.weird', '/x/thing.qqq'))).assertEqual('file');
    });
    it('不认识的 UTD 但能归化到祖先 → 按祖先', 0, (): void => {
      expect(classifyRecord(rec('com.oem.raw', '/x/a.bin'), 'general.image')).assertEqual('image');
    });
    it('祖先表里没有的祖先不影响退化', 0, (): void => {
      expect(classifyRecord(rec('com.oem.raw', '/x/a.bin'), 'general.object')).assertEqual('file');
    });
    it('声称是图片却没有 uri，只有文字 → 当文本发，不丢内容', 0, (): void => {
      expect(classifyRecord(rec('general.image', '', '这其实是文字'))).assertEqual('text');
    });
    it('声称是图片、既没 uri 也没内容 → 当文件（由 itemOf 丢弃）', 0, (): void => {
      expect(classifyRecord(rec('general.image'))).assertEqual('file');
    });

    it('kindFromAncestor 只认已知中间类型', 0, (): void => {
      expect(kindFromAncestor('general.video')).assertEqual('video');
      expect(kindFromAncestor('general.object') === undefined).assertTrue();
    });

    // ---- itemOf ----

    it('空记录被丢弃', 0, (): void => {
      expect(itemOf(rec('general.plain-text')) === null).assertTrue();
    });

    it('文本项不带 uri，正文进 text', 0, (): void => {
      const item: SharedItem = itemOf(rec('general.plain-text', '', 'hi')) as SharedItem;
      expect(item.text).assertEqual('hi');
      expect(item.uri).assertEqual('');
    });

    it('链接只给了 uri 没给 content 时，uri 就是正文', 0, (): void => {
      const item: SharedItem = itemOf(rec('general.hyperlink', 'https://a.b')) as SharedItem;
      expect(item.text).assertEqual('https://a.b');
    });

    it('媒体项不带 text，路径进 uri', 0, (): void => {
      const item: SharedItem = itemOf(rec('general.jpeg', '/a.jpg')) as SharedItem;
      expect(item.uri).assertEqual('/a.jpg');
      expect(item.text).assertEqual('');
    });

    it('标题原样带过来（只给界面预览用）', 0, (): void => {
      const r: SharedRecordLike = { utd: 'general.jpeg', uri: '/a.jpg', title: '风景' };
      expect((itemOf(r) as SharedItem).title).assertEqual('风景');
    });

    // ---- 拆分 ----

    it('图文混合时文字当说明，不单独发一条', 0, (): void => {
      const items: SharedItem[] = [
        itemOf(rec('general.plain-text', '', '看这个')) as SharedItem,
        itemOf(rec('general.jpeg', '/a.jpg')) as SharedItem
      ];
      const payload: SharedPayload = splitPayload(items);
      expect(payload.caption).assertEqual('看这个');
      expect(payload.media.length).assertEqual(1);
    });

    it('多条文字换行拼起来', 0, (): void => {
      const items: SharedItem[] = [
        itemOf(rec('general.plain-text', '', 'a')) as SharedItem,
        itemOf(rec('general.hyperlink', 'https://b')) as SharedItem
      ];
      expect(splitPayload(items).caption).assertEqual('a\nhttps://b');
    });

    it('纯媒体时说明为空', 0, (): void => {
      const items: SharedItem[] = [itemOf(rec('general.jpeg', '/a.jpg')) as SharedItem];
      expect(splitPayload(items).caption).assertEqual('');
    });

    it('空输入拆出空载荷', 0, (): void => {
      const payload: SharedPayload = splitPayload([]);
      expect(payload.caption).assertEqual('');
      expect(payload.media.length).assertEqual(0);
    });

    // ---- 预览 ----

    it('纯文本的预览就是文本本身', 0, (): void => {
      expect(previewOf({ caption: '你好', media: [] })).assertEqual('你好');
    });

    it('多个媒体的预览带计数', 0, (): void => {
      const media: SharedItem[] = [
        itemOf(rec('general.jpeg', '/a.jpg')) as SharedItem,
        itemOf(rec('general.jpeg', '/b.jpg')) as SharedItem
      ];
      expect(previewOf({ caption: '', media: media })).assertEqual('JPG +1');
    });

    it('有标题时预览用标题', 0, (): void => {
      const r: SharedRecordLike = { utd: 'general.jpeg', uri: '/a.jpg', title: '风景' };
      expect(previewOf({ caption: '', media: [itemOf(r) as SharedItem] })).assertEqual('风景');
    });

    // ---- 跨进程交接 ----
    //
    // 分享面板那块界面在独立进程里选人，主应用进程负责发。中间只有一个
    // 交接文件，解析失败必须是"没有交接"而不是崩溃。

    it('交接往返：目标会话和内容都能还原', 0, (): void => {
      const handoff: ShareHandoff = {
        chatId: -100123,
        autoSend: true,
        payload: {
          caption: '看这个',
          media: [itemOf(rec('general.jpeg', '/cache/share_1_a.jpg')) as SharedItem]
        }
      };
      const back: ShareHandoff = parseHandoff(serializeHandoff(handoff)) as ShareHandoff;
      expect(back.chatId).assertEqual(-100123);
      expect(back.payload.caption).assertEqual('看这个');
      expect(back.payload.media.length).assertEqual(1);
      expect(back.payload.media[0].uri).assertEqual('/cache/share_1_a.jpg');
      expect(back.payload.media[0].kind).assertEqual('image');
      expect(back.autoSend).assertTrue();
    });

    it('交接：老格式没有 autoSend 时按"不自动发"处理', 0, (): void => {
      // 升级前留下的交接文件。宁可多一步确认，也不要莫名其妙把东西发出去。
      const old: string = `{"version":${HANDOFF_VERSION},"chatId":9,"caption":"x"}`;
      expect((parseHandoff(old) as ShareHandoff).autoSend).assertFalse();
    });

    it('交接：只有文字也成立', 0, (): void => {
      const handoff: ShareHandoff = { chatId: 7, autoSend: false, payload: { caption: 'hi', media: [] } };
      const back: ShareHandoff = parseHandoff(serializeHandoff(handoff)) as ShareHandoff;
      expect(back.payload.caption).assertEqual('hi');
      expect(back.payload.media.length).assertEqual(0);
    });

    it('交接：chatId 为 0 表示还没选人，仍然是有效交接', 0, (): void => {
      const handoff: ShareHandoff = { chatId: 0, autoSend: false, payload: { caption: 'hi', media: [] } };
      expect((parseHandoff(serializeHandoff(handoff)) as ShareHandoff).chatId).assertEqual(0);
    });

    it('交接：空内容不成立', 0, (): void => {
      const handoff: ShareHandoff = { chatId: 7, autoSend: true, payload: { caption: '', media: [] } };
      expect(parseHandoff(serializeHandoff(handoff)) === null).assertTrue();
    });

    it('交接：版本不符当作没有交接', 0, (): void => {
      const bad: string = `{"version":${HANDOFF_VERSION + 1},"chatId":1,"caption":"x"}`;
      expect(parseHandoff(bad) === null).assertTrue();
    });

    it('交接：坏 JSON 不抛异常', 0, (): void => {
      expect(parseHandoff('{truncated') === null).assertTrue();
      expect(parseHandoff('') === null).assertTrue();
    });

    it('交接：媒体项丢了路径就跳过那一条（文件没复制成功）', 0, (): void => {
      const text: string = `{"version":${HANDOFF_VERSION},"chatId":1,"caption":"c",` +
        `"media":[{"kind":"image"},{"kind":"image","uri":"/a.jpg"}]}`;
      const back: ShareHandoff = parseHandoff(text) as ShareHandoff;
      expect(back.payload.media.length).assertEqual(1);
      expect(back.payload.media[0].uri).assertEqual('/a.jpg');
    });
  });
}
