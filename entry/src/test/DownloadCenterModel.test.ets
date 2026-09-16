import { describe, it, expect } from '@ohos/hypium';
import {
  copyDownloadCenterItem, DC_KIND_APK, DC_KIND_AUDIO, DC_KIND_FILE, DC_KIND_PHOTO, DC_KIND_VIDEO, DC_KIND_VOICE,
  DC_SECTION_ACTIVE, DC_SECTION_DONE, DC_SOURCE_CACHE, DC_SOURCE_DISK, DC_SOURCE_MANAGER, DC_STATE_COMPLETE,
  DC_STATE_DOWNLOADING, DC_STATE_FAILED, DC_STATE_PARTIAL, DC_STATE_PAUSED, DC_STATE_QUEUED, DC_TAB_ALL,
  DownloadCenterItem, DownloadCenterSection, downloadCenterItemId, downloadCenterItemKey, etaSeconds,
  filterDownloadCenterItems, groupDownloadCenterItems, kindOfContentType, kindOfDiskDir, kindOfTdContentType,
  mergeDownloadCenterItems, nextSpeed, progressPercent, refineKindByName, storageBarWidths, DC_SORT_SIZE,
  DC_STATE_WAITING_NETWORK, DC_STATE_WAITING_WIFI, isUnsourcedCache
} from '../main/ets/util/downloadCenterModel';

// 下载中心纯逻辑：类型判定（含 APK）、三路合并去重、页签与关键词过滤、两段分组与排序、存储条、速度与剩余时间
// （2026-09-15，第三版照设计稿）。

function item(fileId: number, path: string, name: string, kind: string, state: string, source: string,
  mtime: number, preview: string = '', session: string = ''): DownloadCenterItem {
  return {
    fileId: fileId, path: path, name: name, kind: kind, size: 100, downloaded: 50, state: state,
    source: source, mtime: mtime, preview: preview, chatId: 0, messageId: 0, mimeType: '',
    session: session, savedLocal: false, speed: 0
  };
}

function names(items: DownloadCenterItem[]): string {
  return items.map((it: DownloadCenterItem): string => it.name).join(',');
}

