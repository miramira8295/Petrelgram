import { describe, expect, it } from '@ohos/hypium';
import { buildMessageEntry, MessageEntry } from '../main/ets/store/MessageEntry';
import { TdBridge, TdObject } from '../main/ets/tdkit/TdTypes';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { UserStore } from '../main/ets/store/UserStore';
import { AlbumGroup } from '../main/ets/util/collapseAlbums';
import { slotKey } from '../main/ets/pages/chat/playSlot';
import { albumReuseShape, rowPlaySlotKey } from '../main/ets/util/messageBubblePrepare';

class FakeBridge implements TdBridge {
  onReceive: (json: string) => void = (): void => {};
  init(cb: (json: string) => void): void { this.onReceive = cb; }
  send(_json: string): void {}
}

function usersOf(): UserStore {
  const bridge = new FakeBridge();
  const client = new TdClient(bridge);
  const users = new UserStore(client);
  client.start();
  const user: TdObject = { '@type': 'user' };
  user['id'] = 7;
  user['first_name'] = 'Ann';
  const update: TdObject = { '@type': 'updateUser' };
  update['user'] = user;
  bridge.onReceive(JSON.stringify(update));
  return users;
}

function headEntry(id: number): MessageEntry {
  const formatted: TdObject = { '@type': 'formattedText' };
  formatted['text'] = '';
  const content: TdObject = { '@type': 'messageText' };
  content['text'] = formatted;
  const sender: TdObject = { '@type': 'messageSenderUser' };
  sender['user_id'] = 7;
  const message: TdObject = { '@type': 'message' };
  message['id'] = id;
  message['is_outgoing'] = false;
  message['sender_id'] = sender;
  message['date'] = 100;
  message['content'] = content;
  return buildMessageEntry(message, usersOf());
}

// ArkTS 不支持 Partial<T>，用等价的「全字段可选」接口代替（同 RowReuseId.test）。
// 这两个纯函数只读 memberIds 与四条并行数组，其余字段给中性值即可。
interface AlbumOverrides {
  paths?: string[];
  fileIds?: number[];
  isVideo?: boolean[];
  failed?: boolean[];
}

function groupOf(memberIds: number[], over: AlbumOverrides = {}): AlbumGroup {
  const head: MessageEntry = headEntry(memberIds[0]);
  const empty: string[] = [];
  const paths: string[] = over.paths ?? empty;
  const zeros: number[] = [];
  const falses: boolean[] = [];
  for (let i = 0; i < paths.length; i++) {
    zeros.push(0);
    falses.push(false);
  }
  const noEntities: TdObject[] = [];
  return {
    key: `group-${memberIds[0]}`,
    head,
    memberIds,
    rowMemberIds: memberIds,
    photoPaths: paths,
    photoFileIds: over.fileIds ?? zeros,
    photoRatios: zeros,
    photoIsVideo: over.isVideo ?? falses,
    photoIsLive: falses,
    photoProgress: zeros,
    photoFailed: over.failed ?? falses,
    videoFileIds: zeros,
    videoFileSizes: zeros,
    videoDurations: zeros,
    videoMimeTypes: empty,
    caption: '',
    captionEntities: noEntities,
    dateLabel: '',
    showAvatar: true,
    showSenderName: true
  };
}

// 一块两图相册：第一格图片、缩略图已落地、有封面文件、没失败；第二格视频、
// 缩略图还没落地、没有可下载的封面、下载失败过。
function twoUp(): AlbumGroup {
  return groupOf([101, 102], {
    paths: ['/cache/a.jpg', ''],
    fileIds: [11, 0],
    isVideo: [false, true],
    failed: [false, true]
  });
}

