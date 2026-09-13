import { describe, it, expect } from '@ohos/hypium';
import { TdObject } from '../main/ets/tdkit/TdTypes';
import {
  parseStickerSetItems, parseStickerSetInfo, stickerSetIdOf, stickerSourceFileId,
  StickerSetItem, StickerSetInfo
} from '../main/ets/util/stickerSetItems';

function sticker(fileId: number, fmt: string, setId: string): TdObject {
  const file: TdObject = { '@type': 'file' }; file['id'] = fileId;
  const local: TdObject = { '@type': 'localFile' }; local['path'] = '';
  file['local'] = local;
  const format: TdObject = { '@type': fmt };
  const st: TdObject = { '@type': 'sticker' };
  st['sticker'] = file; st['format'] = format; st['set_id'] = setId;
  st['width'] = 512; st['height'] = 512; st['emoji'] = '😀';
  return st;
}

function thumbOf(fileId: number, fmt: string, path: string): TdObject {
  const file: TdObject = { '@type': 'file' }; file['id'] = fileId;
  const local: TdObject = { '@type': 'localFile' }; local['path'] = path;
  file['local'] = local;
  const t: TdObject = { '@type': 'thumbnail' };
  t['file'] = file; t['format'] = { '@type': fmt } as TdObject;
  return t;
}

export default function stickerSetItemsTest() {
  describe('stickerSetItems', () => {
    it('取贴纸所属合集 id：缺字段/占位 0 都算没有', 0, (): void => {
      expect(stickerSetIdOf(sticker(1, 'stickerFormatWebp', '12345'))).assertEqual('12345');
      const noSet: TdObject = { '@type': 'sticker' };
      expect(stickerSetIdOf(noSet)).assertEqual('');
      // TDLib 对"不属于任何合集"的贴纸给的是 0，不是缺字段。
      expect(stickerSetIdOf(sticker(1, 'stickerFormatWebp', '0'))).assertEqual('');
      // 数字型（某些回包不是字符串）也要能取到。
      const numeric: TdObject = { '@type': 'sticker' }; numeric['set_id'] = 998;
      expect(stickerSetIdOf(numeric)).assertEqual('998');
    });

    it('解析合集内容：webp 直接用源文件，动态贴纸用缩略图', 0, (): void => {
      const a = sticker(11, 'stickerFormatWebp', '7');
      const b = sticker(12, 'stickerFormatTgs', '7');
      b['thumbnail'] = thumbOf(99, 'thumbnailFormatWebp', '/p/99.webp');
      const res: TdObject = { '@type': 'stickerSet' };
      res['stickers'] = [a, b];
      const items: StickerSetItem[] = parseStickerSetItems(res);
      expect(items.length).assertEqual(2);
      expect(items[0].fileId).assertEqual(11);
      expect(items[0].format).assertEqual('webp');
      expect(items[0].thumbFileId).assertEqual(11);   // webp 自身就能画
      expect(items[1].format).assertEqual('tgs');
      expect(items[1].thumbFileId).assertEqual(99);
      expect(items[1].thumbPath).assertEqual('/p/99.webp');
    });

    it('跳过无源文件的条目；矢量缩略图不当栅格用', 0, (): void => {
      const broken: TdObject = { '@type': 'sticker' };
      const ok = sticker(5, 'stickerFormatTgs', '7');
      ok['thumbnail'] = thumbOf(60, 'thumbnailFormatWebm', '/p/60.webm'); // 不是栅格
      const res: TdObject = { '@type': 'stickerSet' };
      res['stickers'] = [broken, ok];
      const items: StickerSetItem[] = parseStickerSetItems(res);
      expect(items.length).assertEqual(1);
      expect(items[0].fileId).assertEqual(5);
      expect(items[0].thumbFileId).assertEqual(0);
    });

    it('合集信息：标题、数量、是否已添加', 0, (): void => {
      const res: TdObject = { '@type': 'stickerSet' };
      res['id'] = '7'; res['title'] = 'Cats'; res['name'] = 'cats_by_bot';
      res['is_installed'] = true; res['is_archived'] = false;
      res['stickers'] = [sticker(1, 'stickerFormatWebp', '7')];
      const info: StickerSetInfo = parseStickerSetInfo(res);
      expect(info.id).assertEqual('7');
      expect(info.title).assertEqual('Cats');
      expect(info.name).assertEqual('cats_by_bot');
      expect(info.installed).assertTrue();
      expect(info.count).assertEqual(1);
      // 归档过的合集不算"已添加"——再点一次应该是"添加"。
      const arch: TdObject = { '@type': 'stickerSet' };
      arch['is_installed'] = true; arch['is_archived'] = true; arch['stickers'] = [];
      expect(parseStickerSetInfo(arch).installed).assertFalse();
      expect(parseStickerSetInfo(arch).title).assertEqual('');
    });

    it('可收藏的那个文件：动态贴纸取源文件，静态取图片位', 0, (): void => {
      // 静态 webp：源文件就在 photoFileId 上
      expect(stickerSourceFileId('sticker', 0, 42, 'webp')).assertEqual(42);
      // 动态：photoFileId 是缩略图，必须取 stickerFileId
      expect(stickerSourceFileId('sticker', 77, 42, 'tgs')).assertEqual(77);
      expect(stickerSourceFileId('sticker', 77, 42, 'webm')).assertEqual(77);
      // 动态但源文件还没解析出来：不能退回缩略图
      expect(stickerSourceFileId('sticker', 0, 42, 'tgs')).assertEqual(0);
      // 非贴纸消息一律 0
      expect(stickerSourceFileId('photo', 0, 42, '')).assertEqual(0);
    });
  });
}
