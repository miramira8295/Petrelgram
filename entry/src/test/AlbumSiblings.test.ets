import { describe, it, expect } from '@ohos/hypium';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdObject, TdBridge } from '../main/ets/tdkit/TdTypes';
import { UserStore } from '../main/ets/store/UserStore';
import { buildMessageEntry, cloneMessage, MessageEntry } from '../main/ets/store/MessageEntry';
import {
  collapseAlbums, AlbumGroup, albumSiblingIds, albumIndexOfMember
} from '../main/ets/util/collapseAlbums';

// albumSiblingIds / albumIndexOfMember 的测试（第二轮第 6 项）。
//
// 这两个函数原来是 ChatPage 的私有方法（siblingIdsFor / albumIndexForViewer），
// 对 groups 纯读、不碰任何页面状态，待在页面里只是因为当初顺手读了 this.groups，
// 因此一条覆盖都没有。上移到 util 之后才钉得住。
//
// 它们不是可有可无的小工具：全屏查看器的 Swiper 靠 albumSiblingIds 决定有几页，
// closeViewer 的播放位交接靠 albumIndexOfMember 把 viewerMsgId 换算成
// PlaySlotRegistry 的 (messageId, albumIndex) 坐标。算错就是"退出查看器后
// 播放位落在相册的另一格上"。
//
// 构造 groups 的写法照抄 CollapseAlbumsKey.test.ets：用真实的
// buildMessageEntry + collapseAlbums 现算，不手搭 AlbumGroup 字面量——
// memberIds 的形状必须是真的。

class FakeBridge implements TdBridge {
  onReceive: (json: string) => void = (): void => {};
  sent: string[] = [];
  init(cb: (json: string) => void): void { this.onReceive = cb; }
  send(json: string): void { this.sent.push(json); }
}

function usersOf(): UserStore {
  const b: FakeBridge = new FakeBridge();
  const c: TdClient = new TdClient(b);
  const u: UserStore = new UserStore(c);
  c.start();
  const user: TdObject = { '@type': 'user' };
  user['id'] = 7;
  user['first_name'] = 'Ann';
  const upd: TdObject = { '@type': 'updateUser' };
  upd['user'] = user;
  b.onReceive(JSON.stringify(upd));
  return u;
}

function baseEntry(id: number, users: UserStore): MessageEntry {
  const ft: TdObject = { '@type': 'formattedText' };
  ft['text'] = '';
  const content: TdObject = { '@type': 'messageText' };
  content['text'] = ft;
  const sender: TdObject = { '@type': 'messageSenderUser' };
  sender['user_id'] = 7;
  const m: TdObject = { '@type': 'message' };
  m['id'] = id;
  m['is_outgoing'] = false;
  m['sender_id'] = sender;
  m['date'] = 1000;
  m['content'] = content;
  return buildMessageEntry(m, users);
}

function media(id: number, albumId: string, users: UserStore): MessageEntry {
  const e: MessageEntry = cloneMessage(baseEntry(id, users));
  e.contentType = 'photo';
  e.albumId = albumId;
  e.photoFileId = id + 100;
  e.photoPath = `/data/${id}.jpg`;
  return e;
}

// 一组三格的相册 + 一条普通文本，覆盖两类形状。
// 放在模块层而不是 describe 里：ArkTS 不允许嵌套函数声明（arkts-no-nested-funcs）。
function groupsOf(): AlbumGroup[] {
  const users: UserStore = usersOf();
  const list: MessageEntry[] = [
    media(11, 'A1', users),
    media(12, 'A1', users),
    media(13, 'A1', users),
    baseEntry(20, users)
  ];
  return collapseAlbums(list);
}

export default function albumSiblingsTest() {
  describe('AlbumSiblings', () => {

    it('相册成员拿到整组的 memberIds', 0, () => {
      const ids: number[] = albumSiblingIds(groupsOf(), 12);
      expect(ids.length).assertEqual(3);
      expect(ids.indexOf(11) >= 0).assertTrue();
      expect(ids.indexOf(12) >= 0).assertTrue();
      expect(ids.indexOf(13) >= 0).assertTrue();
    });

    // memberIds.length > 1 这个判据不能省：collapseAlbums 给单条消息也建
    // 一个 group，memberIds 里就它一个。不判长度的话，单条消息会被当成
    // "相册的第 0 格"，查看器的 Swiper 也会按相册去渲染。
    it('非相册消息只返回它自己', 0, () => {
      const ids: number[] = albumSiblingIds(groupsOf(), 20);
      expect(ids.length).assertEqual(1);
      expect(ids[0]).assertEqual(20);
    });

    it('不在列表里的 id 也返回它自己，查看器永远拿得到非空数组', 0, () => {
      const ids: number[] = albumSiblingIds(groupsOf(), 999);
      expect(ids.length).assertEqual(1);
      expect(ids[0]).assertEqual(999);
    });

    it('相册成员的 albumIndex 是它在 memberIds 里的下标', 0, () => {
      const groups: AlbumGroup[] = groupsOf();
      const ids: number[] = albumSiblingIds(groups, 12);
      expect(albumIndexOfMember(groups, 12)).assertEqual(ids.indexOf(12));
      expect(albumIndexOfMember(groups, 11)).assertEqual(ids.indexOf(11));
      expect(albumIndexOfMember(groups, 13)).assertEqual(ids.indexOf(13));
    });

    // -1 不是"没找到"，是"整条消息"这个合法取值——PlaySlotRegistry 的 slotKey
    // 靠它区分"整条"与"相册第 n 格"。不在相册里的消息本来就该按整条记，
    // 所以找不到的那条也回 -1，两者同义。
    it('非相册消息与找不到的 id 都是 -1（整条消息）', 0, () => {
      const groups: AlbumGroup[] = groupsOf();
      expect(albumIndexOfMember(groups, 20)).assertEqual(-1);
      expect(albumIndexOfMember(groups, 999)).assertEqual(-1);
    });

    it('空 groups 不抛，按整条消息处理', 0, () => {
      const empty: AlbumGroup[] = [];
      expect(albumSiblingIds(empty, 5).length).assertEqual(1);
      expect(albumIndexOfMember(empty, 5)).assertEqual(-1);
    });
  });
}
