import { describe, expect, it } from '@ohos/hypium';
import { AlbumCellRenderCache, AlbumCellRenderContext, AlbumCellRenderData,
  albumRenderRowAt } from '../main/ets/util/albumCellRenderData';
import { AlbumGroup, collapseAlbums } from '../main/ets/util/collapseAlbums';
import { packAlbumRows } from '../main/ets/util/packAlbumRows';
import { MessageEntry, buildMessageEntry } from '../main/ets/store/MessageEntry';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdBridge, TdObject } from '../main/ets/tdkit/TdTypes';
import { UserStore } from '../main/ets/store/UserStore';
import { slotKey } from '../main/ets/pages/chat/playSlot';

class AlbumRenderBridge implements TdBridge {
  init(_cb: (json: string) => void): void {}
  send(_json: string): void {}
}

function albumFixture(count: number = 4): AlbumGroup {
  const users = new UserStore(new TdClient(new AlbumRenderBridge()));
  const members: MessageEntry[] = [];
  for (let i = 0; i < count; i++) {
    const text: TdObject = { '@type': 'formattedText' }; text['text'] = '';
    const content: TdObject = { '@type': 'messageText' }; content['text'] = text;
    const sender: TdObject = { '@type': 'messageSenderUser' }; sender['user_id'] = 7;
    const raw: TdObject = { '@type': 'message' };
    raw['id'] = 101 + i; raw['date'] = 1000; raw['sender_id'] = sender; raw['content'] = content;
    const member = buildMessageEntry(raw, users);
    member.contentType = 'photo'; member.albumId = 'album';
    member.photoWidth = 400; member.photoHeight = 400;
    member.photoFileId = 1001 + i; member.photoPath = `/photo/${i}.jpg`;
    members.push(member);
  }
  return collapseAlbums(members)[0];
}

function contextFixture(): AlbumCellRenderContext {
  return { chatId: -100, selectionActive: false, selectedMemberIds: [],
    playSlotKey: '', autoplayMuted: true, playSlotStartMs: 0 };
}

function flatCells(rows: AlbumCellRenderData[][]): AlbumCellRenderData[] {
  const cells: AlbumCellRenderData[] = [];
  for (const row of rows) { for (const cell of row) { cells.push(cell); } }
  return cells;
}

