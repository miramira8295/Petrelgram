// 查看器缩略图条 / 大图层的纯数据层（2026-09-16）。
//
// 【为什么要有这一层】原来缩略图条是 `Scroll{Row{ForEach(siblingIds())}}`、大图层是
// `Swiper{ForEach(siblingIds())}`——两处都一次性把每一格、每一页建出来，没有复用。
// 聊天里相册最多十张所以一直没暴露；下载中心把**整个页签**当成一个相册
// （pages/main/DownloadPreviewPage + util/downloadViewerSet，没有上限），n 就是下载
// 中心已加载的全部条目。用户 2026-09-16 问：「缩略图列表是分页的吗。如果一次都加载
// 上来又会很卡，item 需要是复用的」——确实不是，确实会。
//
// 改成 LazyForEach 之后，数据源要的三件套（items / ids / keys）在这里算，组件只管画。
// 判据集中在这里还有一个好处：两层的 key 规则**不一样**，而那个差别正是容易写错的地方。

export interface FilmCellVM {
  id: number;
  // 缩略图的 TDLib 文件 id：交给 LiveThumbImage 自己订阅 mediaThumbChannel。
  fileId: number;
  // 通道还没有值时的兜底路径（相册行里那份）。
  path: string;
  isVideo: boolean;
  // 本地视频文件的路径。下载中心磁盘扫出来的视频 fileId 恒为 0、也没有 TDLib 缩略图，
  // 海报只能自己抽首帧，而那条通道**按路径索引**（util/videoPosterStore）。
  // 聊天里的视频这一项是空串，走原来的 fileId 通道。
  videoPath: string;
}

// 相册行的 photoPaths / photoFileIds 可能比 memberIds 短（半个相册、缩略图还没落地），
// 短了就给空值——越界取值在 ArkTS 里是 undefined，会一路飘到 Image 的 src。
export function buildFilmCells(
  memberIds: number[], photoPaths: string[], photoFileIds: number[],
  isVideo: (id: number) => boolean, videoPathOf: (id: number) => string = (): string => ''
): FilmCellVM[] {
  const out: FilmCellVM[] = [];
  for (let i = 0; i < memberIds.length; i++) {
    const id: number = memberIds[i];
    const video: boolean = isVideo(id);
    out.push({
      id: id,
      fileId: i < photoFileIds.length ? photoFileIds[i] : 0,
      path: i < photoPaths.length ? photoPaths[i] : '',
      isVideo: video,
      videoPath: video ? videoPathOf(id) : ''
    });
  }
  return out;
}

// 身份：消息 id。LazyForEach 的前后缀对齐按它做。
export function filmCellIds(cells: FilmCellVM[]): string[] {
  return cells.map((c: FilmCellVM): string => `${c.id}`);
}

// 行的内容签名（两层共用一份数据源，所以只有一套 key）。
//
// **不含选中态**：高亮/缩放由 ViewerFilmstripCell 的 `current` @Param 就地更新——
// 进 key 就等于每翻一页重建两格，而大图层那边更严重：当前页换 key = Swiper 重建那
// 一页 = 视频宿主重建 = 翻回来重新起播。
//
// **不含 path**：缩略图落地由 LiveThumbImage 自己订阅通道换图（路径刻意不进 key，
// 理由见 util/collapseAlbums）；进 key 只会让每张图落地都白白重建一格。
export function cellKeys(cells: FilmCellVM[]): string[] {
  return cells.map((c: FilmCellVM): string => `${c.id}|${c.fileId}|${c.isVideo ? 1 : 0}|${c.videoPath}`);
}

// id → 下标。原来 siblingPath / siblingIsVideo / entryById / jumpToSibling 每格都各自
// indexOf / findIndex 一遍，建 n 格就是 O(n²)。
//
// 重复 id 取**第一个**：相册成员本该唯一，真撞上了也要行为确定。
export function idIndexMap(ids: number[]): Map<number, number> {
  const map: Map<number, number> = new Map<number, number>();
  for (let i = 0; i < ids.length; i++) {
    if (!map.has(ids[i])) {
      map.set(ids[i], i);
    }
  }
  return map;
}

export function indexOfId(map: Map<number, number>, id: number): number {
  const at: number | undefined = map.get(id);
  return at === undefined ? -1 : at;
}
