import { describe, expect, it } from '@ohos/hypium';
import { AlbumGroup } from '../main/ets/util/collapseAlbums';
import {
  ROW_TEMPLATE_DEFERRED, ROW_TEMPLATE_PLAIN, ROW_TEMPLATE_PLAIN_SEL,
  ROW_TEMPLATE_RICH, ROW_TEMPLATE_RICH_SEL, ROW_TEMPLATE_IDS, rowTemplateId
} from '../main/ets/util/rowTemplateId';

interface GroupShape {
  deferred: boolean;
}

function groupOf(over: GroupShape): AlbumGroup {
  const g: AlbumGroup = {} as AlbumGroup;
  if (over.deferred) {
    g.initialDeferred = true;
  }
  return g;
}

export default function rowTemplateIdTest() {
  describe('rowTemplateId', () => {
    // Repeat 要求每个 templateId 都预先注册 .template()；没注册的会退回 .each
    // 的默认池，等于没分池——那正是 2026-09-10 "消息重复/相册变文本" 那一族
    // 的成因（外壳按位置复用，装的却是结构不同的行）。所以这里钉两件事：
    // 取值必须落在全集里，且五种结构互不相同。
    it('every_id_is_registered_and_shapes_never_collide', 0, () => {
      const plain: AlbumGroup = groupOf({ deferred: false });
      const ids: string[] = [
        rowTemplateId(groupOf({ deferred: true }), false, false),
        rowTemplateId(plain, true, false),
        rowTemplateId(plain, true, true),
        rowTemplateId(plain, false, false),
        rowTemplateId(plain, false, true)
      ];
      // 五种结构五个不同的名字，一个都不许合并。
      expect(new Set<string>(ids).size).assertEqual(5);
      // 每一个都必须在注册全集里。
      for (const id of ids) {
        expect(ROW_TEMPLATE_IDS.indexOf(id) >= 0).assertTrue();
      }
      expect(ids[0]).assertEqual(ROW_TEMPLATE_DEFERRED);
      expect(ids[1]).assertEqual(ROW_TEMPLATE_PLAIN);
      expect(ids[2]).assertEqual(ROW_TEMPLATE_PLAIN_SEL);
      expect(ids[3]).assertEqual(ROW_TEMPLATE_RICH);
      expect(ids[4]).assertEqual(ROW_TEMPLATE_RICH_SEL);
    });

    // 首屏占位行只画一个定高 Column，多选让位栏对它没有意义——不该因为多选
    // 态而分成两个池，白白多占一份缓存。
    it('deferred_rows_ignore_the_selection_gutter', 0, () => {
      const d: AlbumGroup = groupOf({ deferred: true });
      expect(rowTemplateId(d, false, false)).assertEqual(rowTemplateId(d, false, true));
      expect(rowTemplateId(d, true, true)).assertEqual(ROW_TEMPLATE_DEFERRED);
    });
  });
}
