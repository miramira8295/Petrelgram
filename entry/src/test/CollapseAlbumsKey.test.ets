import { describe, it, expect } from '@ohos/hypium';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdObject, TdBridge } from '../main/ets/tdkit/TdTypes';
import { UserStore } from '../main/ets/store/UserStore';
import { buildMessageEntry, cloneMessage, MessageEntry } from '../main/ets/store/MessageEntry';
import { collapseAlbums, AlbumGroup } from '../main/ets/util/collapseAlbums';
import {
  repeatRowKey, reuseUnchangedRows
} from '../main/ets/pages/chat/AlbumGroupDataSource';

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

function albumVideo(id: number, albumId: string, fileId: number, size: number,
  duration: number, users: UserStore): MessageEntry {
  const e: MessageEntry = media(id, albumId, fileId + 1000, `/data/${id}.jpg`, users);
  e.contentType = 'video';
  e.videoFileId = fileId;
  e.videoFileSize = size;
  e.videoDuration = duration;
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

    it('混合相册：视频时长和大小按格透传，元信息变化时刷新行', 0, () => {
      const u = usersOf();
      const photo: MessageEntry = media(1, 'mixed', 101, '/data/1.jpg', u);
      const video: MessageEntry = albumVideo(2, 'mixed', 202, 7340032, 42, u);
      const before: AlbumGroup = collapseAlbums([photo, video])[0];
      expect(before.videoFileSizes.join(',')).assertEqual('0,7340032');
      expect(before.videoDurations.join(',')).assertEqual('0,42');

      const changedVideo: MessageEntry = cloneMessage(video);
      changedVideo.videoFileSize = 8388608;
      const after: AlbumGroup = collapseAlbums([photo, changedVideo])[0];
      expect(after.key === before.key).assertFalse();
    });

    it('单条媒体行：只有路径变化时 key 不变', 0, () => {
      const u = usersOf();
      const before: AlbumGroup[] = collapseAlbums([media(5, '', 201, '', u)]);
      const after: AlbumGroup[] = collapseAlbums([media(5, '', 201, '/data/5.jpg', u)]);
      expect(after[0].key).assertEqual(before[0].key);
    });

    // 静态贴纸也由行展示通道拿到最新 MessageEntry，不再靠重命名列表 item。
    it('静态贴纸行：photoPath 到达时 key 保持稳定', 0, () => {
      const u = usersOf();
      const before: MessageEntry = media(9, '', 301, '', u);
      before.contentType = 'sticker';
      before.stickerFormat = 'webp';
      const after: MessageEntry = cloneMessage(before);
      after.photoPath = '/data/9.webp';
      expect(collapseAlbums([after])[0].key).assertEqual(collapseAlbums([before])[0].key);
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

    it('单条媒体行：photoFailed 变化时 key 保持稳定', 0, () => {
      const u = usersOf();
      const a: MessageEntry = media(5, '', 201, '', u);
      const b: MessageEntry = cloneMessage(a);
      b.photoFailed = true;
      const before: AlbumGroup[] = collapseAlbums([a]);
      const after: AlbumGroup[] = collapseAlbums([b]);
      expect(after[0].key).assertEqual(before[0].key);
    });

    it('相册行：某格 photoFailed 变化时 key 保持稳定', 0, () => {
      const u = usersOf();
      const a1: MessageEntry = media(5, 'alb2', 201, '', u);
      const a2: MessageEntry = media(6, 'alb2', 202, '', u);
      const b1: MessageEntry = cloneMessage(a1);
      const b2: MessageEntry = cloneMessage(a2);
      b2.photoFailed = true;
      expect(collapseAlbums([b1, b2])[0].key)
        .assertEqual(collapseAlbums([a1, a2])[0].key);
    });

    it('下载展示态和译文变化时 key 保持稳定', 0, () => {
      const u = usersOf();
      const before: MessageEntry = media(7, '', 301, '', u);
      before.contentType = 'video';
      before.videoFileId = 401;
      const after: MessageEntry = cloneMessage(before);
      after.videoProgress = 63;
      after.videoFailed = true;
      after.mediaDownloadActive = true;
      after.videoPath = '/data/video.mp4';
      after.translatedText = 'translated';
      after.translatedLang = 'en';
      after.translationHidden = true;
      expect(collapseAlbums([after])[0].key).assertEqual(collapseAlbums([before])[0].key);
    });

    // 发送成功时 TDLib 把临时 id 换成真实 id，MessageStore 让新条目继承旧条目
    // 的 rowId（onSendSucceeded）。两件事必须同时成立：
    //   行身份（rowId）不变 —— 列表才不会把它当成新 item 销毁重建，
    //                          界面上就是发完消息不"闪一下"；
    //   内容 key 变          —— 数据源才会发 CHANGE，气泡拿到带真实 id 的新
    //                          数据。这一条原来是反着钉的，正是 issue #66
    //                          「刚发的消息无法编辑」的成因：key 不变则不发
    //                          CHANGE，@Prop msg 一直揣着作废的临时 id。
    it('单条媒体行：id 换新而 rowId 不变——行身份不变、内容 key 变', 0, () => {
      const u = usersOf();
      const before: MessageEntry = media(5, '', 201, '/data/5.jpg', u);
      const after: MessageEntry = cloneMessage(before);
      after.id = 999;            // 真实 id 到位
      after.rowId = before.rowId; // 行身份由新条目继承
      const g0: AlbumGroup = collapseAlbums([before])[0];
      const g1: AlbumGroup = collapseAlbums([after])[0];
      expect(g1.head.rowId).assertEqual(g0.head.rowId);
      expect(g1.rowMemberIds.join(',')).assertEqual(g0.rowMemberIds.join(','));
      expect(g1.key === g0.key).assertFalse();
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

    it('相册：成员 id 换了而 rowId 不变时，key 必须变', 0, () => {
      const u = usersOf();
      const a: MessageEntry = media(11, 'alb', 201, '/data/a.jpg', u);
      const b: MessageEntry = media(12, 'alb', 202, '/data/b.jpg', u);
      const a2: MessageEntry = cloneMessage(a);
      const b2: MessageEntry = cloneMessage(b);
      a2.id = 111; b2.id = 112;    // rowId 保持 11 / 12
      expect(collapseAlbums([a2, b2])[0].key === collapseAlbums([a, b])[0].key).assertFalse();
    });

    it('历史分页补全相册：外层行身份稳定，内容对象和内部成员必须刷新', 0, () => {
      const u = usersOf();
      const first: MessageEntry = media(11, 'cross-page', 201, '/data/a.jpg', u);
      first.text = 'caption from older page';
      const second: MessageEntry = media(12, 'cross-page', 202, '/data/b.jpg', u);
      const partial: AlbumGroup = collapseAlbums([second])[0];
      const complete: AlbumGroup = collapseAlbums([first, second])[0];

      // List 仍能用同一个 key 保住位置；新 item 会让 Repeat 刷新气泡。
      expect(repeatRowKey(partial, 0, 0)).assertEqual(repeatRowKey(complete, 0, 0));
      expect(partial.key === complete.key).assertFalse();
      const merged: AlbumGroup[] = reuseUnchangedRows([partial], [complete]);
      expect(merged[0] === complete).assertTrue();
      expect(merged[0].memberIds.join(',')).assertEqual('11,12');
      expect(merged[0].caption).assertEqual('caption from older page');
    });

    it('同一 albumId 被拆成两段时 Repeat key 仍唯一', 0, () => {
      const u = usersOf();
      const separator: MessageEntry = baseEntry(12, u);
      separator.text = 'separator';
      const groups: AlbumGroup[] = collapseAlbums([
        media(11, 'split-album', 201, '/data/a.jpg', u),
        separator,
        media(13, 'split-album', 203, '/data/c.jpg', u)
      ]);

      expect(groups.length).assertEqual(3);
      expect(repeatRowKey(groups[0], 0, 0) === repeatRowKey(groups[2], 0, 0)).assertFalse();
    });

    it('非图片视频媒体组不能共用 albumId 作 Repeat key', 0, () => {
      const u = usersOf();
      const first: MessageEntry = baseEntry(21, u);
      first.contentType = 'document';
      first.albumId = 'document-album';
      const second: MessageEntry = baseEntry(22, u);
      second.contentType = 'document';
      second.albumId = 'document-album';
      const groups: AlbumGroup[] = collapseAlbums([first, second]);

      expect(groups.length).assertEqual(2);
      expect(repeatRowKey(groups[0], 0, 0) === repeatRowKey(groups[1], 0, 0)).assertFalse();
    });
  });
}
