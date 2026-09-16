import { describe, it, expect } from '@ohos/hypium';
import { CacheRecord } from '../main/ets/util/cacheRegistryModel';
import {
  aggregateCachePercent, BG_WAIT_NETWORK, BG_WAIT_NONE, BG_WAIT_WIFI, cacheWaitReason, messageHasFile,
  resumableCacheRecords
} from '../main/ets/util/backgroundCacheModel';

// 后台缓存：重启后续上哪几条、来源消息里还是不是那个文件、网络门控、通知栏汇总进度（2026-09-15）。

function rec(fileId: number, background: boolean, paused: boolean, chatId: number = 1): CacheRecord {
  return {
    fileId: fileId, chatId: chatId, messageId: 1, kind: 'video', name: '', size: 0, mimeType: '', preview: '',
    background: background, addedAt: 1, paused: paused
  };
}

export default function backgroundCacheModelTest() {
  describe('backgroundCacheModel', () => {
    it('只续上点过后台缓存、没被暂停、知道来源消息的', 0, () => {
      const list: CacheRecord[] = [rec(1, true, false), rec(2, false, false), rec(3, true, true), rec(4, true, false, 0)];
      expect(resumableCacheRecords(list).map((r: CacheRecord): number => r.fileId).join(',')).assertEqual('1');
    });

    it('在消息内容里按 fileId 找文件对象，数组、嵌套都找', 0, () => {
      const video = JSON.parse('{"@type":"messageVideo","video":{"@type":"video","video":{"@type":"file","id":42}}}') as Object;
      expect(messageHasFile(video, 42)).assertTrue();
      expect(messageHasFile(video, 43)).assertFalse();
      const album = JSON.parse('{"@type":"x","items":[{"@type":"photoSize","photo":{"@type":"file","id":7}}]}') as Object;
      expect(messageHasFile(album, 7)).assertTrue();
      expect(messageHasFile(undefined, 7)).assertFalse();
      const notFile = JSON.parse('{"@type":"thumbnail","id":42}') as Object;
      expect(messageHasFile(notFile, 42)).assertFalse();
    });

    it('网络门控：断网等网络；蜂窝且只在 Wi‑Fi 下缓存等 Wi‑Fi；点过用流量继续、VPN、其它放行', 0, () => {
      expect(cacheWaitReason('none', true, false)).assertEqual(BG_WAIT_NETWORK);
      expect(cacheWaitReason('none', false, true)).assertEqual(BG_WAIT_NETWORK);
      expect(cacheWaitReason('mobile', true, false)).assertEqual(BG_WAIT_WIFI);
      expect(cacheWaitReason('roaming', true, false)).assertEqual(BG_WAIT_WIFI);
      expect(cacheWaitReason('mobile', true, true)).assertEqual(BG_WAIT_NONE);
      expect(cacheWaitReason('mobile', false, false)).assertEqual(BG_WAIT_NONE);
      expect(cacheWaitReason('wifi', true, false)).assertEqual(BG_WAIT_NONE);
      expect(cacheWaitReason('vpn', true, false)).assertEqual(BG_WAIT_NONE);
      expect(cacheWaitReason('other', true, false)).assertEqual(BG_WAIT_NONE);
    });

    it('通知栏汇总进度：按字节加权，大小未知的不计，没下完封顶 99', 0, () => {
      expect(aggregateCachePercent([{ downloaded: 50, size: 100 }, { downloaded: 250, size: 300 }])).assertEqual(75);
      expect(aggregateCachePercent([{ downloaded: 10, size: 0 }])).assertEqual(0);
      expect(aggregateCachePercent([{ downloaded: 100, size: 100 }])).assertEqual(99);
      expect(aggregateCachePercent([])).assertEqual(0);
    });
  });
}
