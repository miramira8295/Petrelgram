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

function withProgress(e: MessageEntry, percent: number): MessageEntry {
  const c: MessageEntry = cloneMessage(e);
  c.photoProgress = percent;
  return c;
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

    // 进度和路径在同一个事件里一起变（缩略图很小，只在完成那一刻 0→100）。
    // 只把路径摘出 key、把进度留下，整行重建照旧发生，只是触发字段换了个
    // 名字——真机实测净效果为零。这几条钉住"两个都不在 key 里"。
    it('单条媒体行：只有进度变化时 key 不变', 0, () => {
      const u = usersOf();
      const before: AlbumGroup[] = collapseAlbums([withProgress(media(5, '', 201, '', u), 0)]);
      const after: AlbumGroup[] = collapseAlbums([withProgress(media(5, '', 201, '', u), 100)]);
      expect(after[0].key).assertEqual(before[0].key);
    });

    it('单条媒体行：进度与路径同时到达时 key 仍然不变', 0, () => {
      const u = usersOf();
      const before: AlbumGroup[] = collapseAlbums([withProgress(media(5, '', 201, '', u), 0)]);
      const after: AlbumGroup[] =
        collapseAlbums([withProgress(media(5, '', 201, '/data/5.jpg', u), 100)]);
      expect(after[0].key).assertEqual(before[0].key);
    });

    it('相册行：只有某一格进度变化时 key 不变', 0, () => {
      const u = usersOf();
      const before: AlbumGroup[] = collapseAlbums([
        withProgress(media(1, 'alb1', 101, '', u), 0),
        withProgress(media(2, 'alb1', 102, '', u), 0)
      ]);
      const after: AlbumGroup[] = collapseAlbums([
        withProgress(media(1, 'alb1', 101, '', u), 0),
        withProgress(media(2, 'alb1', 102, '', u), 100)
      ]);
      expect(after[0].key).assertEqual(before[0].key);
    });

    // 失败态仍然要进 key：它把占位整个换成重试 UI，而且很少发生。
    it('单条媒体行：photoFailed 变化时 key 必须变', 0, () => {
      const u = usersOf();
      const a: MessageEntry = media(5, '', 201, '', u);
      const b: MessageEntry = cloneMessage(a);
      b.photoFailed = true;
      const before: AlbumGroup[] = collapseAlbums([a]);
      const after: AlbumGroup[] = collapseAlbums([b]);
      expect(after[0].key === before[0].key).assertFalse();
    });

    // 发送成功时 TDLib 把临时 id 换成真实 id，MessageStore 让新条目继承旧条目
    // 的 rowId（onSendSucceeded）。行 key 用 rowId，所以这一步 key 必须纹丝
    // 不动——否则列表把它当成新 item 销毁重建，界面上就是发完消息"闪一下"。
    it('单条媒体行：id 换新但 rowId 不变时 key 不变', 0, () => {
      const u = usersOf();
      const before: MessageEntry = media(5, '', 201, '/data/5.jpg', u);
      const after: MessageEntry = cloneMessage(before);
      after.id = 999;            // 真实 id 到位
      after.rowId = before.rowId; // 行身份由新条目继承
      expect(collapseAlbums([after])[0].key).assertEqual(collapseAlbums([before])[0].key);
    });

    it('单条媒体行：sendState 变化时 key 不变（走旁路通道）', 0, () => {
      const u = usersOf();
      const before: MessageEntry = media(5, '', 201, '/data/5.jpg', u);
      before.sendState = 'sending';
      const after: MessageEntry = cloneMessage(before);
      after.sendState = 'sent';
      expect(collapseAlbums([after])[0].key).assertEqual(collapseAlbums([before])[0].key);
    });

    it('单条媒体行：rowId 变化时 key 必须变', 0, () => {
      const u = usersOf();
      const before: MessageEntry = media(5, '', 201, '/data/5.jpg', u);
      const after: MessageEntry = cloneMessage(before);
      after.rowId = 777;
      expect(collapseAlbums([after])[0].key === collapseAlbums([before])[0].key).assertFalse();
    });
  });
}
