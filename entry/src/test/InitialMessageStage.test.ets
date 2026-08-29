import { describe, expect, it } from '@ohos/hypium';
import { buildMessageEntry } from '../main/ets/store/MessageEntry';
import { UserStore } from '../main/ets/store/UserStore';
import { TdBridge, TdObject } from '../main/ets/tdkit/TdTypes';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { AlbumGroup } from '../main/ets/util/collapseAlbums';
import {
  initialMessageViewportRows, nextInitialMessageRevealCount, stageInitialMessageGroups
} from '../main/ets/util/initialMessageStage';

class StageBridge implements TdBridge {
  onReceive: (json: string) => void = (_json: string): void => {};
  init(cb: (json: string) => void): void { this.onReceive = cb; }
  send(_json: string): void {}
}

function stageUsers(): UserStore {
  const bridge = new StageBridge();
  const client = new TdClient(bridge);
  const users = new UserStore(client);
  client.start();
  return users;
}

function groupOf(id: number): AlbumGroup {
  const formatted: TdObject = { '@type': 'formattedText', 'text': `message-${id}` };
  const content: TdObject = { '@type': 'messageText', 'text': formatted };
  const raw: TdObject = {
    '@type': 'message', 'id': id, 'date': id, 'is_outgoing': false, 'content': content
  };
  const head = buildMessageEntry(raw, stageUsers());
  return {
    key: `group-${id}`, head, memberIds: [id], rowMemberIds: [id],
    photoPaths: [], photoFileIds: [], photoRatios: [], photoIsVideo: [], photoIsLive: [],
    photoProgress: [], photoFailed: [], videoFileIds: [], videoFileSizes: [],
    videoMimeTypes: [], caption: '', captionEntities: [], dateLabel: '',
    showAvatar: true, showSenderName: true
  };
}

function groupsOf(count: number): AlbumGroup[] {
  const groups: AlbumGroup[] = [];
  for (let i = 0; i < count; i++) { groups.push(groupOf(i + 1)); }
  return groups;
}

export default function initialMessageStageTest() {
  describe('InitialMessageStage', () => {
    it('reveals_exactly_one_row_per_release', 0, () => {
      const first = nextInitialMessageRevealCount(0, 10);
      const second = nextInitialMessageRevealCount(first, 10);
      const third = nextInitialMessageRevealCount(second, 10);
      const fourth = nextInitialMessageRevealCount(third, 10);
      const fifth = nextInitialMessageRevealCount(fourth, 10);
      const sixth = nextInitialMessageRevealCount(fifth, 10);
      expect(first).assertEqual(1);
      expect(second).assertEqual(2);
      expect(third).assertEqual(3);
      expect(fourth).assertEqual(4);
      expect(fifth).assertEqual(5);
      expect(sixth).assertEqual(6);
      expect(nextInitialMessageRevealCount(9, 10)).assertEqual(10);
      expect(nextInitialMessageRevealCount(10, 10)).assertEqual(10);
    });

    it('keeps_bottom_one_real_by_default', 0, () => {
      const source = groupsOf(12);
      const staged = stageInitialMessageGroups(source, 11, false);
      for (let i = 0; i < 11; i++) {
        expect(staged[i].initialDeferred).assertTrue();
      }
      expect(staged[11] === source[11]).assertTrue();
    });

    it('can_publish_a_placeholder_only_page_frame', 0, () => {
      const source = groupsOf(12);
      const staged = stageInitialMessageGroups(source, 11, false, 0);
      for (let i = 0; i < staged.length; i++) {
        expect(staged[i].initialDeferred).assertTrue();
      }
    });

    it('keeps_deferred_keys_stable_between_batches', 0, () => {
      const source = groupsOf(12);
      const first = stageInitialMessageGroups(source, 11, false, 3);
      const second = stageInitialMessageGroups(source, 11, false, 6);
      for (let i = 0; i < source.length; i++) {
        expect(first[i].key).assertEqual(second[i].key);
        expect(first[i].key).assertEqual(source[i].key);
      }
      expect(first[6].initialDeferred).assertTrue();
      expect(second[6].initialDeferred === true).assertFalse();
    });

    it('keeps_bottom_five_real', 0, () => {
      const source = groupsOf(12);
      const staged = stageInitialMessageGroups(source, 11, false, 5);
      for (let i = 0; i < 7; i++) {
        expect(staged[i].initialDeferred).assertTrue();
        expect(staged[i].head === source[i].head).assertTrue();
        expect(staged[i].key).assertEqual(source[i].key);
      }
      for (let i = 7; i < 12; i++) {
        expect(staged[i].initialDeferred === true).assertFalse();
        expect(staged[i] === source[i]).assertTrue();
      }
    });

    it('keeps_five_from_unread_anchor_real', 0, () => {
      const source = groupsOf(12);
      const staged = stageInitialMessageGroups(source, 3, true, 5);
      for (let i = 3; i <= 7; i++) {
        expect(staged[i].initialDeferred === true).assertFalse();
      }
      expect(staged[2].initialDeferred).assertTrue();
      expect(staged[8].initialDeferred).assertTrue();
    });

    it('does_not_stage_short_timelines', 0, () => {
      const source = groupsOf(5);
      expect(stageInitialMessageGroups(source, 4, false, 5) === source).assertTrue();
    });

    it('sizes_bottom_preparation_from_viewport_height', 0, () => {
      const source = groupsOf(12);
      // Test text rows estimate to 64vp each; 180vp therefore needs 3 rows.
      expect(initialMessageViewportRows(source, 11, false, 360, 180, 0)).assertEqual(3);
    });

    it('sizes_unread_preparation_forward_from_anchor', 0, () => {
      const source = groupsOf(12);
      expect(initialMessageViewportRows(source, 3, true, 360, 180, 4)).assertEqual(3);
    });

    it('caps_viewport_preparation_at_available_rows', 0, () => {
      const source = groupsOf(2);
      expect(initialMessageViewportRows(source, 1, false, 360, 1000, 0)).assertEqual(2);
    });
  });
}
