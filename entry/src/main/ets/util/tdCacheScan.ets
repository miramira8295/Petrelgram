import { fileIo as fs, Filter, ListFileOptions } from '@kit.CoreFileKit';
import { taskpool } from '@kit.ArkTS';

// 下载中心的磁盘扫描（2026-09-15）：列出 TDLib 缓存目录里已经完整落盘的文件。
//
// 和 util/downloadedFileScan 同一套做法（离开 UI 线程、体积过滤下推原生层、worker 里排序截断，
// 理由见那个文件头），区别是目录更全——多了音乐、语音、圆形视频——并且把目录名带回来，
// 由 util/downloadCenterModel.kindOfDiskDir 判类型。
//
// 扫出来的只有路径：TDLib 没有"路径 → fileId / 消息"的接口，所以这些条目不能定位到消息、
// 也没有进度（能扫到就是完整的；没下完的分片在 temp 目录里，名字对不上任何消息，不列）。

export interface TdCacheFile {
  path: string;
  name: string;
  dir: string;
  size: number;
  mtimeSec: number;
}

interface CacheDir {
  name: string;
  minBytes: number;
}

@Concurrent
function scanTdCacheTask(base: string, minPhotoBytes: number, maxItems: number): TdCacheFile[] {
  const dirs: CacheDir[] = [
    { name: 'videos', minBytes: 0 },
    { name: 'animations', minBytes: 0 },
    { name: 'video_notes', minBytes: 0 },
    { name: 'music', minBytes: 0 },
    { name: 'voice', minBytes: 0 },
    { name: 'documents', minBytes: 0 },
    // 自动下载的缩略图全落在 photos 里、占绝大多数，靠体积在原生层挡掉。
    { name: 'photos', minBytes: minPhotoBytes }
  ];
  const items: TdCacheFile[] = [];
  for (const d of dirs) {
    const dir: string = `${base}/${d.name}`;
    try {
      const filter: Filter = { fileSizeOver: d.minBytes };
      const options: ListFileOptions = { filter: filter };
      const names: string[] = fs.listFileSync(dir, options);
      for (const name of names) {
        const path: string = `${dir}/${name}`;
        try {
          const st = fs.statSync(path);
          if (!st.isFile() || st.size <= 0) {
            continue;
          }
          items.push({ path: path, name: name, dir: d.name, size: st.size, mtimeSec: st.mtime });
        } catch (e) {
          // 单个条目不可读（正在写入 / 刚被 TDLib 清理）——跳过。
        }
      }
    } catch (e) {
      // 目录还没建——正常，跳过。
    }
  }
  items.sort((a: TdCacheFile, b: TdCacheFile): number => b.mtimeSec - a.mtimeSec);
  return items.slice(0, maxItems);
}

export function scanTdCacheFiles(base: string, minPhotoBytes: number, maxItems: number): Promise<TdCacheFile[]> {
  const task: taskpool.Task = new taskpool.Task(scanTdCacheTask, base, minPhotoBytes, maxItems);
  return taskpool.execute(task).then((res: Object): TdCacheFile[] => res as TdCacheFile[]);
}
