import { describe, it, expect } from '@ohos/hypium';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdObject, TdBridge } from '../main/ets/tdkit/TdTypes';
import { UserStore } from '../main/ets/store/UserStore';
import { buildMessageEntry, cloneMessage, MessageEntry } from '../main/ets/store/MessageEntry';
import { collapseAlbums, AlbumGroup } from '../main/ets/util/collapseAlbums';

class FakeBridge implements TdBridge {
  onReceive: (json: string) => void = (): void => {};
  sent: string[] = [];
  init(cb: (json: string) => void): void { this.onReceive = cb; }
  send(json: string): void { this.sent.push(json); }
}

function usersOf(): UserStore {
  const b = new FakeBridge();
  const c = new TdClient(b);
  const u = new UserStore(c);
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

// 一条媒体消息：albumId 非空即为相册成员。
function media(id: number, albumId: string, fileId: number, path: string,
  users: UserStore): MessageEntry {
  const e: MessageEntry = cloneMessage(baseEntry(id, users));
  e.contentType = 'photo';
  e.albumId = albumId;
  e.photoFileId = fileId;
  e.photoPath = path;
  return e;
}

export default function collapseAlbumsKeyTest() {
  describe('collapseAlbumsKey', () => {
    it('相册行：只有缩略图路径变化时 key 不变', 0, () => {
      const u = usersOf();
      const before: AlbumGroup[] = collapseAlbums([
        media(1, 'alb1', 101, '', u), media(2, 'alb1', 102, '', u)
      ]);
      const after: AlbumGroup[] = collapseAlbums([
        media(1, 'alb1', 101, '/data/1.jpg', u), media(2, 'alb1', 102, '/data/2.jpg', u)
      ]);
      expect(after.length).assertEqual(before.length);
      expect(after[0].key).assertEqual(before[0].key);
    });

    it('相册行：缩略图 fileId 变化时 key 必须变', 0, () => {
      const u = usersOf();
      const before: AlbumGroup[] = collapseAlbums([
        media(1, 'alb1', 101, '/data/1.jpg', u), media(2, 'alb1', 102, '/data/2.jpg', u)
      ]);
      const after: AlbumGroup[] = collapseAlbums([
        media(1, 'alb1', 999, '/data/1.jpg', u), media(2, 'alb1', 102, '/data/2.jpg', u)
      ]);
      expect(after[0].key === before[0].key).assertFalse();
    });

    it('单条媒体行：只有路径变化时 key 不变', 0, () => {
      const u = usersOf();
      const before: AlbumGroup[] = collapseAlbums([media(5, '', 201, '', u)]);
      const after: AlbumGroup[] = collapseAlbums([media(5, '', 201, '/data/5.jpg', u)]);
      expect(after[0].key).assertEqual(before[0].key);
    });

    it('单条媒体行：photoFileId 变化时 key 必须变', 0, () => {
      const u = usersOf();
      const before: AlbumGroup[] = collapseAlbums([media(5, '', 201, '/data/5.jpg', u)]);
      const after: AlbumGroup[] = collapseAlbums([media(5, '', 202, '/data/5.jpg', u)]);
      expect(after[0].key === before[0].key).assertFalse();
    });
  });
}
