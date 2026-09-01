import { describe, expect, it } from '@ohos/hypium';
import { AlbumGroup } from '../main/ets/util/collapseAlbums';
import {
  ChatTimelineSnapshot, coalesceChatTimelineSnapshot, emptyChatTimelineSnapshot
} from '../main/ets/util/chatTimelineSnapshot';

function snapshotWith(groups: AlbumGroup[], loadState: string = 'loading'): ChatTimelineSnapshot {
  return {
    groups: groups,
    visibleGroupCount: groups.length,
    messageLoadState: loadState,
    messageLoadError: '',
    olderLoadState: 'idle',
    newerLoadState: 'idle',
    isChannel: false,
    isGroup: false
  };
}

export default function chatTimelineSnapshotTest() {
  describe('chatTimelineSnapshot', () => {
    it('equivalent publication keeps the current object identity', 0, () => {
      const groups: AlbumGroup[] = [];
      const current: ChatTimelineSnapshot = snapshotWith(groups);
      const merged: ChatTimelineSnapshot = coalesceChatTimelineSnapshot(
        current, snapshotWith(groups));
      expect(merged === current).assertTrue();
    });

    it('a complete state change is published as one replacement', 0, () => {
      const groups: AlbumGroup[] = [];
      const current: ChatTimelineSnapshot = emptyChatTimelineSnapshot();
      const ready: ChatTimelineSnapshot = snapshotWith(groups, 'ready');
      const merged: ChatTimelineSnapshot = coalesceChatTimelineSnapshot(current, ready);
      expect(merged === current).assertFalse();
      expect(merged === ready).assertTrue();
      expect(merged.messageLoadState).assertEqual('ready');
    });

    it('a new row-array identity is a real host publication', 0, () => {
      const firstRows: AlbumGroup[] = [];
      const secondRows: AlbumGroup[] = [];
      const current: ChatTimelineSnapshot = snapshotWith(firstRows, 'ready');
      const merged: ChatTimelineSnapshot = coalesceChatTimelineSnapshot(
        current, snapshotWith(secondRows, 'ready'));
      expect(merged === current).assertFalse();
      expect(merged.groups === secondRows).assertTrue();
    });
  });
}
