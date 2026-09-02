import { describe, expect, it } from '@ohos/hypium';
import { buildMessageEntry } from '../main/ets/store/MessageEntry';
import { UserStore } from '../main/ets/store/UserStore';
import { TdBridge, TdObject } from '../main/ets/tdkit/TdTypes';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { AlbumGroup } from '../main/ets/util/collapseAlbums';
import {
  initialMessagePlaceholderHeight, initialMessageViewportRows,
  nextInitialMessageRevealCount, stageInitialMessageGroups
} from '../main/ets/util/initialMessageStage';
import { mediaBoxFor, mediaThumbWidth } from '../main/ets/util/mediaBox';
import { AlbumCell, packAlbumRows } from '../main/ets/util/packAlbumRows';

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
    videoDurations: [], videoMimeTypes: [], caption: '', captionEntities: [], dateLabel: '',
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

    it('uses_cached_geometry_to_size_the_initial_viewport', 0, () => {
      const source = groupsOf(12);
      expect(initialMessageViewportRows(
        source, 11, false, 360, 180, 0,
        (_group: AlbumGroup, _width: number, _divider: boolean): number => 100
      )).assertEqual(2);
    });

    // 绘制面批 1：媒体行估高与真实布局共用 mediaBoxFor/packAlbumRows。
    it('media_row_height_follows_shared_media_geometry', 0, () => {
      const g = groupOf(501);
      g.head.contentType = 'photo';
      g.head.text = '';
      g.head.photoWidth = 900;
      g.head.photoHeight = 600;
      g.showSenderName = false;
      const screenW: number = 400;
      // MEDIA_BUBBLE_CHROME = 20（气泡 padding 16 + 行外边距近似）。
      const expected: number = mediaBoxFor(screenW, 900, 600, false).height + 20;
      expect(initialMessagePlaceholderHeight(g, screenW, false)).assertEqual(expected);
    });

    it('album_row_height_sums_packed_mosaic_rows', 0, () => {
      const g = groupOf(502);
      g.head.contentType = 'photo';
      g.photoPaths = ['a', 'b', 'c'];
      g.photoRatios = [1.2, 0.8, 1.5];
      g.showSenderName = false;
      const screenW: number = 400;
      const rows: AlbumCell[][] = packAlbumRows(g.photoRatios, mediaThumbWidth(screenW));
      let media: number = 0;
      for (const row of rows) {
        media += row[0].height;
      }
      media += (rows.length - 1) * 2;
      expect(initialMessagePlaceholderHeight(g, screenW, false)).assertEqual(media + 20);
    });

    it('sender_name_row_adds_height_for_incoming_group_media', 0, () => {
      const named = groupOf(504);
      named.head.contentType = 'photo';
      named.head.text = '';
      named.head.photoWidth = 900;
      named.head.photoHeight = 600;
      named.showSenderName = true;
      const anonymous = groupOf(505);
      anonymous.head.contentType = 'photo';
      anonymous.head.text = '';
      anonymous.head.photoWidth = 900;
      anonymous.head.photoHeight = 600;
      anonymous.showSenderName = false;
      const withName: number = initialMessagePlaceholderHeight(named, 400, false);
      const without: number = initialMessagePlaceholderHeight(anonymous, 400, false);
      expect(withName - without).assertEqual(22);
    });

    // 行数启发式 v2：中文按全宽字符换行，caption 宽度跟媒体框走（批 2 校准）。
    it('cjk_caption_estimates_more_lines_than_latin', 0, () => {
      AppStorage.setOrCreate('msgTextSize', 16);
      const cjk = groupOf(506);
      cjk.head.contentType = 'photo';
      cjk.photoPaths = ['a', 'b', 'c'];
      cjk.photoRatios = [1.2, 0.8, 1.5];
      cjk.showSenderName = false;
      cjk.caption = '中'.repeat(96);
      const latin = groupOf(507);
      latin.head.contentType = 'photo';
      latin.photoPaths = ['a', 'b', 'c'];
      latin.photoRatios = [1.2, 0.8, 1.5];
      latin.showSenderName = false;
      latin.caption = 'x'.repeat(96);
      const cjkH: number = initialMessagePlaceholderHeight(cjk, 400, false);
      const latinH: number = initialMessagePlaceholderHeight(latin, 400, false);
      // 全宽 16vp/字 vs 8.8vp/字，行数差一倍上下（280vp 宽：6 行 vs 4 行）。
      expect(cjkH - latinH).assertEqual(2 * 22);
    });

    it('explicit_newlines_add_caption_lines', 0, () => {
      AppStorage.setOrCreate('msgTextSize', 16);
      const flat = groupOf(508);
      flat.head.contentType = 'photo';
      flat.photoPaths = ['a', 'b', 'c'];
      flat.photoRatios = [1.2, 0.8, 1.5];
      flat.showSenderName = false;
      flat.caption = 'abc';
      const broken = groupOf(509);
      broken.head.contentType = 'photo';
      broken.photoPaths = ['a', 'b', 'c'];
      broken.photoRatios = [1.2, 0.8, 1.5];
      broken.showSenderName = false;
      broken.caption = 'a\nb\nc';
      const flatH: number = initialMessagePlaceholderHeight(flat, 400, false);
      const brokenH: number = initialMessagePlaceholderHeight(broken, 400, false);
      expect(brokenH - flatH).assertEqual(2 * 22);
    });

    // 键回归：同 rowId 不同媒体比例不得共享缓存高度（旧键会撞车）。
    it('different_ratios_do_not_share_cached_heights', 0, () => {
      const wide = groupOf(503);
      wide.head.contentType = 'photo';
      wide.head.text = '';
      wide.head.photoWidth = 900;
      wide.head.photoHeight = 600;
      wide.showSenderName = false;
      const tall = groupOf(503);
      tall.head.contentType = 'photo';
      tall.head.text = '';
      tall.head.photoWidth = 600;
      tall.head.photoHeight = 900;
      tall.showSenderName = false;
      const wideH: number = initialMessagePlaceholderHeight(wide, 400, false);
      const tallH: number = initialMessagePlaceholderHeight(tall, 400, false);
      expect(wideH !== tallH).assertTrue();
    });
  });
}