export default function downloadCenterModelTest() {
  describe('downloadCenterModel', () => {
    it('三种来源的类型判定，安装包单独归 APK', 0, () => {
      expect(kindOfContentType('videoNote')).assertEqual(DC_KIND_VIDEO);
      expect(kindOfContentType('photo')).assertEqual(DC_KIND_PHOTO);
      expect(kindOfContentType('voice')).assertEqual(DC_KIND_VOICE);
      expect(kindOfContentType('file')).assertEqual(DC_KIND_FILE);
      expect(kindOfTdContentType('messageAudio')).assertEqual(DC_KIND_AUDIO);
      expect(kindOfTdContentType('messageDocument')).assertEqual(DC_KIND_FILE);
      expect(kindOfDiskDir('video_notes')).assertEqual(DC_KIND_VIDEO);
      expect(kindOfDiskDir('music')).assertEqual(DC_KIND_AUDIO);
      expect(refineKindByName(DC_KIND_FILE, 'Petrelgram-beta.APK')).assertEqual(DC_KIND_APK);
      expect(refineKindByName(DC_KIND_FILE, 'entry-default-signed.hap')).assertEqual(DC_KIND_APK);
      expect(refineKindByName(DC_KIND_FILE, 'report.pdf')).assertEqual(DC_KIND_FILE);
      expect(refineKindByName(DC_KIND_VIDEO, 'odd.apk')).assertEqual(DC_KIND_VIDEO);
    });

    it('进度：没下完封顶 99，完成才是 100', 0, () => {
      expect(progressPercent(999, 1000, false)).assertEqual(99);
      expect(progressPercent(1000, 1000, true)).assertEqual(100);
      expect(progressPercent(10, 0, false)).assertEqual(0);
      expect(progressPercent(430, 1000, false)).assertEqual(43);
    });

    it('合并：同一 fileId 下载管理器优先，磁盘文件按路径去重', 0, () => {
      const manager = [item(1, '/a.mp4', 'm', DC_KIND_VIDEO, DC_STATE_COMPLETE, DC_SOURCE_MANAGER, 3)];
      const cached = [
        item(1, '', 'c-dup', DC_KIND_VIDEO, DC_STATE_PARTIAL, DC_SOURCE_CACHE, 2),
        item(2, '', 'c', DC_KIND_VIDEO, DC_STATE_PARTIAL, DC_SOURCE_CACHE, 2)
      ];
      const disk = [
        item(0, '/a.mp4', 'disk-dup', DC_KIND_VIDEO, DC_STATE_COMPLETE, DC_SOURCE_DISK, 1),
        item(0, '/b.jpg', 'disk', DC_KIND_PHOTO, DC_STATE_COMPLETE, DC_SOURCE_DISK, 1)
      ];
      const merged = mergeDownloadCenterItems(manager, cached, disk);
      expect(names(merged)).assertEqual('m,c,disk');
      expect(downloadCenterItemId(merged[2])).assertEqual('p/b.jpg');
    });

    it('过滤：按页签；关键词匹配文件名、来源会话和摘要，不分大小写', 0, () => {
      const items = [
        item(1, '', 'Trip.MP4', DC_KIND_VIDEO, DC_STATE_PARTIAL, DC_SOURCE_CACHE, 1),
        item(2, '', 'song.mp3', DC_KIND_AUDIO, DC_STATE_COMPLETE, DC_SOURCE_MANAGER, 1, '旅行歌单'),
        item(3, '', 'doc.pdf', DC_KIND_FILE, DC_STATE_COMPLETE, DC_SOURCE_DISK, 1, '', '设计组')
      ];
      expect(filterDownloadCenterItems(items, DC_TAB_ALL, 'trip').length).assertEqual(1);
      expect(filterDownloadCenterItems(items, DC_KIND_AUDIO, '旅行').length).assertEqual(1);
      expect(filterDownloadCenterItems(items, DC_TAB_ALL, '设计').length).assertEqual(1);
      expect(filterDownloadCenterItems(items, DC_KIND_VIDEO, '').length).assertEqual(1);
      expect(filterDownloadCenterItems(items, DC_KIND_PHOTO, '').length).assertEqual(0);
    });

    it('分组：进行中（正在传 → 暂停 → 排队 → 失败，同档新到旧）→ 已完成（新到旧）', 0, () => {
      const items = [
        item(1, '', 'old-done', DC_KIND_FILE, DC_STATE_COMPLETE, DC_SOURCE_DISK, 1),
        item(2, '', 'paused', DC_KIND_FILE, DC_STATE_PAUSED, DC_SOURCE_MANAGER, 5),
        item(3, '', 'new-done', DC_KIND_FILE, DC_STATE_COMPLETE, DC_SOURCE_DISK, 9),
        item(4, '', 'downloading', DC_KIND_FILE, DC_STATE_DOWNLOADING, DC_SOURCE_MANAGER, 7),
        item(5, '', 'queued', DC_KIND_FILE, DC_STATE_QUEUED, DC_SOURCE_MANAGER, 8),
        item(6, '', 'failed', DC_KIND_FILE, DC_STATE_FAILED, DC_SOURCE_CACHE, 10),
        item(7, '', 'partial', DC_KIND_FILE, DC_STATE_PARTIAL, DC_SOURCE_CACHE, 6)
      ];
      const groups: DownloadCenterSection[] = groupDownloadCenterItems(items);
      expect(groups.map((g: DownloadCenterSection): string => g.section).join(','))
        .assertEqual(`${DC_SECTION_ACTIVE},${DC_SECTION_DONE}`);
      expect(names(groups[0].items)).assertEqual('downloading,partial,paused,queued,failed');
      expect(names(groups[1].items)).assertEqual('new-done,old-done');
      const onlyDone = groupDownloadCenterItems([item(8, '', 'd', DC_KIND_FILE, DC_STATE_COMPLETE, DC_SOURCE_DISK, 1)]);
      expect(onlyDone.length).assertEqual(1);
      expect(onlyDone[0].section).assertEqual(DC_SECTION_DONE);
    });

    it('存储条：缓存占两者之比，已存本地再乘 0.9；都为 0 各半', 0, () => {
      const w = storageBarWidths(300, 100);
      expect(Math.round(w.cache * 10)).assertEqual(750);
      expect(Math.round(w.local * 10)).assertEqual(225);
      const empty = storageBarWidths(0, 0);
      expect(Math.round(empty.cache)).assertEqual(50);
      expect(Math.round(empty.local * 10)).assertEqual(450);
    });

    it('速度平滑与剩余时间', 0, () => {
      expect(Math.round(nextSpeed(0, 1000, 1000))).assertEqual(1000);
      expect(Math.round(nextSpeed(1000, 3000, 1000))).assertEqual(1800);
      expect(nextSpeed(500, 100, 100)).assertEqual(500);
      expect(etaSeconds(1000, 400, 100)).assertEqual(6);
      expect(etaSeconds(1000, 400, 0)).assertEqual(-1);
      expect(etaSeconds(1000, 1000, 50)).assertEqual(-1);
    });

    it('签名随会话名、已存本地变化；复制出来的改动不影响原件', 0, () => {
      const a = item(9, '/x.jpg', 'x', DC_KIND_PHOTO, DC_STATE_COMPLETE, DC_SOURCE_DISK, 1);
      const b = copyDownloadCenterItem(a);
      b.savedLocal = true;
      expect(a.savedLocal).assertFalse();
      expect(downloadCenterItemKey(a) === downloadCenterItemKey(b)).assertFalse();
      const c = copyDownloadCenterItem(a);
      c.session = 'Kevin';
      expect(downloadCenterItemKey(a) === downloadCenterItemKey(c)).assertFalse();
      expect(downloadCenterItemId(a)).assertEqual(downloadCenterItemId(c));
    });

    it('等 Wi‑Fi / 等网络排在正在传之后、暂停之前', 0, () => {
      const items = [
        item(1, '', 'paused', DC_KIND_FILE, DC_STATE_PAUSED, DC_SOURCE_MANAGER, 9),
        item(2, '', 'wifi', DC_KIND_FILE, DC_STATE_WAITING_WIFI, DC_SOURCE_CACHE, 1),
        item(3, '', 'dl', DC_KIND_FILE, DC_STATE_DOWNLOADING, DC_SOURCE_MANAGER, 2),
        item(4, '', 'net', DC_KIND_FILE, DC_STATE_WAITING_NETWORK, DC_SOURCE_CACHE, 5)
      ];
      expect(names(groupDownloadCenterItems(items)[0].items)).assertEqual('dl,net,wifi,paused');
    });

    it('已完成按大小排：大到小，一样大的新到旧；来源不明的是磁盘扫描出来的', 0, () => {
      const a = item(1, '/a', 'a', DC_KIND_FILE, DC_STATE_COMPLETE, DC_SOURCE_DISK, 1);
      a.size = 10;
      const b = item(2, '/b', 'b', DC_KIND_FILE, DC_STATE_COMPLETE, DC_SOURCE_MANAGER, 2);
      b.size = 30;
      const c = item(3, '/c', 'c', DC_KIND_FILE, DC_STATE_COMPLETE, DC_SOURCE_CACHE, 3);
      c.size = 10;
      expect(names(groupDownloadCenterItems([a, b, c], DC_SORT_SIZE)[0].items)).assertEqual('b,c,a');
      expect(names(groupDownloadCenterItems([a, b, c])[0].items)).assertEqual('c,b,a');
      expect(isUnsourcedCache(a)).assertTrue();
      expect(isUnsourcedCache(b)).assertFalse();
    });
  });
}
