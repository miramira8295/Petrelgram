// 「这张贴纸收藏过没有」的本地那一份。
//
// 【为什么要有它】长按菜单必须在**渲染那一刻**就知道该写"添加到收藏"还是
// "取消收藏"——菜单是同步构建的，等不了一次 getFavoriteStickers 往返。所以
// 收藏表整表存一份，菜单只读它；点下去先本地翻面（用户立刻看到结果），服务端
// 回包再以整表为准覆盖。
//
// 没加载过时 has() 一律返回 false：宁可显示"添加到收藏"（点了是幂等的，
// TDLib 对已收藏的贴纸只是把它移到最前），也不要谎报"已收藏"让用户点了丢失。
export class FavoriteStickerCache {
  private ids: Set<number> = new Set<number>();
  private ready: boolean = false;

  loaded(): boolean {
    return this.ready;
  }

  has(fileId: number): boolean {
    return fileId !== 0 && this.ids.has(fileId);
  }

  replaceAll(fileIds: number[]): void {
    const next: Set<number> = new Set<number>();
    for (const id of fileIds) {
      if (id !== 0) {
        next.add(id);
      }
    }
    this.ids = next;
    this.ready = true;
  }

  set(fileId: number, favorite: boolean): void {
    if (fileId === 0) {
      return;
    }
    const next: Set<number> = new Set<number>(this.ids);
    if (favorite) {
      next.add(fileId);
    } else {
      next.delete(fileId);
    }
    this.ids = next;
  }
}
