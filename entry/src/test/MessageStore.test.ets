import { describe, it, expect } from '@ohos/hypium';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdObject, TdBridge } from '../main/ets/tdkit/TdTypes';
import { UserStore } from '../main/ets/store/UserStore';
import { MessageStore } from '../main/ets/store/MessageStore';
import { MessageEntry } from '../main/ets/store/MessageEntry';

class FakeBridge implements TdBridge {
  onReceive: (json: string) => void = (): void => {};
  sent: string[] = [];
  init(cb: (json: string) => void): void { this.onReceive = cb; }
  send(json: string): void { this.sent.push(json); }
}
function setup(chatId: number, historyPageSize: number = 30): Array<Object> {
  const b = new FakeBridge(); const c = new TdClient(b); const u = new UserStore(c);
  const store = new MessageStore(c, u, chatId, 0, historyPageSize); c.start();
  return [b, store];
}
function textMessage(id: number, chatId: number, outgoing: boolean, text: string): TdObject {
  const ft: TdObject = { '@type': 'formattedText' }; ft['text'] = text;
  const content: TdObject = { '@type': 'messageText' }; content['text'] = ft;
  const m: TdObject = { '@type': 'message' };
  m['id'] = id; m['chat_id'] = chatId; m['is_outgoing'] = outgoing; m['date'] = 100; m['content'] = content;
  return m;
}
function keyboardMessage(id: number, chatId: number, label: string): TdObject {
  const m = textMessage(id, chatId, false, 'choose');
  const button: TdObject = { '@type': 'keyboardButton' };
  button['text'] = label;
  button['type'] = { '@type': 'keyboardButtonTypeText' } as TdObject;
  const markup: TdObject = { '@type': 'replyMarkupShowKeyboard' };
  markup['rows'] = [[button]];
  markup['is_persistent'] = true;
  m['reply_markup'] = markup;
  return m;
}
function videoMessage(id: number, chatId: number, fileId: number, thumbId: number): TdObject {
  const source: TdObject = { '@type': 'file' };
  source['id'] = fileId;
  source['size'] = 1000;
  const thumbFile: TdObject = { '@type': 'file' };
  thumbFile['id'] = thumbId;
  const thumb: TdObject = { '@type': 'thumbnail' };
  thumb['file'] = thumbFile;
  thumb['width'] = 320;
  thumb['height'] = 180;
  const video: TdObject = { '@type': 'video' };
  video['video'] = source;
  video['thumbnail'] = thumb;
  video['width'] = 320;
  video['height'] = 180;
  const content: TdObject = { '@type': 'messageVideo' };
  content['video'] = video;
  const m: TdObject = { '@type': 'message' };
  m['id'] = id;
  m['chat_id'] = chatId;
  m['is_outgoing'] = false;
  m['date'] = 100;
  m['content'] = content;
  return m;
}
function photoMessage(id: number, chatId: number, thumbId: number, fullId: number): TdObject {
  const smallFile: TdObject = { '@type': 'file' };
  smallFile['id'] = thumbId - 1;
  smallFile['size'] = 5000;
  const smallSize: TdObject = { '@type': 'photoSize' };
  smallSize['type'] = 's';
  smallSize['photo'] = smallFile;
  smallSize['width'] = 200;
  smallSize['height'] = 200;
  const midFile: TdObject = { '@type': 'file' };
  midFile['id'] = thumbId;
  midFile['size'] = 30000;
  const midSize: TdObject = { '@type': 'photoSize' };
  midSize['type'] = 'm';
  midSize['photo'] = midFile;
  midSize['width'] = 900;
  midSize['height'] = 900;
  const fullFile: TdObject = { '@type': 'file' };
  fullFile['id'] = fullId;
  fullFile['size'] = 200000;
  const fullSize: TdObject = { '@type': 'photoSize' };
  fullSize['type'] = 'x';
  fullSize['photo'] = fullFile;
  fullSize['width'] = 1600;
  fullSize['height'] = 1600;
  const photo: TdObject = { '@type': 'photo' };
  photo['sizes'] = [smallSize, midSize, fullSize];
  const content: TdObject = { '@type': 'messagePhoto' };
  content['photo'] = photo;
  const m: TdObject = { '@type': 'message' };
  m['id'] = id;
  m['chat_id'] = chatId;
  m['is_outgoing'] = false;
  m['date'] = 100;
  m['content'] = content;
  return m;
}
function animationMessage(id: number, chatId: number, fileId: number, thumbId: number): TdObject {
  const source: TdObject = { '@type': 'file' };
  source['id'] = fileId;
  source['size'] = 1000;
  const thumbFile: TdObject = { '@type': 'file' };
  thumbFile['id'] = thumbId;
  const thumb: TdObject = { '@type': 'thumbnail' };
  thumb['file'] = thumbFile;
  thumb['width'] = 320;
  thumb['height'] = 180;
  const animation: TdObject = { '@type': 'animation' };
  animation['animation'] = source;
  animation['thumbnail'] = thumb;
  animation['width'] = 320;
  animation['height'] = 180;
  const content: TdObject = { '@type': 'messageAnimation' };
  content['animation'] = animation;
  const message: TdObject = { '@type': 'message' };
  message['id'] = id;
  message['chat_id'] = chatId;
  message['is_outgoing'] = false;
  message['date'] = 100;
  message['content'] = content;
  return message;
}
function voiceMessage(id: number, chatId: number, fileId: number, listened: boolean): TdObject {
  const source: TdObject = { '@type': 'file' };
  source['id'] = fileId;
  source['size'] = 1000;
  const voice: TdObject = { '@type': 'voiceNote' };
  voice['voice'] = source;
  voice['duration'] = 8;
  voice['mime_type'] = 'audio/ogg';
  voice['waveform'] = '//8=';
  const content: TdObject = { '@type': 'messageVoiceNote' };
  content['voice_note'] = voice;
  content['is_listened'] = listened;
  const message: TdObject = { '@type': 'message' };
  message['id'] = id;
  message['chat_id'] = chatId;
  message['is_outgoing'] = false;
  message['date'] = 100;
  message['content'] = content;
  return message;
}
function audioMessage(id: number, chatId: number, fileId: number, coverId: number): TdObject {
  const source: TdObject = { '@type': 'file' };
  source['id'] = fileId;
  source['size'] = 1000;
  const coverSource: TdObject = { '@type': 'file' };
  coverSource['id'] = coverId;
  const cover: TdObject = { '@type': 'thumbnail' };
  cover['file'] = coverSource;
  cover['width'] = 200;
  cover['height'] = 200;
  const audio: TdObject = { '@type': 'audio' };
  audio['audio'] = source;
  audio['album_cover_thumbnail'] = cover;
  audio['duration'] = 180;
  audio['title'] = 'Track';
  audio['performer'] = 'Artist';
  audio['file_name'] = 'track.mp3';
  audio['mime_type'] = 'audio/mpeg';
  const content: TdObject = { '@type': 'messageAudio' };
  content['audio'] = audio;
  const message: TdObject = { '@type': 'message' };
  message['id'] = id;
  message['chat_id'] = chatId;
  message['is_outgoing'] = false;
  message['date'] = 100;
  message['content'] = content;
  return message;
}
function documentMessage(
  id: number,
  chatId: number,
  fileId: number,
  localPath: string = ''
): TdObject {
  const source: TdObject = { '@type': 'file' };
  source['id'] = fileId;
  source['size'] = 1000;
  const local: TdObject = { '@type': 'localFile' };
  local['is_downloading_completed'] = localPath !== '';
  local['is_downloading_active'] = false;
  local['path'] = localPath;
  local['downloaded_size'] = localPath !== '' ? 1000 : 0;
  source['local'] = local;
  const document: TdObject = { '@type': 'document' };
  document['document'] = source;
  document['file_name'] = 'guide.pdf';
  document['mime_type'] = 'application/pdf';
  const content: TdObject = { '@type': 'messageDocument' };
  content['document'] = document;
  const message: TdObject = { '@type': 'message' };
  message['id'] = id;
  message['chat_id'] = chatId;
  message['is_outgoing'] = false;
  message['date'] = 100;
  message['content'] = content;
  return message;
}
function pollObject(chosenOption: number = -1, total: number = 0): TdObject {
  const question: TdObject = { '@type': 'formattedText' };
  question['text'] = '今天喝什么';
  const tea: TdObject = { '@type': 'pollOption' };
  tea['text'] = { '@type': 'formattedText', 'text': '茶' } as TdObject;
  tea['voter_count'] = chosenOption === 0 ? total : 0;
  tea['vote_percentage'] = chosenOption === 0 ? 100 : 0;
  tea['is_chosen'] = chosenOption === 0;
  tea['is_being_chosen'] = false;
  const coffee: TdObject = { '@type': 'pollOption' };
  coffee['text'] = { '@type': 'formattedText', 'text': '咖啡' } as TdObject;
  coffee['voter_count'] = chosenOption === 1 ? total : 0;
  coffee['vote_percentage'] = chosenOption === 1 ? 100 : 0;
  coffee['is_chosen'] = chosenOption === 1;
  coffee['is_being_chosen'] = false;
  const type: TdObject = { '@type': 'pollTypeRegular' };
  type['allow_multiple_answers'] = false;
  const poll: TdObject = { '@type': 'poll' };
  poll['id'] = 'poll-store-1';
  poll['question'] = question;
  poll['options'] = [tea, coffee];
  poll['total_voter_count'] = total;
  poll['is_anonymous'] = true;
  poll['type'] = type;
  poll['is_closed'] = false;
  return poll;
}
function pollMessage(id: number, chatId: number): TdObject {
  const content: TdObject = { '@type': 'messagePoll' };
  content['poll'] = pollObject();
  const message: TdObject = { '@type': 'message' };
  message['id'] = id;
  message['chat_id'] = chatId;
  message['is_outgoing'] = false;
  message['date'] = 100;
  message['content'] = content;
  return message;
}
// tgs 贴纸消息：source 是动画文件，thumbnail 是静态占位图。
function tgsStickerMessage(id: number, chatId: number, srcId: number, thumbId: number): TdObject {
  const source: TdObject = { '@type': 'file' };
  source['id'] = srcId;
  source['size'] = 20000;
  const thumbFile: TdObject = { '@type': 'file' };
  thumbFile['id'] = thumbId;
  const thumb: TdObject = { '@type': 'thumbnail' };
  thumb['file'] = thumbFile;
  thumb['format'] = { '@type': 'thumbnailFormatWebp' } as TdObject;
  const sticker: TdObject = { '@type': 'sticker' };
  sticker['sticker'] = source;
  sticker['thumbnail'] = thumb;
  sticker['width'] = 512;
  sticker['height'] = 512;
  sticker['emoji'] = '\u{1F600}';
  sticker['format'] = { '@type': 'stickerFormatTgs' } as TdObject;
  const content: TdObject = { '@type': 'messageSticker' };
  content['sticker'] = sticker;
  const m: TdObject = { '@type': 'message' };
  m['id'] = id; m['chat_id'] = chatId; m['is_outgoing'] = false; m['date'] = 100;
  m['content'] = content;
  return m;
}

