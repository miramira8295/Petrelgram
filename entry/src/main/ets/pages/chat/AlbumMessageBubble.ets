import { MessageTextPresentationCache } from '../../util/messageTextInput';
import { MessageBubbleContext, MessageBubbleShell } from './MessageBubbleShell';
import { MessageBubbleText } from './MessageBubbleText';
import { AlbumGroup } from '../../util/collapseAlbums';
import { ALBUM_ROW_SLOTS } from '../../util/packAlbumRows';
import { AlbumCellRenderCache, AlbumCellRenderContext, AlbumCellRenderData, albumRenderRowAt } from '../../util/albumCellRenderData';
import { mediaThumbWidth, BUBBLE_AVATAR_GUTTER_VP } from '../../util/mediaBox';
import { AlbumRowView } from './AlbumRowView';
import { AlbumCellHooks } from './AlbumCellView';
import { MessageBubbleActions, MessageBubbleRenderData } from './ReusableMessageBubble';
import { logW } from '../../util/log';

// 相册直接组合公共壳与网格/配文，不实例化其他消息类型的状态和订阅。
// 格子几何与视频候选生命周期由相册自己持有；菜单/滑动共用壳的认领状态。
@ComponentV2
export struct AlbumMessageBubble {
  private textInputCache: MessageTextPresentationCache = new MessageTextPresentationCache();
  @Require @Param group: AlbumGroup;
  @Require @Param data: MessageBubbleRenderData;
  @Require @Param actions: MessageBubbleActions;
  @Param nowSec: number = 0;
  @Param jumpFocus: number = 0;
  @Param leaving: number = 0;
  private context: MessageBubbleContext = new MessageBubbleContext();
  private centers: Map<number, number> = new Map<number, number>();
  private competing: Map<number, number> = new Map<number, number>();
  private attachedRowId: number = 0;
  private hooks: AlbumCellHooks = {
    onCenterY: (index: number, y: number): void => { this.centers.set(index, y); },
    centerYOf: (index: number): number => this.centers.get(index) ?? 0,
    isClaimed: (): boolean => this.context.gestureClaimed,
    onToggleMember: (id: number): void => { this.actions.onToggleSelectedMessage(id); }
  };

  private syncCandidates(): void {
    if (this.attachedRowId !== this.group.head.rowId) {
      this.centers.clear();
    }
    let next: Map<number, number> | undefined = undefined;
    for (let i = 0; i < this.group.photoIsVideo.length; i++) {
      if (this.group.photoIsVideo[i]) {
        if (next === undefined) { next = new Map<number, number>(); }
        next.set(i, this.group.memberIds[i] ?? 0);
      }
    }
    if (next === undefined) {
      // Photo-only albums need no new empty candidate map. Still retire every
      // previous video before reusing the existing private map.
      this.competing.forEach((id: number, index: number): void => { this.actions.onMediaGone(id, index); });
      this.competing.clear();
    } else {
      const candidates = next;
      this.competing.forEach((id: number, index: number): void => {
        if (candidates.get(index) !== id) { this.actions.onMediaGone(id, index); }
      });
      this.competing = candidates;
    }
    this.attachedRowId = this.group.head.rowId;
  }

  private releaseCandidates(): void {
    this.competing.forEach((id: number, index: number): void => { this.actions.onMediaGone(id, index); });
    this.competing.clear();
    this.centers.clear();
    this.attachedRowId = 0;
  }

  aboutToAppear(): void { this.syncCandidates(); }
  aboutToDisappear(): void { this.releaseCandidates(); }
  aboutToRecycle(): void { this.releaseCandidates(); }
  aboutToReuse(): void {
    this.releaseCandidates();
    this.syncCandidates();
  }

  @Monitor('group')
  onGroupChanged(): void {
    this.syncCandidates();
  }

  private cellCache: AlbumCellRenderCache = new AlbumCellRenderCache();

  private albumWidth(): number {
    const avatarReserve: number = this.data.isGroup && !this.group.head.isOutgoing
      ? BUBBLE_AVATAR_GUTTER_VP : 0;
    return mediaThumbWidth(this.data.contentWidth, avatarReserve);
  }

  @Computed
  private get renderedRows(): AlbumCellRenderData[][] {
    const context: AlbumCellRenderContext = {
      chatId: this.data.chatId, selectionActive: this.data.selectionActive,
      selectedMemberIds: this.data.selectedMemberIds, playSlotKey: this.data.playSlotKey,
      autoplayMuted: this.data.autoplayMuted, playSlotStartMs: this.data.playSlotStartMs
    };
    const rows = this.cellCache.prepare(this.group, context, this.albumWidth());
    if (rows.length > ALBUM_ROW_SLOTS) {
      logW(`[Album] ${rows.length} rows > ${ALBUM_ROW_SLOTS} slots,` +
        ` tail not rendered (album=${this.group.head.albumId})`);
    }
    return rows;
  }

  @Builder
  grid() {
    Column({ space: 2 }) {
      AlbumRowView({ cells: albumRenderRowAt(this.renderedRows, 0), actions: this.actions, hooks: this.hooks });
      AlbumRowView({ cells: albumRenderRowAt(this.renderedRows, 1), actions: this.actions, hooks: this.hooks });
      AlbumRowView({ cells: albumRenderRowAt(this.renderedRows, 2), actions: this.actions, hooks: this.hooks });
      AlbumRowView({ cells: albumRenderRowAt(this.renderedRows, 3), actions: this.actions, hooks: this.hooks });
      AlbumRowView({ cells: albumRenderRowAt(this.renderedRows, 4), actions: this.actions, hooks: this.hooks });
      AlbumRowView({ cells: albumRenderRowAt(this.renderedRows, 5), actions: this.actions, hooks: this.hooks });
    }
    .alignItems(HorizontalAlign.Start)
    .width(this.albumWidth())
    .constraintSize({ maxWidth: this.albumWidth() });
  }

  @Builder
  content() {
    this.grid();
    if (this.group.caption !== '' || this.group.head.translatedText !== '') {
      MessageBubbleText({ actions: this.actions, context: this.context,
        presentation: this.textInputCache.prepare(this.group.head, this.group.showSenderName, this.data,
          this.group.caption, this.group.captionEntities, 0, 'caption') });
    }
  }

  build() {
    MessageBubbleShell({ msg: this.group.head, group: this.group, data: this.data, actions: this.actions,
      nowSec: this.nowSec, jumpFocus: this.jumpFocus, leaving: this.leaving, context: this.context }) {
      this.content();
    }
  }
}
