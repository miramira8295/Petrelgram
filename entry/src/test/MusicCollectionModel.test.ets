import { describe, expect, it } from '@ohos/hypium';
import {
  addTrackToCollection, collectionContains, createMusicCollection, deleteMusicCollection,
  MusicCollection, MusicLibrarySummary, musicCollectionsSummary, parseMusicCollections,
  removeTrackFromCollection, renameMusicCollection, serializeMusicCollections, toggleTrackInCollection
} from '../main/ets/util/musicCollectionModel';

// 「我的合集」的数据模型（2026-09-18，设计稿「Music Player」的我的页/合集详情/添加到合集）。
//
// 合集只存曲目键（会话 id + 消息 id，见 musicTrackModel.musicTrackKey），不存曲目本身：
// 曲目随时可能被重新下载、换文件 id，存快照就会和真实消息对不上。
// 全部纯函数且**不改入参**（仓库规矩：返回新数组）。

const A: string = '-100123_88';
const B: string = '-100123_99';

function seed(): MusicCollection[] {
  const first: MusicCollection | null = createMusicCollection([], '深夜工作', 'c1', 1000);
  const second: MusicCollection | null = createMusicCollection([first!], '通勤', 'c2', 2000);
  return [first!, second!];
}

export default function musicCollectionModelTest() {
  describe('musicCollectionModel', () => {
    it('新建合集：名字去空格，空名与重名不建', 0, (): void => {
      const created: MusicCollection | null = createMusicCollection([], '  深夜工作 ', 'c1', 1000);
      expect(created !== null).assertTrue();
      expect(created!.name).assertEqual('深夜工作');
      expect(created!.id).assertEqual('c1');
      expect(created!.createdAt).assertEqual(1000);
      expect(created!.trackKeys.length).assertEqual(0);
      expect(createMusicCollection([], '   ', 'c2', 1) === null).assertTrue();
      // 重名：同名合集在「添加到合集」的列表里分不清，直接不给建
      expect(createMusicCollection([created!], '深夜工作', 'c2', 2) === null).assertTrue();
    });

    it('加入与移出都返回新数组，不改原来的', 0, (): void => {
      const before: MusicCollection[] = seed();
      const added: MusicCollection[] = addTrackToCollection(before, 'c1', A);
      expect(collectionContains(added[0], A)).assertTrue();
      expect(collectionContains(before[0], A)).assertFalse();
      expect(before[0].trackKeys.length).assertEqual(0);
      // 重复加入不产生第二条
      expect(addTrackToCollection(added, 'c1', A)[0].trackKeys.length).assertEqual(1);
      const removed: MusicCollection[] = removeTrackFromCollection(added, 'c1', A);
      expect(collectionContains(removed[0], A)).assertFalse();
      // 不存在的合集 id：原样返回
      expect(addTrackToCollection(before, 'nope', A)[0].trackKeys.length).assertEqual(0);
    });

    it('勾选是加入与移出的开关', 0, (): void => {
      const once: MusicCollection[] = toggleTrackInCollection(seed(), 'c2', B);
      expect(collectionContains(once[1], B)).assertTrue();
      const twice: MusicCollection[] = toggleTrackInCollection(once, 'c2', B);
      expect(collectionContains(twice[1], B)).assertFalse();
    });

    it('改名与删除', 0, (): void => {
      const renamed: MusicCollection[] = renameMusicCollection(seed(), 'c1', ' 睡前 ');
      expect(renamed[0].name).assertEqual('睡前');
      // 空名不改
      expect(renameMusicCollection(renamed, 'c1', '  ')[0].name).assertEqual('睡前');
      const left: MusicCollection[] = deleteMusicCollection(seed(), 'c1');
      expect(left.length).assertEqual(1);
      expect(left[0].id).assertEqual('c2');
      expect(deleteMusicCollection(left, 'nope').length).assertEqual(1);
    });

    it('统计：几个合集、几首歌，同一首在两个合集里只算一次', 0, (): void => {
      let list: MusicCollection[] = seed();
      list = addTrackToCollection(list, 'c1', A);
      list = addTrackToCollection(list, 'c2', A);
      list = addTrackToCollection(list, 'c2', B);
      const summary: MusicLibrarySummary = musicCollectionsSummary(list);
      expect(summary.collections).assertEqual(2);
      expect(summary.tracks).assertEqual(2);
      expect(musicCollectionsSummary([]).tracks).assertEqual(0);
    });

    it('存取：坏数据当没有，不让它拖垮启动', 0, (): void => {
      let list: MusicCollection[] = seed();
      list = addTrackToCollection(list, 'c1', A);
      const restored: MusicCollection[] = parseMusicCollections(serializeMusicCollections(list));
      expect(restored.length).assertEqual(2);
      expect(restored[0].name).assertEqual('深夜工作');
      expect(restored[0].trackKeys[0]).assertEqual(A);
      expect(parseMusicCollections('').length).assertEqual(0);
      expect(parseMusicCollections('{ 不是 json').length).assertEqual(0);
      expect(parseMusicCollections('[{"id":"x"}]').length).assertEqual(0);
      expect(parseMusicCollections('{"a":1}').length).assertEqual(0);
    });
  });
}
