import { describe, expect, it } from '@ohos/hypium';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdObject, TdBridge, TdError } from '../main/ets/tdkit/TdTypes';
import {
  buildAddToDownloadsRequest, defaultDownloadQuery, downloadErrorMessage, downloadFileName,
  parseDownloadCounts, parseDownloadPage, removeAllDownloads, removeDownload, searchDownloads,
  setAllDownloadsPaused, setDownloadPaused, DownloadQuery
} from '../main/ets/store/DownloadApi';

class FakeBridge implements TdBridge {
  onReceive: (json: string) => void = (): void => {};
  sent: string[] = [];

  init(cb: (json: string) => void): void { this.onReceive = cb; }

  send(json: string): void { this.sent.push(json); }
}

function newClient(bridge: FakeBridge): TdClient {
  const client = new TdClient(bridge);
  client.start();
  return client;
}

function firstRequest(bridge: FakeBridge): TdObject {
  return JSON.parse(bridge.sent[0]) as TdObject;
}

// 回复请求需要带回 @extra，否则 TdClient 无法把响应匹配到 Promise。
function replyOk(bridge: FakeBridge, index: number): void {
  const req = JSON.parse(bridge.sent[index]) as TdObject;
  const res: TdObject = { '@type': 'ok' };
  res['@extra'] = req['@extra'];
  bridge.onReceive(JSON.stringify(res));
}

function fileDownload(fileId: number, paused: boolean, fileName: string): TdObject {
  const document: TdObject = { '@type': 'document', 'file_name': fileName };
  const content: TdObject = { '@type': 'messageDocument', 'document': document };
  const message: TdObject = { '@type': 'message', 'id': fileId * 100, 'chat_id': -42, 'content': content };
  const entry: TdObject = { '@type': 'fileDownload' };
  entry['file_id'] = fileId;
  entry['message'] = message;
  entry['add_date'] = 1700000000;
  entry['complete_date'] = 0;
  entry['is_paused'] = paused;
  return entry;
}

