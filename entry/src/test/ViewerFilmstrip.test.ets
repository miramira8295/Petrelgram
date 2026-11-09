import { describe, it, expect } from '@ohos/hypium';
import {
  FilmCellVM, buildFilmCells, cellKeys, filmCellIds, idIndexMap, indexOfId
} from '../main/ets/util/viewerFilmstrip';

// 查看器缩略图条 / Swiper 的纯数据层（2026-09-16）。
//
// 【为什么要有这一层】原来两处都是 ForEach(siblingIds())：一次性把每一格、每一页
// 都建出来，没有复用。聊天里相册最多十张所以没暴露；下载中心把整个页签当成一个
// 相册，n 就是 DC 已加载的全部（用户 2026-09-16 问：「缩略图列表是分页的吗」）。
// 改成 LazyForEach 之后，数据源要的三件套（items / ids / keys）在这里算，
// 组件只管画。

function cells(): FilmCellVM[] {
  return buildFilmCells([11, 22, 33], ['/a.jpg', '', '/c.jpg'], [0, 77, 0],
    (id: number): boolean => id === 22, (id: number): string => id === 22 ? '/v/b.mp4' : '');
}

export default function viewerFilmstripTest() {
  describe('viewerFilmstrip', () => {
    it('maps_paths_and_file_ids_by_member_index', 0, () => {
      const out: FilmCellVM[] = cells();
      expect(out.length).assertEqual(3);
      expect(out[0].id).assertEqual(11);
      expect(out[0].path).assertEqual('/a.jpg');
      expect(out[0].fileId).assertEqual(0);
      expect(out[1].fileId).assertEqual(77);
      expect(out[1].isVideo).assertTrue();
      expect(out[2].isVideo).assertFalse();
      // 本地视频路径只给视频格：海报按它取（util/videoPosterStore 按路径索引）。
      expect(out[1].videoPath).assertEqual('/v/b.mp4');
      expect(out[0].videoPath).assertEqual('');
    });

    // 相册行的 photoPaths/photoFileIds 可能比 memberIds 短（半个相册、还没落地的
    // 缩略图）。短了就给空值，不能越界。
    it('tolerates_short_path_and_file_id_arrays', 0, () => {
      const out: FilmCellVM[] = buildFilmCells([1, 2, 3], ['/only.jpg'], [],
        (_id: number): boolean => false);
      expect(out.length).assertEqual(3);
      expect(out[1].path).assertEqual('');
      expect(out[1].fileId).assertEqual(0);
    });

    it('ids_are_the_member_ids', 0, () => {
      expect(filmCellIds(cells()).join(',')).assertEqual('11,22,33');
    });

    // 选中态**不进 key**：高亮/缩放走 ViewerFilmstripCell 的 current @Param 就地更新。
    // 进了 key 的后果分两层：缩略图条每翻一页白重建两格；大图层当前页换 key =
    // Swiper 重建那一页 = 视频宿主重建 = 翻回来重新起播。
    it('keys_do_not_encode_the_selection', 0, () => {
      const a: string[] = cellKeys(cells());
      const b: string[] = cellKeys(cells());
      expect(a.join('|')).assertEqual(b.join('|'));
      expect(a[1]).assertEqual('22|77|1|/v/b.mp4');
    });

    // 缩略图落地不该换 key：LiveThumbImage 自己订阅通道换图（路径刻意不进 key，
    // 见 collapseAlbums）。所以 key 只含 fileId，不含 path。
    it('a_landed_thumbnail_does_not_rekey', 0, () => {
      const dry: FilmCellVM[] = buildFilmCells([11], [''], [77], (): boolean => false);
      const wet: FilmCellVM[] = buildFilmCells([11], ['/landed.jpg'], [77], (): boolean => false);
      expect(cellKeys(dry)[0]).assertEqual(cellKeys(wet)[0]);
    });

    // id → 下标。原来每格都 indexOf/findIndex，n 格就是 O(n²)。
    it('builds_an_index_map', 0, () => {
      const map: Map<number, number> = idIndexMap([11, 22, 33]);
      expect(indexOfId(map, 22)).assertEqual(1);
      expect(indexOfId(map, 999)).assertEqual(-1);
    });
  });
}