function downloadCount(b: FakeBridge, fileId: number): number {
  let n = 0;
  for (const json of b.sent) {
    const request = JSON.parse(json) as TdObject;
    if (request['@type'] === 'downloadFile' && request['file_id'] === fileId) {
      n++;
    }
  }
  return n;
}

function pushNewMessage(b: FakeBridge, m: TdObject): void {
  const u: TdObject = { '@type': 'updateNewMessage' }; u['message'] = m;
  b.onReceive(JSON.stringify(u));
}
function extraOf(json: string): string {
  const o = JSON.parse(json) as TdObject; return (o['@extra'] as string | undefined) ?? '';
}
function feedChat(b: FakeBridge, chatId: number, asGroup: boolean = false): void {
  // find the getChat request and answer it with a minimal chat (no unread
  // anchor), so startInitialLoad() takes the plain loadHistory(0) path.
  let extra = '';
  for (const s of b.sent) {
    const o = JSON.parse(s) as TdObject;
    if (o['@type'] === 'getChat') { extra = extraOf(s); }
  }
  const chat: TdObject = { '@type': 'chat' };
  chat['id'] = chatId;
  chat['@extra'] = extra;
  if (asGroup) {
    // 回复键盘的尾部探测只对群聊生效，不带 type 的 chat 走不到那条分支。
    const type: TdObject = { '@type': 'chatTypeSupergroup' };
    type['supergroup_id'] = chatId;
    chat['type'] = type;
  }
  b.onReceive(JSON.stringify(chat));
}
function feedHistory(b: FakeBridge, msgs: TdObject[]): void {
  // find the getChatHistory request and answer it with a `messages` response
  let extra = '';
  for (const s of b.sent) {
    const o = JSON.parse(s) as TdObject;
    if (o['@type'] === 'getChatHistory') { extra = extraOf(s); }
  }
  const res: TdObject = { '@type': 'messages' }; res['total_count'] = msgs.length; res['messages'] = msgs; res['@extra'] = extra;
  b.onReceive(JSON.stringify(res));
}
function requestCount(b: FakeBridge, type: string): number {
  return b.sent.filter((json: string): boolean =>
    (JSON.parse(json) as TdObject)['@type'] === type).length;
}
function feedRequestError(b: FakeBridge, type: string, code: number, message: string): void {
  let extra = '';
  for (const json of b.sent) {
    const request = JSON.parse(json) as TdObject;
    if (request['@type'] === type) {
      extra = extraOf(json);
    }
  }
  const error: TdObject = { '@type': 'error' };
  error['code'] = code;
  error['message'] = message;
  error['@extra'] = extra;
  b.onReceive(JSON.stringify(error));
}
function ids(list: MessageEntry[]): number[] { return list.map((m: MessageEntry) => m.id); }

