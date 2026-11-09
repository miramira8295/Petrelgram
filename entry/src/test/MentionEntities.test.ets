import { describe, expect, it } from '@ohos/hypium';
import { buildMentionEntities, NameMention } from '../main/ets/util/mentionEntities';
import { TdObject } from '../main/ets/tdkit/TdTypes';

// 没设用户名的成员被 @ 时，文本里只有一个光秃秃的名字，服务器无从识别，
// 对方收不到提及通知。这些用例钉住"客户端自己把 textEntityTypeMentionName
// 算对"——偏移错一位，Telegram 就会把提及落在别的字上。

function offsets(entities: TdObject[]): string {
  return entities.map((e: TdObject): string =>
    `${e['offset'] as number}+${e['length'] as number}` +
    `:${((e['type'] as TdObject)['user_id']) as number}`).join(',');
}

export default function mentionEntitiesTest() {
  describe('mentionEntities', () => {
    const alice: NameMention = { name: '张三', userId: 7 };

    it('没有提及时不产生实体', 0, () => {
      expect(buildMentionEntities('你好', []).length).assertEqual(0);
    });

    it('名字没出现在文本里就不标', 0, () => {
      expect(buildMentionEntities('你好啊', [alice]).length).assertEqual(0);
    });

    it('标注单次出现', 0, () => {
      expect(offsets(buildMentionEntities('张三 在吗', [alice]))).assertEqual('0+2:7');
    });

    it('偏移按 UTF-16 计，前面有文字时要跟着后移', 0, () => {
      expect(offsets(buildMentionEntities('喂 张三 在吗', [alice]))).assertEqual('2+2:7');
    });

    it('同一个名字出现多次时全部标注', 0, () => {
      expect(offsets(buildMentionEntities('张三 和 张三', [alice]))).assertEqual('0+2:7,5+2:7');
    });

    it('多个成员各自标注', 0, () => {
      const bob: NameMention = { name: '李四', userId: 9 };
      expect(offsets(buildMentionEntities('张三 李四', [alice, bob])))
        .assertEqual('0+2:7,3+2:9');
    });

    // 名字互为前缀：取长的那个，否则同一段文字会被标给两个人。
    it('名字互为前缀时取更长的那个', 0, () => {
      const zhang: NameMention = { name: '张三', userId: 7 };
      const zhangSanFeng: NameMention = { name: '张三丰', userId: 8 };
      expect(offsets(buildMentionEntities('张三丰 你好', [zhang, zhangSanFeng])))
        .assertEqual('0+3:8');
    });

    it('userId 无效时跳过', 0, () => {
      expect(buildMentionEntities('张三', [{ name: '张三', userId: 0 }]).length).assertEqual(0);
    });

    it('空名字跳过', 0, () => {
      expect(buildMentionEntities('张三', [{ name: '', userId: 7 }]).length).assertEqual(0);
    });

    // emoji 是代理对，占 2 个 UTF-16 单位——按码点算就会偏。
    it('名字前有 emoji 时偏移仍按 UTF-16 单位', 0, () => {
      const text = '🎉张三';
      expect(offsets(buildMentionEntities(text, [alice]))).assertEqual('2+2:7');
    });
  });
}