export default function messageBubblePrepareTest() {
  describe('MessageBubblePrepare', () => {
    // 形状串的逐字契约。它进的是行复用 id：多一位少一位都会让整条时间线换一批
    // 复用桶，所以这里钉的是**完整字符串**，不是「两者不等」。
    // 张数 `2`，然后每格四位状态 + 一位播放位：
    //   格 0 = p(图) r(路径已落地) f(有封面文件) o(未失败) i(非播放位)
    //   格 1 = v(视频) n(无路径) z(无封面文件) e(失败) i(非播放位)
    it('two_photo_album_spells_out_every_cell', 0, () => {
      expect(albumReuseShape(twoUp(), '')).assertEqual('2:prfoi:vnzei');
    });

    // 空相册（普通消息行）只剩张数。
    it('a_non_album_row_is_just_its_count', 0, () => {
      expect(albumReuseShape(groupOf([101]), '')).assertEqual('0');
    });

    // 播放位只点亮**它自己那一格**：键里带着相册下标，所以同一条消息的另一格
    // 不会跟着变。
    it('the_play_slot_lights_exactly_one_cell', 0, () => {
      expect(albumReuseShape(twoUp(), slotKey(102, 1))).assertEqual('2:prfoi:vnzes');
      expect(albumReuseShape(twoUp(), slotKey(101, 0))).assertEqual('2:prfos:vnzei');
      // 同一条消息、错的下标：一格都不点亮。
      expect(albumReuseShape(twoUp(), slotKey(101, 1))).assertEqual('2:prfoi:vnzei');
    });

    // 这是 rowPlaySlotKey 那段注释保护的不变式的另一半：别人家的播放位不能
    // 改动本行的形状串——否则播放位一变，整屏的复用 id 一起变。
    it('another_rows_play_slot_leaves_this_row_untouched', 0, () => {
      const foreign: string = slotKey(999, 0);
      expect(albumReuseShape(twoUp(), foreign)).assertEqual(albumReuseShape(twoUp(), ''));
    });

    // 参数顺序写反的哨兵：形状串对同样的入参必须逐次一致（缓存键的前提）。
    it('the_shape_is_stable_for_the_same_inputs', 0, () => {
      const key: string = slotKey(102, 1);
      expect(albumReuseShape(twoUp(), key)).assertEqual(albumReuseShape(twoUp(), key));
    });

    // 没有任何行在播时，人人都是空串。
    it('no_global_slot_means_no_row_slot', 0, () => {
      expect(rowPlaySlotKey(twoUp(), '')).assertEqual('');
    });

    // 拥有播放位的那一行拿到**原样**的键（气泡侧还要拿它和自己的成员 id 比）。
    it('the_owning_row_gets_the_key_verbatim', 0, () => {
      const key: string = slotKey(102, 1);
      expect(rowPlaySlotKey(twoUp(), key)).assertEqual(key);
    });

    // 归属只看消息 id，不看相册下标——slotKeyMessageId 把下标那一段丢掉。
    it('ownership_is_decided_by_message_id_only', 0, () => {
      expect(rowPlaySlotKey(twoUp(), slotKey(101, 7))).assertEqual(slotKey(101, 7));
    });

    // 不拥有播放位的行一律拿空串。这条就是那段【为什么必须行局部化】：让它
    // 返回原值，整屏每一行的 cacheKey 会随全局播放位一起作废。
    it('every_other_row_gets_an_empty_string', 0, () => {
      const other: AlbumGroup = groupOf([201, 202]);
      expect(rowPlaySlotKey(other, slotKey(102, 1))).assertEqual('');
    });

    // 解析不出消息 id 的键（slotKeyMessageId 返回 0）不该意外命中任何行。
    it('a_malformed_key_owns_nothing', 0, () => {
      expect(rowPlaySlotKey(twoUp(), 'nonsense')).assertEqual('');
    });

    // 单图相册：一格也把五位状态写全。张数是 `1`——`0` 的意思是「这行根本不是
    // 相册」，走的是另一条气泡分支，两者不能混。
    it('a_single_photo_album_still_spells_its_one_cell', 0, () => {
      const one: AlbumGroup = groupOf([301], { paths: ['/cache/one.jpg'], fileIds: [5] });
      expect(albumReuseShape(one, '')).assertEqual('1:prfoi');
    });

    // 三格混排：视频/图片、落地/未落地、失败/正常各占一格。逐格独立求值，前一
    // 格的状态不会串到后一格（拼串时少一个 `:` 或少写一位都在这条上现形）。
    it('cells_do_not_bleed_into_each_other', 0, () => {
      const three: AlbumGroup = groupOf([401, 402, 403], {
        paths: ['', '/cache/b.jpg', '/cache/c.jpg'],
        fileIds: [0, 21, 22],
        isVideo: [true, false, false],
        failed: [false, false, true]
      });
      expect(albumReuseShape(three, '')).assertEqual('3:vnzoi:prfoi:prfei');
    });

    // 下载进度**故意不进**形状串。缩略图进度是每几十毫秒都在动的量，走旁路通道
    // 自己刷新；一旦进了行复用 id，下载期间这一行会反复换复用桶。这条就是那句
    // 「不放下载进度这种走旁路通道的高频量」的闸。
    it('download_progress_never_moves_the_shape', 0, () => {
      const busy: AlbumGroup = twoUp();
      busy.photoProgress = [0, 63];
      expect(albumReuseShape(busy, '')).assertEqual(albumReuseShape(twoUp(), ''));
    });

    // 单条视频消息（不是相册）的播放位下标是 **-1**——见 prepareMessageBubble 的
    // `playSlotActive: rowSlot === slotKey(g.head.id, -1)`。这才是最常见的「一条
    // 视频在播」，所以归属判定里不许加「下标必须 >= 0」之类的收紧。
    it('a_plain_video_row_owns_its_minus_one_slot', 0, () => {
      const plain: AlbumGroup = groupOf([501]);
      expect(rowPlaySlotKey(plain, slotKey(501, -1))).assertEqual(slotKey(501, -1));
      expect(rowPlaySlotKey(plain, slotKey(502, -1))).assertEqual('');
    });
  });
}