export default function albumCellRenderDataTest(): void {
  describe('AlbumCellRenderData', (): void => {
    it('caption_translation_and_delivery_updates_reuse_all_media_inputs', 0, (): void => {
      const group = albumFixture(); const data = contextFixture(); const cache = new AlbumCellRenderCache();
      const rows = cache.prepare(group, data, 280);
      const changed = albumFixture(); changed.caption = 'new caption';
      changed.head.translatedText = 'translation'; changed.head.date += 10;
      changed.head.sendState = 'read'; changed.head.editDate += 1;
      expect(cache.prepare(changed, contextFixture(), 280) === rows).assertTrue();
    });
    it('one_selection_replaces_only_its_tile_and_row', 0, (): void => {
      const group = albumFixture(); const data = contextFixture(); data.selectionActive = true;
      const cache = new AlbumCellRenderCache(); const before = cache.prepare(group, data, 280);
      data.selectedMemberIds = [group.memberIds[0]];
      const after = cache.prepare(group, data, 280);
      expect(after[0][0] !== before[0][0]).assertTrue(); expect(after[0][0].selected).assertTrue();
      expect(after[0][1] === before[0][1]).assertTrue(); expect(after[1] === before[1]).assertTrue();
      expect(before[0][0].selected).assertFalse();
    });
    it('thumbnail_completion_and_retry_are_local_and_keep_old_snapshot_intact', 0, (): void => {
      const group = albumFixture(); const data = contextFixture(); const cache = new AlbumCellRenderCache();
      group.photoPaths[0] = ''; group.photoFailed[0] = true;
      const before = cache.prepare(group, data, 280);
      group.photoPaths[0] = '/downloaded.jpg'; group.photoFailed[0] = false; group.photoProgress[0] = 100;
      const after = cache.prepare(group, data, 280);
      expect(after[0][0].thumbPath).assertEqual('/downloaded.jpg'); expect(after[0][0].failed).assertFalse();
      expect(after[0][0].progress).assertEqual(100); expect(before[0][0].thumbPath).assertEqual('');
      expect(after[0][1] === before[0][1]).assertTrue(); expect(after[1] === before[1]).assertTrue();
    });
    it('downloaded_photo_without_file_id_and_live_video_metadata_survive_projection', 0, (): void => {
      const group = albumFixture(); group.photoFileIds[0] = 0;
      group.photoIsVideo[1] = true; group.photoIsLive[1] = true;
      group.videoFileIds[1] = 2001; group.videoFileSizes[1] = 9000; group.videoDurations[1] = 12;
      group.videoMimeTypes[1] = 'video/mp4'; group.inlineFileIds[1] = 3001; group.inlineFileSizes[1] = 1000;
      group.photoMinis[1] = 'mini';
      const cells = flatCells(new AlbumCellRenderCache().prepare(group, contextFixture(), 280));
      expect(cells[0].thumbFileId).assertEqual(0); expect(cells[0].thumbPath).assertEqual('/photo/0.jpg');
      expect(cells[1].isVideo && cells[1].isLive).assertTrue(); expect(cells[1].videoFileId).assertEqual(2001);
      expect(cells[1].videoFileSize).assertEqual(9000); expect(cells[1].videoDuration).assertEqual(12);
      expect(cells[1].videoMimeType).assertEqual('video/mp4'); expect(cells[1].inlineFileId).assertEqual(3001);
      expect(cells[1].inlineFileSize).assertEqual(1000); expect(cells[1].mini).assertEqual('mini');
    });
    it('player_position_and_mute_only_invalidate_the_owner', 0, (): void => {
      const group = albumFixture(); const data = contextFixture(); const cache = new AlbumCellRenderCache();
      group.photoIsVideo[0] = true; group.videoFileIds[0] = 2001;
      data.playSlotKey = slotKey(group.memberIds[0], 0);
      const before = cache.prepare(group, data, 280);
      data.playSlotStartMs = 5000; data.autoplayMuted = false;
      const after = cache.prepare(group, data, 280);
      expect(after[0][0].isPlaySlot).assertTrue(); expect(after[0][0].playSlotStartMs).assertEqual(5000);
      expect(after[0][0].autoplayMuted).assertFalse(); expect(after[0][1] === before[0][1]).assertTrue();
      expect(after[1] === before[1]).assertTrue();
      data.playSlotKey = 'another-row'; const idle = cache.prepare(group, data, 280);
      data.playSlotStartMs = 8000; data.autoplayMuted = true;
      expect(cache.prepare(group, data, 280) === idle).assertTrue();
    });
    it('player_switch_and_animation_exclusion_preserve_other_tiles', 0, (): void => {
      const group = albumFixture(); const data = contextFixture(); const cache = new AlbumCellRenderCache();
      data.playSlotKey = slotKey(group.memberIds[0], 0); const before = cache.prepare(group, data, 280);
      data.playSlotKey = slotKey(group.memberIds[1], 1); const after = cache.prepare(group, data, 280);
      expect(after[0][0].isPlaySlot).assertFalse(); expect(after[0][1].isPlaySlot).assertTrue();
      expect(after[1] === before[1]).assertTrue();
      group.head.isAnimation = true;
      expect(cache.prepare(group, data, 280)[0][1].isPlaySlot).assertFalse();
    });
    it('temporary_id_replacement_and_chat_switch_refresh_action_identity', 0, (): void => {
      const group = albumFixture(); const data = contextFixture(); const cache = new AlbumCellRenderCache();
      group.memberIds[0] = -1; const before = cache.prepare(group, data, 280);
      group.memberIds[0] = 9001; const after = cache.prepare(group, data, 280);
      expect(after[0][0].messageId).assertEqual(9001); expect(before[0][0].messageId).assertEqual(-1);
      expect(after[0][1] === before[0][1]).assertTrue();
      data.chatId = -200; const switched = flatCells(cache.prepare(group, data, 280));
      expect(switched.every((cell: AlbumCellRenderData): boolean => cell.chatId === -200)).assertTrue();
    });
    it('resize_and_ratio_mutation_match_existing_layout_and_stay_stable_afterward', 0, (): void => {
      const group = albumFixture(); const data = contextFixture(); const cache = new AlbumCellRenderCache();
      const before = cache.prepare(group, data, 280);
      group.photoRatios[0] = 2;
      const resized = cache.prepare(group, data, 240); const expected = packAlbumRows(group.photoRatios, 240);
      const cells = flatCells(resized);
      let count = 0;
      for (const row of expected) {
        for (const cell of row) {
          expect(cells[count].idx).assertEqual(cell.idx); expect(cells[count].width).assertEqual(cell.width);
          expect(cells[count].height).assertEqual(cell.height); count++;
        }
      }
      expect(resized !== before).assertTrue(); expect(cache.prepare(group, data, 240) === resized).assertTrue();
    });
    it('reusing_for_smaller_and_empty_albums_removes_stale_slots', 0, (): void => {
      const cache = new AlbumCellRenderCache(); const data = contextFixture();
      cache.prepare(albumFixture(10), data, 280);
      const small = albumFixture(2); const rows = cache.prepare(small, data, 280);
      expect(flatCells(rows).length).assertEqual(2); expect(albumRenderRowAt(rows, 5).length).assertEqual(0);
      expect(albumRenderRowAt(rows, -1).length).assertEqual(0); expect(albumRenderRowAt(rows, 0.5).length).assertEqual(0);
      small.photoRatios = [];
      expect(cache.prepare(small, data, 280).length).assertEqual(0);
    });
    it('album_uploading_state_reaches_every_tile_and_clears_after_send', 0, (): void => {
      const group = albumFixture(); const data = contextFixture(); const cache = new AlbumCellRenderCache();
      group.head.sendState = 'sending'; const uploading = flatCells(cache.prepare(group, data, 280));
      expect(uploading.every((cell: AlbumCellRenderData): boolean => cell.uploading)).assertTrue();
      group.head.sendState = 'sent'; const sent = flatCells(cache.prepare(group, data, 280));
      expect(sent.every((cell: AlbumCellRenderData): boolean => !cell.uploading)).assertTrue();
      expect(uploading.every((cell: AlbumCellRenderData): boolean => cell.uploading)).assertTrue();
    });
  });
}
