// 「我的合集」的数据模型（2026-09-18，设计稿「Music Player」）。
//
// 合集里只存**曲目键**（会话 id + 消息 id，见 musicTrackModel.musicTrackKey），不存曲目本身：
// 同一首歌的文件 id、本地路径、下载状态随时会变，存快照必然和真实消息对不上；键是稳定的。
//
// 全部纯函数，且**不改入参**——返回新数组（仓库规矩）。落盘在 store/MusicCollectionStore。

export interface MusicCollection {
  id: string;
  name: string;
  trackKeys: string[];
  createdAt: number;
}

export interface MusicLibrarySummary {
  collections: number;
  // 去重之后的歌曲数：同一首歌在两个合集里只算一次。
  tracks: number;
}

export function collectionContains(collection: MusicCollection, trackKey: string): boolean {
  return collection.trackKeys.indexOf(trackKey) >= 0;
}

// 空名不建；重名也不建——「添加到合集」的列表里两个同名合集分不清哪个是哪个。
export function createMusicCollection(
  collections: MusicCollection[], name: string, id: string, now: number
): MusicCollection | null {
  const trimmed: string = name.trim();
  if (trimmed === '' || id === '') {
    return null;
  }
  const taken: boolean = collections.some((c: MusicCollection): boolean => c.name === trimmed);
  if (taken) {
    return null;
  }
  return { id: id, name: trimmed, trackKeys: [], createdAt: now };
}

function mapCollection(
  collections: MusicCollection[], id: string, patch: (c: MusicCollection) => MusicCollection
): MusicCollection[] {
  return collections.map((c: MusicCollection): MusicCollection => c.id === id ? patch(c) : c);
}

export function addTrackToCollection(
  collections: MusicCollection[], collectionId: string, trackKey: string
): MusicCollection[] {
  return mapCollection(collections, collectionId, (c: MusicCollection): MusicCollection =>
    collectionContains(c, trackKey)
      ? c
      : { id: c.id, name: c.name, trackKeys: c.trackKeys.concat([trackKey]), createdAt: c.createdAt });
}

export function removeTrackFromCollection(
  collections: MusicCollection[], collectionId: string, trackKey: string
): MusicCollection[] {
  return mapCollection(collections, collectionId, (c: MusicCollection): MusicCollection => ({
    id: c.id,
    name: c.name,
    trackKeys: c.trackKeys.filter((key: string): boolean => key !== trackKey),
    createdAt: c.createdAt
  }));
}

// 「添加到合集」面板里每行的勾：有就移出，没有就加入。
export function toggleTrackInCollection(
  collections: MusicCollection[], collectionId: string, trackKey: string
): MusicCollection[] {
  const target: MusicCollection | undefined =
    collections.find((c: MusicCollection): boolean => c.id === collectionId);
  if (target === undefined) {
    return collections.slice();
  }
  return collectionContains(target, trackKey)
    ? removeTrackFromCollection(collections, collectionId, trackKey)
    : addTrackToCollection(collections, collectionId, trackKey);
}

export function renameMusicCollection(
  collections: MusicCollection[], collectionId: string, name: string
): MusicCollection[] {
  const trimmed: string = name.trim();
  if (trimmed === '') {
    return collections.slice();
  }
  return mapCollection(collections, collectionId, (c: MusicCollection): MusicCollection => ({
    id: c.id, name: trimmed, trackKeys: c.trackKeys, createdAt: c.createdAt
  }));
}

export function deleteMusicCollection(
  collections: MusicCollection[], collectionId: string
): MusicCollection[] {
  return collections.filter((c: MusicCollection): boolean => c.id !== collectionId);
}

export function musicCollectionsSummary(collections: MusicCollection[]): MusicLibrarySummary {
  const keys: Set<string> = new Set<string>();
  collections.forEach((c: MusicCollection): void => {
    c.trackKeys.forEach((key: string): void => { keys.add(key); });
  });
  return { collections: collections.length, tracks: keys.size };
}

export function serializeMusicCollections(collections: MusicCollection[]): string {
  return JSON.stringify(collections);
}

// 坏数据一律当成「没有合集」：这份东西在启动路径上读，不能让它把启动拖垮
// （同 savedLocalModel 的处理）。
export function parseMusicCollections(raw: string): MusicCollection[] {
  if (raw.trim() === '') {
    return [];
  }
  let parsed: Object;
  try {
    parsed = JSON.parse(raw) as Object;
  } catch (e) {
    return [];
  }
  if (!Array.isArray(parsed)) {
    return [];
  }
  const out: MusicCollection[] = [];
  (parsed as Object[]).forEach((item: Object): void => {
    const record = item as Record<string, Object>;
    const id = record['id'] as string | undefined;
    const name = record['name'] as string | undefined;
    const keys = record['trackKeys'] as Object | undefined;
    if (typeof id !== 'string' || id === '' || typeof name !== 'string' || name === '' ||
      !Array.isArray(keys)) {
      return;
    }
    const trackKeys: string[] = (keys as Object[])
      .filter((key: Object): boolean => typeof key === 'string' && (key as string) !== '')
      .map((key: Object): string => key as string);
    const createdAt = record['createdAt'] as number | undefined;
    out.push({
      id: id,
      name: name,
      trackKeys: trackKeys,
      createdAt: typeof createdAt === 'number' ? createdAt : 0
    });
  });
  return out;
}