export default function downloadApiTest() {
  describe('DownloadApi', (): void => {
    it('search_request_carries_cursor_and_clamped_limit', 0, (): void => {
      const bridge = new FakeBridge();
      const query: DownloadQuery = defaultDownloadQuery();
      query.query = '报告';
      query.onlyActive = true;
      query.offset = 'cursor-1';
      query.limit = 9999;
      searchDownloads(newClient(bridge), query);
      const req = firstRequest(bridge);
      expect(req['@type'] as string).assertEqual('searchFileDownloads');
      expect(req['query'] as string).assertEqual('报告');
      expect(req['only_active'] as boolean).assertTrue();
      expect(req['only_completed'] as boolean).assertFalse();
      expect(req['offset'] as string).assertEqual('cursor-1');
      expect(req['limit'] as number).assertEqual(200);
    });

    it('toggle_one_download_sends_file_id_and_flag', 0, (): void => {
      const bridge = new FakeBridge();
      setDownloadPaused(newClient(bridge), 77, true);
      const req = firstRequest(bridge);
      expect(req['@type'] as string).assertEqual('toggleDownloadIsPaused');
      expect(req['file_id'] as number).assertEqual(77);
      expect(req['is_paused'] as boolean).assertTrue();
    });

    it('toggle_all_downloads_sends_are_paused', 0, (): void => {
      const bridge = new FakeBridge();
      setAllDownloadsPaused(newClient(bridge), false);
      const req = firstRequest(bridge);
      expect(req['@type'] as string).assertEqual('toggleAllDownloadsArePaused');
      expect(req['are_paused'] as boolean).assertFalse();
    });

    it('remove_download_sends_delete_from_cache', 0, (): void => {
      const bridge = new FakeBridge();
      removeDownload(newClient(bridge), 5, true);
      const req = firstRequest(bridge);
      expect(req['@type'] as string).assertEqual('removeFileFromDownloads');
      expect(req['file_id'] as number).assertEqual(5);
      expect(req['delete_from_cache'] as boolean).assertTrue();
    });

    it('remove_all_downloads_sends_all_three_filters', 0, (): void => {
      const bridge = new FakeBridge();
      removeAllDownloads(newClient(bridge), false, true, false);
      const req = firstRequest(bridge);
      expect(req['@type'] as string).assertEqual('removeAllFilesFromDownloads');
      expect(req['only_active'] as boolean).assertFalse();
      expect(req['only_completed'] as boolean).assertTrue();
      expect(req['delete_from_cache'] as boolean).assertFalse();
    });

    it('add_to_downloads_clamps_priority_into_tdlib_range', 0, (): void => {
      const low = buildAddToDownloadsRequest(1, -42, 900, 0);
      expect(low['priority'] as number).assertEqual(1);
      const high = buildAddToDownloadsRequest(1, -42, 900, 999);
      expect(high['priority'] as number).assertEqual(32);
      expect(high['chat_id'] as number).assertEqual(-42);
      expect(high['message_id'] as number).assertEqual(900);
    });

    it('resolves_with_parsed_page_when_tdlib_answers', 0, async (): Promise<void> => {
      const bridge = new FakeBridge();
      const pending = searchDownloads(newClient(bridge), defaultDownloadQuery());
      const req = firstRequest(bridge);
      const counts: TdObject = {
        '@type': 'downloadedFileCounts', 'active_count': 2, 'paused_count': 1, 'completed_count': 7
      };
      const res: TdObject = { '@type': 'foundFileDownloads' };
      res['total_counts'] = counts;
      res['files'] = [fileDownload(11, false, 'a.pdf'), fileDownload(12, true, 'b.zip')];
      res['next_offset'] = 'cursor-2';
      res['@extra'] = req['@extra'];
      bridge.onReceive(JSON.stringify(res));
      const page = await pending;
      expect(page.counts.activeCount).assertEqual(2);
      expect(page.counts.pausedCount).assertEqual(1);
      expect(page.counts.completedCount).assertEqual(7);
      expect(page.nextOffset).assertEqual('cursor-2');
      expect(page.entries.length).assertEqual(2);
      expect(page.entries[0].fileName).assertEqual('a.pdf');
      expect(page.entries[0].chatId).assertEqual(-42);
      expect(page.entries[0].messageId).assertEqual(1100);
      expect(page.entries[0].isPaused).assertFalse();
      expect(page.entries[1].isPaused).assertTrue();
    });

    it('drops_entries_without_a_usable_file_id', 0, (): void => {
      const res: TdObject = { '@type': 'foundFileDownloads' };
      res['files'] = [fileDownload(0, false, 'ghost.bin'), fileDownload(3, false, 'real.bin')];
      const page = parseDownloadPage(res);
      expect(page.entries.length).assertEqual(1);
      expect(page.entries[0].fileId).assertEqual(3);
      // total_counts/next_offset 缺失时应退化为零值而不是抛错。
      expect(page.nextOffset).assertEqual('');
      expect(page.counts.completedCount).assertEqual(0);
    });

    it('treats_negative_or_missing_counts_as_zero', 0, (): void => {
      const raw: TdObject = { '@type': 'downloadedFileCounts', 'active_count': -3 };
      const counts = parseDownloadCounts(raw);
      expect(counts.activeCount).assertEqual(0);
      expect(counts.pausedCount).assertEqual(0);
      expect(parseDownloadCounts(undefined).completedCount).assertEqual(0);
    });

    it('reads_file_name_from_any_media_kind', 0, (): void => {
      const video: TdObject = { '@type': 'video', 'file_name': 'clip.mp4' };
      const content: TdObject = { '@type': 'messageVideo', 'video': video };
      const message: TdObject = { '@type': 'message', 'content': content };
      expect(downloadFileName(message)).assertEqual('clip.mp4');
      expect(downloadFileName(undefined)).assertEqual('');
      expect(downloadFileName({ '@type': 'message' } as TdObject)).assertEqual('');
    });

    it('maps_known_tdlib_errors_to_chinese_messages', 0, (): void => {
      const gone = new TdError(400, 'FILE_DOWNLOAD_ID_INVALID');
      expect(downloadErrorMessage('暂停', gone)).assertEqual('dl_not_in_list(暂停)');
      const unknown = new TdError(500, 'Boom');
      expect(downloadErrorMessage('移除', unknown)).assertEqual('dl_failed_msg(移除,Boom)');
      const blank = new TdError(500, '');
      expect(downloadErrorMessage('全部暂停', blank)).assertEqual('dl_failed_retry(全部暂停)');
    });

    it('rejects_when_tdlib_returns_an_error', 0, async (): Promise<void> => {
      const bridge = new FakeBridge();
      const pending = setDownloadPaused(newClient(bridge), 9, true);
      const req = firstRequest(bridge);
      const err: TdObject = { '@type': 'error', 'code': 400, 'message': 'FILE_ID_INVALID' };
      err['@extra'] = req['@extra'];
      bridge.onReceive(JSON.stringify(err));
      let message = '';
      try {
        await pending;
      } catch (e) {
        message = downloadErrorMessage('暂停', e as Object);
      }
      expect(message).assertEqual('dl_bad_id(暂停)');
    });

    it('resolves_void_helpers_on_plain_ok', 0, async (): Promise<void> => {
      const bridge = new FakeBridge();
      const client = newClient(bridge);
      const pending = setAllDownloadsPaused(client, true);
      replyOk(bridge, 0);
      await pending;
      expect(bridge.sent.length).assertEqual(1);
    });
  });
}
