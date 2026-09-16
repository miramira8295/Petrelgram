import { describe, expect, it } from '@ohos/hypium';
import { MessageEntry, buildMessageEntry } from '../main/ets/store/MessageEntry';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdBridge } from '../main/ets/tdkit/TdTypes';
import { UserStore } from '../main/ets/store/UserStore';
import { AlbumGroup, collapseAlbums } from '../main/ets/util/collapseAlbums';
import {
  DC_KIND_FILE, DC_KIND_PHOTO, DC_KIND_VIDEO, DC_SORT_TIME, DC_SOURCE_CACHE, DC_SOURCE_DISK, DC_STATE_COMPLETE,
  DC_STATE_DOWNLOADING, DC_TAB_ALL, DownloadCenterItem
} from '../main/ets/util/downloadCenterModel';
import {
  DC_VIEWER_ALBUM_ID, DownloadViewerSet, buildDownloadViewerSet, viewableInViewer, viewerBaseMessage,
  viewerEntryFor, viewerIndexOf, viewerKindsForTab, viewerMessageIdAt
} from '../main/ets/util/downloadViewerSet';

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
  return users;
}

function item(fileId: number, kind: string, state: string, mtime: number, source: string = DC_SOURCE_CACHE): DownloadCenterItem {
  const done: boolean = state === DC_STATE_COMPLETE;
  return {
    fileId: fileId, path: done ? `/data/f${fileId}` : '', name: `f${fileId}.bin`, kind: kind, size: 1000,
    downloaded: done ? 1000 : 400, state: state, source: source, mtime: mtime, preview: '', chatId: 7,
    messageId: fileId * 1048576, mimeType: kind === DC_KIND_VIDEO ? 'video/mp4' : 'image/jpeg', session: 'Ann',
    savedLocal: false, speed: 0
  };
}

function idsOf(set: DownloadViewerSet | null): number[] {
  return set === null ? [] : set.items.map((x: DownloadCenterItem): number => x.fileId);
}

// 下载中心接聊天的媒体查看器：挑哪些、按什么顺序、从第几张开始。2026-09-15。
export default function downloadViewerSetTest() {
  describe('downloadViewerSet', () => {
    it('页签决定可滑动的类型：全部混排、图片 / 视频各管各的、其它页签不进查看器', 0, (): void => {
      expect(viewerKindsForTab(DC_TAB_ALL).join(',')).assertEqual('photo,video');
      expect(viewerKindsForTab(DC_KIND_PHOTO).join(',')).assertEqual('photo');
      expect(viewerKindsForTab(DC_KIND_VIDEO).join(',')).assertEqual('video');
      expect(viewerKindsForTab(DC_KIND_FILE).length).assertEqual(0);
    });

    const items: DownloadCenterItem[] = [
      item(1, DC_KIND_PHOTO, DC_STATE_COMPLETE, 3000),
      item(2, DC_KIND_VIDEO, DC_STATE_COMPLETE, 2000),
      item(3, DC_KIND_PHOTO, DC_STATE_COMPLETE, 1000),
      item(4, DC_KIND_VIDEO, DC_STATE_DOWNLOADING, 500),
      item(5, DC_KIND_PHOTO, DC_STATE_DOWNLOADING, 400),
      item(6, DC_KIND_FILE, DC_STATE_COMPLETE, 900)
    ];

    it('图片页签只滑下完的图片，按列表顺序，从点的那张开始', 0, (): void => {
      const set: DownloadViewerSet | null = buildDownloadViewerSet(items, items[2], DC_KIND_PHOTO, '', DC_SORT_TIME);
      expect(idsOf(set).join(',')).assertEqual('1,3');
      expect(set?.startIndex ?? -1).assertEqual(1);
    });

    it('全部页签图片视频混着滑，没下完的视频在进行中那段、排在最前', 0, (): void => {
      const set: DownloadViewerSet | null = buildDownloadViewerSet(items, items[1], DC_TAB_ALL, '', DC_SORT_TIME);
      expect(idsOf(set).join(',')).assertEqual('4,1,2,3');
      expect(set?.startIndex ?? -1).assertEqual(2);
    });

    it('进不了查看器的：没下完的图片、没路径又没 fileId 的视频、别的类型', 0, (): void => {
      expect(buildDownloadViewerSet(items, items[4], DC_TAB_ALL, '', DC_SORT_TIME) === null).assertTrue();
      expect(buildDownloadViewerSet(items, items[5], DC_TAB_ALL, '', DC_SORT_TIME) === null).assertTrue();
    });

    // 磁盘扫描出来的视频 fileId 恒为 0（TDLib 没有「路径 → fileId」的接口），
    // 但**文件就在本地**：播放器的取源顺序是 localPath 优先（StreamingVideoPlayer
    // 里 sourceUrl = localPath，只有"没路径又没 fileId"才放弃）。所以它该进查看器，
    // 而不是甩给系统播放器（用户 2026-09-16：「视频现在不会进入媒体查看器」）。
    it('磁盘扫出来的完整视频照样进查看器', 0, (): void => {
      const diskVideo: DownloadCenterItem = item(0, DC_KIND_VIDEO, DC_STATE_COMPLETE, 800, DC_SOURCE_DISK);
      const set: DownloadViewerSet | null =
        buildDownloadViewerSet([...items, diskVideo], diskVideo, DC_TAB_ALL, '', DC_SORT_TIME);
      expect(set !== null).assertTrue();
      expect(viewableInViewer(diskVideo)).assertTrue();
    });

    // 但「没下完、又没有 fileId」是真的播不了：既没有本地文件也没法流式。
    it('没下完又没有 fileId 的视频仍然进不去', 0, (): void => {
      const orphan: DownloadCenterItem = item(0, DC_KIND_VIDEO, DC_STATE_DOWNLOADING, 700, DC_SOURCE_DISK);
      expect(viewableInViewer(orphan)).assertFalse();
    });

    it('临时编号与下标互换', 0, (): void => {
      expect(viewerMessageIdAt(0)).assertEqual(1);
      expect(viewerIndexOf(viewerMessageIdAt(5))).assertEqual(5);
    });

    it('条目转成查看器认的消息：图片给原图路径，视频没下完只给 fileId，整组拼成一个相册', 0, (): void => {
      const base: MessageEntry = buildMessageEntry(viewerBaseMessage(), usersOf());
      const photo: MessageEntry = viewerEntryFor(base, items[0], 1);
      expect(photo.contentType).assertEqual('photo');
      expect(photo.photoFullPath).assertEqual('/data/f1');
      expect(photo.id).assertEqual(1);
      expect(photo.rowId).assertEqual(1);
      const done: MessageEntry = viewerEntryFor(base, items[1], 2);
      expect(done.contentType).assertEqual('video');
      expect(done.videoPath).assertEqual('/data/f2');
      const streaming: MessageEntry = viewerEntryFor(base, items[3], 3);
      expect(streaming.videoPath).assertEqual('');
      expect(streaming.videoFileId).assertEqual(4);
      expect(streaming.videoProgress).assertEqual(40);
      const groups: AlbumGroup[] = collapseAlbums([photo, done, streaming]);
      expect(groups.length).assertEqual(1);
      expect(groups[0].memberIds.join(',')).assertEqual('1,2,3');
      expect(groups[0].head.albumId).assertEqual(DC_VIEWER_ALBUM_ID);
    });
  });
}
