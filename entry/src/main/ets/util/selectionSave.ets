// 多选保存（issue #199）：从选中的消息里挑出能保存的媒体。
// 照片 / 视频 / 视频消息 → 相册；文件 / 音乐 → 下载目录。语音、贴纸、文本不算。
// 只做挑选与分类，真正的下载与落盘交给 MediaSaveState。

export interface SaveableSource {
  id: number;
  contentType: string;
}

export interface SaveableEntry {
  id: number;
  toFiles: boolean;
}

export interface SaveablePlan {
  entries: SaveableEntry[];   // 按 id 升序
  galleryCount: number;
  fileCount: number;
}

const GALLERY_TYPES: string[] = ['photo', 'video', 'videoNote'];
const FILE_TYPES: string[] = ['file', 'audio'];

export function saveableEntries(sources: SaveableSource[], selectedIds: number[]): SaveablePlan {
  const wanted: Set<number> = new Set<number>(selectedIds);
  const entries: SaveableEntry[] = [];
  let galleryCount: number = 0;
  let fileCount: number = 0;
  for (const s of sources) {
    if (!wanted.has(s.id)) {
      continue;
    }
    if (GALLERY_TYPES.indexOf(s.contentType) >= 0) {
      entries.push({ id: s.id, toFiles: false });
      galleryCount++;
    } else if (FILE_TYPES.indexOf(s.contentType) >= 0) {
      entries.push({ id: s.id, toFiles: true });
      fileCount++;
    }
  }
  entries.sort((a: SaveableEntry, b: SaveableEntry): number => a.id - b.id);
  return { entries, galleryCount, fileCount };
}