export default function messageStoreTest() {
  describe('MessageStore', () => {
    it('open_sends_openchat_and_history', 0, async () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      feedChat(b, 5); // history is deferred until getChat resolves (unread anchor)
      // onChat() runs in a .then() microtask, not synchronously after feedChat.
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      const types = b.sent.map((s: string) => (JSON.parse(s) as TdObject)['@type']);
      expect(types.includes('openChat')).assertTrue();
      expect(types.includes('getChatHistory')).assertTrue();
    });
    // A remembered/message-link landing is aligned at the top of the viewport.
    // Bias its small first page toward newer rows so the area below the restored
    // row is already populated instead of appearing a few seconds later.
    it('requested_initial_landing_prefetches_a_full_trailing_viewport', 0, async () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open(500, false, true);
      feedChat(b, 5);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      const request = b.sent.map((json: string): TdObject => JSON.parse(json) as TdObject)
        .find((candidate: TdObject): boolean => candidate['@type'] === 'getChatHistory');
      expect(request !== undefined).assertTrue();
      expect(request !== undefined ? request['from_message_id'] : 0).assertEqual(500);
      expect(request !== undefined ? request['offset'] : 0).assertEqual(-13);
      expect(request !== undefined ? request['limit'] : 0).assertEqual(14);
      expect(store.isResumeLandingSelected()).assertTrue();
    });
    it('remembered_landing_yields_to_a_new_unread_boundary', 0, async () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open(500, false, true);
      let extra = '';
      for (const json of b.sent) {
        const request = JSON.parse(json) as TdObject;
        if (request['@type'] === 'getChat') {
          extra = extraOf(json);
        }
      }
      const chat: TdObject = { '@type': 'chat' };
      chat['id'] = 5;
      chat['unread_count'] = 3;
      chat['last_read_inbox_message_id'] = 200;
      chat['last_message'] = textMessage(800, 5, false, 'latest');
      chat['@extra'] = extra;
      b.onReceive(JSON.stringify(chat));
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      const request = b.sent.map((json: string): TdObject => JSON.parse(json) as TdObject)
        .find((candidate: TdObject): boolean => candidate['@type'] === 'getChatHistory');
      expect(request !== undefined).assertTrue();
      expect(request !== undefined ? request['from_message_id'] : 0).assertEqual(200);
      expect(request !== undefined ? request['offset'] : 0).assertEqual(-7);
      expect(request !== undefined ? request['limit'] : 0).assertEqual(14);
      expect(store.isResumeLandingSelected()).assertFalse();
    });
    it('first_unread_skips_own_outgoing_messages', 0, async () => {
      // issue #101：last_read_inbox 只记收到的消息。自己刚发过 300/400 再收到
      // 500，「第一条未读」必须是 500，不能落在自己发的 300 上。
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      let extra = '';
      for (const json of b.sent) {
        const request = JSON.parse(json) as TdObject;
        if (request['@type'] === 'getChat') {
          extra = extraOf(json);
        }
      }
      const chat: TdObject = { '@type': 'chat' };
      chat['id'] = 5;
      chat['unread_count'] = 1;
      chat['last_read_inbox_message_id'] = 200;
      chat['last_message'] = textMessage(500, 5, false, 'incoming');
      chat['@extra'] = extra;
      b.onReceive(JSON.stringify(chat));
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      feedHistory(b, [
        textMessage(500, 5, false, 'incoming'), textMessage(400, 5, true, 'mine 2'),
        textMessage(300, 5, true, 'mine 1'), textMessage(200, 5, false, 'read')
      ]);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      expect(store.getFirstUnreadId()).assertEqual(500);
    });
    it('history_loads_ascending', 0, async () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      expect(store.getInitialHistoryState()).assertEqual('loading');
      feedChat(b, 5);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      feedHistory(b, [textMessage(30, 5, false, 'c'), textMessage(20, 5, false, 'b'), textMessage(10, 5, false, 'a')]);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      expect(ids(store.getMessages()).join(',')).assertEqual('10,20,30');
      expect(store.getInitialHistoryState()).assertEqual('ready');
    });
    // The suspended stretch is a blind spot: the process is frozen, messages
    // delivered meanwhile never pass through updateNewMessage. resumeOpenChat
    // refetches the newest page; if it does not overlap the loaded window the
    // pages between were never fetched, and merging would render the two runs
    // seamlessly glued with the middle silently missing (10:46 followed by
    // 10:57 on the device). Disjoint pages must replace the window.
    it('resume_after_suspend_replaces_disjoint_window', 0, async () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      feedChat(b, 5);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      feedHistory(b, [textMessage(30, 5, false, 'c'), textMessage(20, 5, false, 'b'), textMessage(10, 5, false, 'a')]);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      expect(ids(store.getMessages()).join(',')).assertEqual('10,20,30');
      store.suspendOpenChat();
      store.resumeOpenChat();
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      // The refetched newest page shares no id with the window: 40 was lost in
      // the gap, 50-70 arrived later.
      feedHistory(b, [textMessage(70, 5, false, 'g'), textMessage(60, 5, false, 'f'), textMessage(50, 5, false, 'e')]);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      expect(ids(store.getMessages()).join(',')).assertEqual('50,60,70');
    });
    // The overlap case must keep merging: replacing the window on every resume
    // would throw away loaded history for no reason.
    it('resume_after_suspend_merges_overlapping_page', 0, async () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      feedChat(b, 5);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      feedHistory(b, [textMessage(30, 5, false, 'c'), textMessage(20, 5, false, 'b'), textMessage(10, 5, false, 'a')]);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      store.suspendOpenChat();
      store.resumeOpenChat();
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      // One new message; the page still contains 20 and 30 — contiguous.
      feedHistory(b, [textMessage(40, 5, false, 'd'), textMessage(30, 5, false, 'c'), textMessage(20, 5, false, 'b')]);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      expect(ids(store.getMessages()).join(',')).assertEqual('10,20,30,40');
    });
    // TDLib often answers the FIRST negative-offset getChatHistory from its
    // local cache only — nothing newer comes back even though newer messages
    // exist. Concluding "live tail" from that one answer froze newer-paging,
    // which users saw as unread messages never fully loading. The store must
    // retry once from the same anchor before believing the tail is real.
    it('newer_paging_retries_cache_only_first_answer', 0, async () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      feedChat(b, 5);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      feedHistory(b, [textMessage(30, 5, false, 'c'), textMessage(20, 5, false, 'b'), textMessage(10, 5, false, 'a')]);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      // Jump mid-history so hasMoreNewer arms newer paging.
      store.loadAround(20);
      feedHistory(b, [textMessage(30, 5, false, 'c'), textMessage(20, 5, false, 'b'), textMessage(10, 5, false, 'a')]);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      expect(store.loadNewer()).assertTrue();
      // Cache-only first answer: anchor and older, nothing newer.
      feedHistory(b, [textMessage(30, 5, false, 'c'), textMessage(20, 5, false, 'b')]);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      // The retry fired automatically; the server-backed page answers it.
      feedHistory(b, [textMessage(50, 5, false, 'e'), textMessage(40, 5, false, 'd'), textMessage(30, 5, false, 'c')]);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      expect(ids(store.getMessages()).join(',')).assertEqual('10,20,30,40,50');
      expect(store.getHasMoreNewer()).assertTrue();
    });
    // 一整页更新的消息全在缺口之后时，store 会「整页收下、让窗口带着洞往前走」
    // （宁可留洞也不冻住）。那条分支原来**忘了把 newerLoadState 放回 idle**：
    // 请求发出时置了 'loading'，收下之后没人复位，顶上那颗"正在加载较新消息"的
    // 胶囊就永远关不掉——用户实报"一直加载较新的消息，关不掉了"。
    // 另外两条合并路径（inner-gap-trimmed / 正常合并）都有这一句，只有它没有。
    it('newer_page_taken_as_is_behind_a_gap_clears_the_loading_pill', 0, async () => {
      const S: number = 1048576; // TDLib 的消息 id 每条加 2^20，一步就是一条
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      feedChat(b, 5);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      feedHistory(b, [textMessage(30 * S, 5, false, 'c'), textMessage(20 * S, 5, false, 'b'),
        textMessage(10 * S, 5, false, 'a')]);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      // 跳到历史中间，向下分页才会上膛。
      store.loadAround(20 * S);
      feedHistory(b, [textMessage(30 * S, 5, false, 'c'), textMessage(20 * S, 5, false, 'b'),
        textMessage(10 * S, 5, false, 'a')]);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      expect(store.loadNewer()).assertTrue();
      expect(store.getNewerLoadState()).assertEqual('loading');
      // 页里带着锚点自己（30），所以**页首连续性检查放行**（skipped=0，不会走
      // 整页重问那条路）；但更新的三条离锚点都在 98 步之外，一条都接不上。
      // 这正是真机日志里那一页的形状。
      feedHistory(b, [textMessage(130 * S, 5, false, 'g'), textMessage(129 * S, 5, false, 'f'),
        textMessage(128 * S, 5, false, 'e'), textMessage(30 * S, 5, false, 'c')]);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      expect(store.getMessages().length).assertEqual(6);
      expect(ids(store.getMessages())[5]).assertEqual(130 * S);
      // 回归点：修之前这里是 'loading'，胶囊再也不会消失。
      expect(store.getNewerLoadState()).assertEqual('idle');
    });
    it('sole_local_join_notice_is_injected_and_read', 0, async () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      let extra = '';
      for (const json of b.sent) {
        const request = JSON.parse(json) as TdObject;
        if (request['@type'] === 'getChat') { extra = extraOf(json); }
      }
      const sender: TdObject = { '@type': 'messageSenderUser' };
      sender['user_id'] = 7;
      const content: TdObject = { '@type': 'messageChatJoinByLink' };
      const join: TdObject = { '@type': 'message' };
      join['id'] = 100;
      join['chat_id'] = 5;
      join['sender_id'] = sender;
      join['is_outgoing'] = true;
      join['date'] = 100;
      join['content'] = content;
      const chat: TdObject = { '@type': 'chat' };
      chat['id'] = 5;
      chat['unread_count'] = 1;
      chat['last_read_inbox_message_id'] = 90;
      chat['last_message'] = join;
      chat['@extra'] = extra;
      b.onReceive(JSON.stringify(chat));
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      feedHistory(b, []); // TDLib omits the LOCAL service message from history.
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      expect(ids(store.getMessages()).join(',')).assertEqual('100');
      expect(store.getMessages()[0].placeholderLabel).assertEqual('cp_joined_group');
      const view = b.sent.map((json: string): TdObject => JSON.parse(json) as TdObject)
        .find((request: TdObject): boolean => request['@type'] === 'viewMessages');
      expect(view !== undefined).assertTrue();
      expect(((view!['message_ids'] as number[] | undefined) ?? []).join(',')).assertEqual('100');
      expect(view!['force_read']).assertEqual(true);
    });
    it('empty_history_is_ready_and_stops_older_paging', 0, async () => {
      const arr = setup(5, 2); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      feedChat(b, 5);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      feedRequestError(b, 'getChatHistory', 404, 'Not Found');
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      expect(store.getInitialHistoryState()).assertEqual('ready');
      expect(store.getInitialHistoryError()).assertEqual('');
      expect(store.getMessages().length).assertEqual(0);
      expect(store.getHasMoreOlder()).assertFalse();
      expect(store.getOlderLoadState()).assertEqual('end');
    });
    it('initial_history_error_can_retry_without_false_empty_state', 0, async () => {
      const arr = setup(5, 2); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      feedChat(b, 5);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      feedRequestError(b, 'getChatHistory', -1, 'request timeout');
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      expect(store.getInitialHistoryState()).assertEqual('error');
      expect(store.getInitialHistoryError()).assertEqual('ms_timeout');
      const before = requestCount(b, 'getChatHistory');
      store.retryInitialHistory();
      expect(store.getInitialHistoryState()).assertEqual('loading');
      expect(requestCount(b, 'getChatHistory')).assertEqual(before + 1);
      feedHistory(b, []);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      expect(store.getInitialHistoryState()).assertEqual('ready');
      expect(store.getInitialHistoryError()).assertEqual('');
    });
    it('older_page_error_retries_and_404_marks_history_end', 0, async () => {
      const arr = setup(5, 2); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      feedChat(b, 5);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      feedHistory(b, [
        textMessage(20, 5, false, 'b'),
        textMessage(10, 5, false, 'a')
      ]);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      expect(store.getHasMoreOlder()).assertTrue();
      expect(store.loadOlder()).assertTrue();
      feedRequestError(b, 'getChatHistory', 500, 'server error');
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      expect(store.getOlderLoadState()).assertEqual('error');
      expect(store.loadOlder()).assertFalse();
      const beforeRetry = requestCount(b, 'getChatHistory');
      store.retryOlder();
      expect(requestCount(b, 'getChatHistory')).assertEqual(beforeRetry + 1);
      feedRequestError(b, 'getChatHistory', 404, 'Not Found');
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      expect(store.getOlderLoadState()).assertEqual('end');
      expect(store.getHasMoreOlder()).assertFalse();
      const atEnd = requestCount(b, 'getChatHistory');
      expect(store.loadOlder()).assertFalse();
      expect(requestCount(b, 'getChatHistory')).assertEqual(atEnd);
    });
    it('older_page_merges_without_duplicates_and_stays_sorted', 0, async () => {
      const arr = setup(5, 2); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      feedChat(b, 5);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      feedHistory(b, [textMessage(30, 5, false, 'c'), textMessage(20, 5, false, 'b')]);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      expect(store.loadOlder()).assertTrue();
      // TDLib pages may overlap at the seam: the anchor message returns again.
      feedHistory(b, [textMessage(20, 5, false, 'b'), textMessage(10, 5, false, 'a')]);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      expect(ids(store.getMessages()).join(',')).assertEqual('10,20,30');
    });
    it('sender_name_backfill_publishes_once_not_per_message', 0, async () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      feedChat(b, 5);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      const msgs: TdObject[] = [];
      for (let i = 5; i >= 1; i--) {
        const m = textMessage(i * 10, 5, false, `m${i}`);
        const sender: TdObject = { '@type': 'messageSenderUser' };
        sender['user_id'] = 42;
        m['sender_id'] = sender;
        msgs.push(m);
      }
      feedHistory(b, msgs);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      let notifies = 0;
      const unsub = store.subscribe((): void => { notifies++; });
      const baseline = notifies;
      const user: TdObject = { '@type': 'user' };
      user['id'] = 42; user['first_name'] = 'Bob';
      const upd: TdObject = { '@type': 'updateUser' };
      upd['user'] = user;
      b.onReceive(JSON.stringify(upd));
      // Past the full settle window (1s): right after initial history the
      // store holds ALL update publications and flushes once at window end —
      // which is exactly what this test exercises.
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 1100));
      const named = store.getMessages()
        .filter((m: MessageEntry): boolean => m.senderName === 'Bob').length;
      expect(named).assertEqual(5);
      // One coalesced publish for the whole backfill, not one per message.
      expect(notifies - baseline).assertEqual(1);
      unsub();
    });
    it('new_message_appends', 0, () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      pushNewMessage(b, textMessage(40, 5, false, 'new'));
      expect(ids(store.getMessages()).join(',')).assertEqual('40');
    });
    it('new_message_other_chat_ignored', 0, () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      pushNewMessage(b, textMessage(41, 99, false, 'other'));
      expect(store.getMessages().length).assertEqual(0);
    });
    it('keyboard_probe_recovers_markup_beyond_visible_history', 0, async () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      let label = '';
      store.subscribeReplyKeyboard((kb) => {
        label = kb !== null && kb.rows.length > 0 && kb.rows[0].length > 0
          ? kb.rows[0][0].text : '';
      });
      store.open();
      feedChat(b, 5, true);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      // The visible latest page has no keyboard marker, so MessageStore starts
      // an independent tail probe rather than depending on rendered history.
      feedHistory(b, []);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      feedHistory(b, [keyboardMessage(10, 5, '快捷操作')]);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      expect(label).assertEqual('快捷操作');
    });
    it('send_succeeded_swaps_id', 0, () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      pushNewMessage(b, textMessage(1001, 5, true, 'hi')); // optimistic (temp id 1001, pending)
      const newMsg = textMessage(2002, 5, true, 'hi');
      const u: TdObject = { '@type': 'updateMessageSendSucceeded' }; u['message'] = newMsg; u['old_message_id'] = 1001;
      b.onReceive(JSON.stringify(u));
      expect(ids(store.getMessages()).join(',')).assertEqual('2002');
      expect(store.getMessages()[0].sendState).assertEqual('sent');
    });
    it('read_outbox_marks_read', 0, async () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      pushNewMessage(b, textMessage(50, 5, true, 'x')); // outgoing, sent
      const u: TdObject = { '@type': 'updateChatReadOutbox' }; u['chat_id'] = 5; u['last_read_outbox_message_id'] = 50;
      b.onReceive(JSON.stringify(u));
      // The read watermark is applied inside the (now coalesced) publish.
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 30));
      expect(store.getMessages()[0].sendState).assertEqual('read');
    });
    it('edited_update_refreshes_edit_marker', 0, () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      pushNewMessage(b, textMessage(51, 5, true, 'x'));
      const u: TdObject = { '@type': 'updateMessageEdited' };
      u['chat_id'] = 5;
      u['message_id'] = 51;
      u['edit_date'] = 345;
      b.onReceive(JSON.stringify(u));
      expect(store.getMessages()[0].editDate).assertEqual(345);
    });
    it('delete_removes', 0, () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      pushNewMessage(b, textMessage(60, 5, false, 'y'));
      const u: TdObject = { '@type': 'updateDeleteMessages' }; u['chat_id'] = 5; u['message_ids'] = [60]; u['is_permanent'] = true;
      b.onReceive(JSON.stringify(u));
      expect(store.getMessages().length).assertEqual(0);
    });
    it('shared_video_file_updates_all_bubbles', 0, () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      pushNewMessage(b, videoMessage(80, 5, 900, 901));
      pushNewMessage(b, videoMessage(81, 5, 900, 902));
      store.requestVideoDownload(80);
      const local: TdObject = { '@type': 'localFile' };
      local['is_downloading_completed'] = true;
      local['path'] = '/data/video.mp4';
      local['downloaded_size'] = 1000;
      const file: TdObject = { '@type': 'file' };
      file['id'] = 900;
      file['size'] = 1000;
      file['local'] = local;
      const update: TdObject = { '@type': 'updateFile' };
      update['file'] = file;
      b.onReceive(JSON.stringify(update));
      expect(store.getMessages()[0].videoPath).assertEqual('/data/video.mp4');
      expect(store.getMessages()[1].videoPath).assertEqual('/data/video.mp4');
      expect(store.getMessages()[0].videoProgress).assertEqual(100);
      expect(store.getMessages()[1].videoProgress).assertEqual(100);
    });
    it('new_animation_prefetches_loop_source_when_autoplay_is_enabled', 0, () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      pushNewMessage(b, animationMessage(82, 5, 920, 921));
      const sourceRequested = b.sent.some((json: string): boolean => {
        const request = JSON.parse(json) as TdObject;
        return request['@type'] === 'downloadFile' && request['file_id'] === 920;
      });
      expect(store.getMessages()[0].isAnimation).assertTrue();
      expect(sourceRequested).assertTrue();
    });
    it('voice_listened_update_preserves_downloaded_file', 0, () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      pushNewMessage(b, voiceMessage(83, 5, 930, false));
      const local: TdObject = { '@type': 'localFile' };
      local['is_downloading_completed'] = true;
      local['path'] = '/data/voice.ogg';
      local['downloaded_size'] = 1000;
      const file: TdObject = { '@type': 'file' };
      file['id'] = 930;
      file['size'] = 1000;
      file['local'] = local;
      const fileUpdate: TdObject = { '@type': 'updateFile' };
      fileUpdate['file'] = file;
      b.onReceive(JSON.stringify(fileUpdate));
      expect(store.getMessages()[0].videoPath).assertEqual('/data/voice.ogg');

      store.markVoiceListened(83);
      expect(store.getMessages()[0].voiceListened).assertTrue();
      const opened: boolean = b.sent.some((json: string): boolean => {
        const request = JSON.parse(json) as TdObject;
        return request['@type'] === 'openMessageContent' && request['message_id'] === 83;
      });
      expect(opened).assertTrue();

      const updated: TdObject = voiceMessage(83, 5, 930, true)['content'] as TdObject;
      const contentUpdate: TdObject = { '@type': 'updateMessageContent' };
      contentUpdate['chat_id'] = 5;
      contentUpdate['message_id'] = 83;
      contentUpdate['new_content'] = updated;
      b.onReceive(JSON.stringify(contentUpdate));
      expect(store.getMessages()[0].voiceListened).assertTrue();
      expect(store.getMessages()[0].videoPath).assertEqual('/data/voice.ogg');
      expect(store.getMessages()[0].videoProgress).assertEqual(100);
    });
    it('sticker_source_is_requested_once_and_not_stormed', 0, () => {
      // issue #68 的回归位：贴纸源文件请求要去重，不能每次 requestPhotos 都
      // 重发一次（那是另一个方向的病：请求风暴）。真正的修复是超过 8s 的
      // 限速重发，时间相关那半没法在宿主测里等，这里钉住的是"短时间内只发
      // 一次"这一半。
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      pushNewMessage(b, tgsStickerMessage(90, 5, 960, 961));
      expect(store.getMessages()[0].contentType).assertEqual('sticker');
      expect(downloadCount(b, 960)).assertEqual(1);
      // 再来一条消息会再跑一遍 requestPhotos：贴纸不该被重新请求。
      pushNewMessage(b, textMessage(91, 5, false, 'hi'));
      expect(downloadCount(b, 960)).assertEqual(1);
    });

    it('audio_prefetches_cover_and_downloads_source_on_demand', 0, () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      pushNewMessage(b, audioMessage(84, 5, 940, 941));
      expect(store.getMessages()[0].contentType).assertEqual('audio');
      expect(store.getMessages()[0].audioTitle).assertEqual('Track');
      expect(store.getMessages()[0].audioPerformer).assertEqual('Artist');
      const coverRequested: boolean = b.sent.some((json: string): boolean => {
        const request = JSON.parse(json) as TdObject;
        return request['@type'] === 'downloadFile' && request['file_id'] === 941;
      });
      const sourceRequestedBeforeTap: boolean = b.sent.some((json: string): boolean => {
        const request = JSON.parse(json) as TdObject;
        return request['@type'] === 'downloadFile' && request['file_id'] === 940;
      });
      expect(coverRequested).assertTrue();
      expect(sourceRequestedBeforeTap).assertFalse();

      store.requestVideoDownload(84);
      expect(store.getMessages()[0].mediaDownloadActive).assertTrue();
      const sourceRequestedAfterTap: boolean = b.sent.some((json: string): boolean => {
        const request = JSON.parse(json) as TdObject;
        return request['@type'] === 'downloadFile' && request['file_id'] === 940;
      });
      expect(sourceRequestedAfterTap).assertTrue();

      const progressLocal: TdObject = { '@type': 'localFile' };
      progressLocal['is_downloading_completed'] = false;
      progressLocal['is_downloading_active'] = true;
      progressLocal['downloaded_size'] = 400;
      const progressFile: TdObject = { '@type': 'file' };
      progressFile['id'] = 940;
      progressFile['size'] = 1000;
      progressFile['local'] = progressLocal;
      const progressUpdate: TdObject = { '@type': 'updateFile' };
      progressUpdate['file'] = progressFile;
      b.onReceive(JSON.stringify(progressUpdate));
      expect(store.getMessages()[0].videoProgress).assertEqual(40);
      expect(store.getMessages()[0].mediaDownloadActive).assertTrue();

      const completedLocal: TdObject = { '@type': 'localFile' };
      completedLocal['is_downloading_completed'] = true;
      completedLocal['path'] = '/data/track.mp3';
      completedLocal['downloaded_size'] = 1000;
      const completedFile: TdObject = { '@type': 'file' };
      completedFile['id'] = 940;
      completedFile['size'] = 1000;
      completedFile['local'] = completedLocal;
      const completedUpdate: TdObject = { '@type': 'updateFile' };
      completedUpdate['file'] = completedFile;
      b.onReceive(JSON.stringify(completedUpdate));
      expect(store.getMessages()[0].videoPath).assertEqual('/data/track.mp3');
      expect(store.getMessages()[0].videoProgress).assertEqual(100);
      expect(store.getMessages()[0].mediaDownloadActive).assertFalse();
    });
    it('document_hydrates_cached_file_and_remote_file_stays_on_demand', 0, () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      pushNewMessage(b, documentMessage(85, 5, 950, '/data/guide.pdf'));
      const cached: MessageEntry = store.getMessages()[0];
      expect(cached.contentType).assertEqual('file');
      expect(cached.videoFileName).assertEqual('guide.pdf');
      expect(cached.videoMimeType).assertEqual('application/pdf');
      expect(cached.videoPath).assertEqual('/data/guide.pdf');
      expect(cached.videoProgress).assertEqual(100);

      pushNewMessage(b, documentMessage(86, 5, 951));
      const downloadedBeforeTap: boolean = b.sent.some((json: string): boolean => {
        const request = JSON.parse(json) as TdObject;
        return (request['@type'] === 'downloadFile' ||
          request['@type'] === 'addFileToDownloads') && request['file_id'] === 951;
      });
      expect(downloadedBeforeTap).assertFalse();
      store.requestVideoDownload(86, true);
      const registeredAfterTap: boolean = b.sent.some((json: string): boolean => {
        const request = JSON.parse(json) as TdObject;
        return request['@type'] === 'addFileToDownloads' &&
          request['file_id'] === 951 &&
          request['message_id'] === 86;
      });
      expect(registeredAfterTap).assertTrue();
      expect(store.getMessages()[1].mediaDownloadActive).assertTrue();
    });
    // 播放用的下载必须能停。曾经点开看一眼就等于永久注册进 TDLib 的下载管理
    // 器 + 永久豁免可见窗口取消，回到列表页视频还在后台跑。
    it('playback_download_is_cancelled_when_playback_is_released', 0, () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      pushNewMessage(b, videoMessage(200, 5, 960, 961));
      store.requestVideoForPlayback(200);

      // 为播放而下 => downloadFile，不进下载管理器
      const managed: boolean = b.sent.some((json: string): boolean => {
        const request = JSON.parse(json) as TdObject;
        return request['@type'] === 'addFileToDownloads' && request['file_id'] === 960;
      });
      expect(managed).assertFalse();
      const started: boolean = b.sent.some((json: string): boolean => {
        const request = JSON.parse(json) as TdObject;
        return request['@type'] === 'downloadFile' && request['file_id'] === 960;
      });
      expect(started).assertTrue();
      expect(store.getMessages()[0].mediaDownloadActive).assertTrue();

      store.releaseVideoPlayback(200);
      const cancelled: boolean = b.sent.some((json: string): boolean => {
        const request = JSON.parse(json) as TdObject;
        return request['@type'] === 'cancelDownloadFile' && request['file_id'] === 960;
      });
      expect(cancelled).assertTrue();
      expect(store.getMessages()[0].mediaDownloadActive).assertFalse();
      expect(store.getMessages()[0].videoProgress).assertEqual(0);
    });
    // 反过来：用户明确"保存/下载"的文件进了下载管理器，看完了不该顺手取消。
    it('managed_download_survives_playback_release', 0, () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      pushNewMessage(b, videoMessage(201, 5, 970, 971));
      store.requestVideoDownload(201, true);
      store.releaseVideoPlayback(201);
      const cancelled: boolean = b.sent.some((json: string): boolean => {
        const request = JSON.parse(json) as TdObject;
        return request['@type'] === 'cancelDownloadFile' && request['file_id'] === 970;
      });
      expect(cancelled).assertFalse();
      expect(store.getMessages()[0].mediaDownloadActive).assertTrue();
    });
    // 已经下完的不该被"看完了"清掉本地路径。
    it('completed_download_is_untouched_by_playback_release', 0, () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      pushNewMessage(b, videoMessage(202, 5, 980, 981));
      store.requestVideoForPlayback(202);
      const local: TdObject = { '@type': 'localFile' };
      local['is_downloading_completed'] = true;
      local['path'] = '/data/done.mp4';
      local['downloaded_size'] = 1000;
      const file: TdObject = { '@type': 'file' };
      file['id'] = 980;
      file['size'] = 1000;
      file['local'] = local;
      const update: TdObject = { '@type': 'updateFile' };
      update['file'] = file;
      b.onReceive(JSON.stringify(update));
      expect(store.getMessages()[0].videoPath).assertEqual('/data/done.mp4');

      store.releaseVideoPlayback(202);
      const cancelled: boolean = b.sent.some((json: string): boolean => {
        const request = JSON.parse(json) as TdObject;
        return request['@type'] === 'cancelDownloadFile' && request['file_id'] === 980;
      });
      expect(cancelled).assertFalse();
      expect(store.getMessages()[0].videoPath).assertEqual('/data/done.mp4');
    });
    it('poll_vote_is_deduplicated_and_update_poll_refreshes_results', 0, async () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      pushNewMessage(b, pollMessage(87, 5));
      let completed = false;
      store.votePoll(87, [1], (ok: boolean): void => { completed = ok; });
      store.votePoll(87, [0], (): void => {});
      const voteRequests: TdObject[] = b.sent
        .map((json: string): TdObject => JSON.parse(json) as TdObject)
        .filter((request: TdObject): boolean => request['@type'] === 'setPollAnswer');
      expect(voteRequests.length).assertEqual(1);
      expect((voteRequests[0]['option_ids'] as number[])[0]).assertEqual(1);
      expect(store.getMessages()[0].pollVotePending).assertTrue();

      // TDLib can publish an intermediate updatePoll with is_being_chosen
      // before setPollAnswer resolves. Keep that option visibly pending and
      // block a second answer until the authoritative result arrives.
      const pendingPoll = pollObject();
      const pendingOptions = pendingPoll['options'] as TdObject[];
      pendingOptions[1]['is_being_chosen'] = true;
      const pendingUpdate: TdObject = { '@type': 'updatePoll' };
      pendingUpdate['poll'] = pendingPoll;
      b.onReceive(JSON.stringify(pendingUpdate));
      expect(store.getMessages()[0].pollVotePending).assertTrue();
      expect(store.getMessages()[0].pollOptions[1].isBeingChosen).assertTrue();

      const ok: TdObject = { '@type': 'ok' };
      ok['@extra'] = voteRequests[0]['@extra'];
      b.onReceive(JSON.stringify(ok));
      await new Promise<void>((resolve: (value: undefined) => void) =>
        setTimeout(() => resolve(undefined), 0));
      expect(completed).assertTrue();
      expect(store.getMessages()[0].pollVotePending).assertFalse();
      expect(store.getMessages()[0].pollOptions[1].isChosen).assertTrue();

      const update: TdObject = { '@type': 'updatePoll' };
      update['poll'] = pollObject(1, 4);
      b.onReceive(JSON.stringify(update));
      expect(store.getMessages()[0].pollTotalVoterCount).assertEqual(4);
      expect(store.getMessages()[0].pollOptions[1].votePercentage).assertEqual(100);
      expect(store.getMessages()[0].pollOptions[1].isChosen).assertTrue();
    });
    it('poll_member_restriction_rolls_back_and_explains_subscriber_rule', 0, async () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      pushNewMessage(b, pollMessage(88, 5));
      let callbackError = '';
      store.votePoll(88, [0], (_ok: boolean, error: string): void => {
        callbackError = error;
      });
      expect(store.getMessages()[0].pollVotePending).assertTrue();
      feedRequestError(b, 'setPollAnswer', 406, 'POLL_MEMBER_RESTRICTED');
      await new Promise<void>((resolve: (value: undefined) => void) =>
        setTimeout(() => resolve(undefined), 0));
      const updated = store.getMessages()[0];
      expect(updated.pollVotePending).assertFalse();
      expect(updated.pollOptions[0].isChosen).assertFalse();
      expect(updated.pollVoteError).assertEqual(
        'ms_poll_subscribers_only'
      );
      expect(callbackError).assertEqual(updated.pollVoteError);
    });
    it('send_optimistically_adds_and_requests', 0, async () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      const before = b.sent.length;
      store.send('hello');
      const sentTypes = b.sent.slice(before).map((s: string) => (JSON.parse(s) as TdObject)['@type']);
      expect(sentTypes.includes('sendMessage')).assertTrue();
    });
    it('edit_text_sends_request_and_applies_result', 0, async () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      feedChat(b, 5);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      const original = textMessage(90, 5, true, 'old text');
      feedHistory(b, [original]);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      const before = b.sent.length;
      const pending = store.editTextAsync(90, 'new text');
      const sent = b.sent.slice(before)
        .map((s: string): TdObject => JSON.parse(s) as TdObject)
        .find((o: TdObject): boolean => o['@type'] === 'editMessageText');
      expect(sent !== undefined).assertTrue();
      expect(sent?.['message_id'] as number).assertEqual(90);
      const edited = textMessage(90, 5, true, 'new text');
      edited['edit_date'] = 200;
      edited['@extra'] = (sent?.['@extra'] as string | undefined) ?? '';
      b.onReceive(JSON.stringify(edited));
      await pending;
      expect(store.getMessages()[0].text).assertEqual('new text');
      expect(store.getMessages()[0].editDate).assertEqual(200);
    });
    it('edit_caption_sends_request_and_applies_result', 0, async () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      feedChat(b, 5);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      feedHistory(b, [videoMessage(91, 5, 300, 301)]);
      await new Promise<void>((r: (v: undefined) => void) => setTimeout(() => r(undefined), 0));
      const before = b.sent.length;
      const pending = store.editCaptionAsync(91, 'new caption');
      const sent = b.sent.slice(before)
        .map((s: string): TdObject => JSON.parse(s) as TdObject)
        .find((o: TdObject): boolean => o['@type'] === 'editMessageCaption');
      expect(sent !== undefined).assertTrue();
      expect(sent?.['message_id'] as number).assertEqual(91);
      const edited = videoMessage(91, 5, 300, 301);
      const cap: TdObject = { '@type': 'formattedText' }; cap['text'] = 'new caption';
      (edited['content'] as TdObject)['caption'] = cap;
      edited['edit_date'] = 300;
      edited['@extra'] = (sent?.['@extra'] as string | undefined) ?? '';
      b.onReceive(JSON.stringify(edited));
      await pending;
      expect(store.getMessages()[0].text).assertEqual('new caption');
    });
    it('send_poll_regular_and_quiz', 0, () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      store.sendPoll('喝什么', ['茶', '咖啡'], true, false, 0);
      let req = b.sent.map((json: string): TdObject => JSON.parse(json) as TdObject)
        .filter((o: TdObject): boolean => o['@type'] === 'sendMessage').pop();
      expect(req !== undefined).assertTrue();
      let content = req!['input_message_content'] as TdObject;
      expect(content['@type']).assertEqual('inputMessagePoll');
      expect(((content['question'] as TdObject)['text'] as string)).assertEqual('喝什么');
      expect((content['options'] as TdObject[])
        .map((o: TdObject): string => (o['text'] as string | undefined) ?? '').join(','))
        .assertEqual('茶,咖啡');
      expect(content['is_anonymous']).assertEqual(true);
      expect((content['type'] as TdObject)['@type']).assertEqual('pollTypeRegular');
      store.sendPoll('1+1=?', ['2', '3'], false, true, 0);
      req = b.sent.map((json: string): TdObject => JSON.parse(json) as TdObject)
        .filter((o: TdObject): boolean => o['@type'] === 'sendMessage').pop();
      content = req!['input_message_content'] as TdObject;
      const quizType = content['type'] as TdObject;
      expect(quizType['@type']).assertEqual('pollTypeQuiz');
      expect(quizType['correct_option_id']).assertEqual(0);
      expect(content['is_anonymous']).assertEqual(false);
    });
    it('send_location_contact_audio_dice', 0, () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      const lastContent = (): TdObject => {
        const req = b.sent.map((json: string): TdObject => JSON.parse(json) as TdObject)
          .filter((o: TdObject): boolean => o['@type'] === 'sendMessage').pop();
        return req!['input_message_content'] as TdObject;
      };
      store.sendLocation(31.23, 121.47);
      let content = lastContent();
      expect(content['@type']).assertEqual('inputMessageLocation');
      const location = content['location'] as TdObject;
      expect(location['latitude']).assertEqual(31.23);
      expect(location['longitude']).assertEqual(121.47);
      store.sendContact('8613800138000', '张', '三', 42);
      content = lastContent();
      expect(content['@type']).assertEqual('inputMessageContact');
      const contact = content['contact'] as TdObject;
      expect(contact['phone_number']).assertEqual('8613800138000');
      expect(contact['first_name']).assertEqual('张');
      expect(contact['user_id']).assertEqual(42);
      store.sendAudio('/cache/a.mp3', '好歌');
      content = lastContent();
      expect(content['@type']).assertEqual('inputMessageAudio');
      // 新版 td_api：audio 字段是 inputAudio 包装，内部才是 InputFile。
      const audioWrapper = content['audio'] as TdObject;
      expect(audioWrapper['@type']).assertEqual('inputAudio');
      expect(((audioWrapper['audio'] as TdObject)['path'] as string)).assertEqual('/cache/a.mp3');
      expect(((content['caption'] as TdObject)['text'] as string)).assertEqual('好歌');
      store.sendDice('🎯');
      content = lastContent();
      expect(content['@type']).assertEqual('inputMessageDice');
      expect(content['emoji']).assertEqual('🎯');
    });
    // video_note 必须是裸 InputFile：捆绑的 td 没有 inputVideoNote 包装类，
    // 套一层会让整条消息发不出去。duration/length 相应挂在外层。
    it('send_video_note_uses_bare_input_file_with_outer_duration_and_length', 0, () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      store.sendVideoNote('/cache/videonote_1.mp4', 12, 480);
      const req = b.sent.map((json: string): TdObject => JSON.parse(json) as TdObject)
        .filter((o: TdObject): boolean => o['@type'] === 'sendMessage').pop();
      const content = req!['input_message_content'] as TdObject;
      expect(content['@type']).assertEqual('inputMessageVideoNote');
      expect(content['duration']).assertEqual(12);
      expect(content['length']).assertEqual(480);
      const file = content['video_note'] as TdObject;
      expect(file['@type']).assertEqual('inputFileLocal');
      expect(file['path'] as string).assertEqual('/cache/videonote_1.mp4');
      expect(req!['chat_id']).assertEqual(5);
    });
    it('live 到达的照片只下缩略图，不下高清', 0, () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      pushNewMessage(b, photoMessage(87, 5, 951, 952));
      const fullRequested = b.sent.some((json: string): boolean => {
        const request = JSON.parse(json) as TdObject;
        return request['@type'] === 'downloadFile' && request['file_id'] === 952;
      });
      expect(fullRequested).assertFalse();
      const thumbRequested = b.sent.some((json: string): boolean => {
        const request = JSON.parse(json) as TdObject;
        return request['@type'] === 'downloadFile' && request['file_id'] === 951;
      });
      expect(thumbRequested).assertTrue();
    });
    // I-1 回归：窗口内有多张带 photoFullFileId 的照片同时到达时（模拟查看
    // 器打开期间又收到新消息触发 requestPhotos 的场景），store 不该对任何
    // 一张发起高清下载——高清下载完全交给查看器自己对当前图驱动。
    it('窗口内多张照片同时在场，不对任何一张自动发起高清下载', 0, () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      pushNewMessage(b, photoMessage(90, 5, 961, 962));
      pushNewMessage(b, photoMessage(91, 5, 963, 964));
      pushNewMessage(b, photoMessage(92, 5, 965, 966));
      const fullIds = [962, 964, 966];
      for (const fullId of fullIds) {
        const fullRequested = b.sent.some((json: string): boolean => {
          const request = JSON.parse(json) as TdObject;
          return request['@type'] === 'downloadFile' && request['file_id'] === fullId;
        });
        expect(fullRequested).assertFalse();
      }
    });
    it('live 到达的视频不再自动整文件下载', 0, () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      pushNewMessage(b, videoMessage(88, 5, 2002, 2003));
      const videoDownloaded = b.sent.some((json: string): boolean => {
        const request = JSON.parse(json) as TdObject;
        return request['@type'] === 'downloadFile' && request['file_id'] === 2002;
      });
      expect(videoDownloaded).assertFalse();
    });
    it('close_unsubscribes', 0, () => {
      const arr = setup(5); const b = arr[0] as FakeBridge; const store = arr[1] as MessageStore;
      store.open();
      store.close();
      pushNewMessage(b, textMessage(70, 5, false, 'z'));
      expect(store.getMessages().length).assertEqual(0);
      const types = b.sent.map((s: string) => (JSON.parse(s) as TdObject)['@type']);
      expect(types.includes('closeChat')).assertTrue();
    });
  });
}
