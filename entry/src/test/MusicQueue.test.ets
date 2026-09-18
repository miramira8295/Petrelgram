import { describe, it, expect } from '@ohos/hypium';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdObject, TdBridge } from '../main/ets/tdkit/TdTypes';
import { UserStore } from '../main/ets/store/UserStore';
import { buildMessageEntry, MessageEntry } from '../main/ets/store/MessageEntry';
import { VoiceState } from '../main/ets/services/VoicePlayback';
import {
  adjacentAudioEntry, audioQueueLength, audioQueuePosition, MusicQueue, MusicQueueDeps
} from '../main/ets/services/MusicQueue';

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
  user['id'] = 7; user['first_name'] = 'Ann'; user['last_name'] = '';
  const upd: TdObject = { '@type': 'updateUser' }; upd['user'] = user;
  b.onReceive(JSON.stringify(upd));
  return u;
}

// An audio message; `duration` seconds. Text messages stand in for "not audio".
function audioMsg(id: number, duration: number): TdObject {
  const file: TdObject = { '@type': 'file' };
  file['id'] = id * 100;
  const local: TdObject = { '@type': 'localFile' };
  local['path'] = ''; local['is_downloading_completed'] = false;
  file['local'] = local;
  const remote: TdObject = { '@type': 'remoteFile' }; remote['id'] = `r${id}`;
  file['remote'] = remote;
  file['size'] = 1000;
  const audio: TdObject = { '@type': 'audio' };
  audio['duration'] = duration; audio['file_name'] = `t${id}.mp3`;
  audio['mime_type'] = 'audio/mpeg'; audio['audio'] = file;
  const content: TdObject = { '@type': 'messageAudio' }; content['audio'] = audio;
  const sender: TdObject = { '@type': 'messageSenderUser' }; sender['user_id'] = 7;
  const m: TdObject = { '@type': 'message' };
  m['id'] = id; m['is_outgoing'] = false; m['sender_id'] = sender;
  m['date'] = 100; m['content'] = content;
  return m;
}

function textMsg(id: number): TdObject {
  const ft: TdObject = { '@type': 'formattedText' }; ft['text'] = 'hi';
  const c: TdObject = { '@type': 'messageText' }; c['text'] = ft;
  const sender: TdObject = { '@type': 'messageSenderUser' }; sender['user_id'] = 7;
  const m: TdObject = { '@type': 'message' };
  m['id'] = id; m['is_outgoing'] = false; m['sender_id'] = sender;
  m['date'] = 100; m['content'] = c;
  return m;
}

function audioEntry(id: number, duration: number): MessageEntry {
  return buildMessageEntry(audioMsg(id, duration), usersOf());
}

function textEntry(id: number): MessageEntry {
  return buildMessageEntry(textMsg(id), usersOf());
}

// A downloaded track: buildMessageEntry leaves videoPath empty until TDLib
// reports a local file, so set it directly for the "ready to play" cases.
function downloaded(entry: MessageEntry, path: string): MessageEntry {
  entry.videoPath = path;
  return entry;
}

interface Call {
  kind: string;
  id: number;
  arg: string;
}

class Recorder {
  calls: Call[] = [];
  toasts: string[] = [];
  state: VoiceState = {
    playingId: 0, paused: false, positionMs: 0, durationMs: 0, completedId: 0,
    status: 'idle', mode: 'idle', speed: 1, errorId: 0
  };

  deps(): MusicQueueDeps {
    return {
      currentState: (): VoiceState => this.state,
      toggleMusic: (id: number, path: string): void => {
        this.calls.push({ kind: 'toggle', id, arg: path });
      },
      startMusic: (id: number, path: string): void => {
        this.calls.push({ kind: 'start', id, arg: path });
      },
      seek: (id: number, fraction: number): void => {
        this.calls.push({ kind: 'seek', id, arg: `${fraction}` });
      },
      playStream: (id: number, fileId: number, sizeBytes: number, mimeType: string,
        dur: number, forceStart: boolean): void => {
        this.calls.push({ kind: 'stream', id, arg: `${fileId}:${sizeBytes}:${forceStart}` });
      },
      requestDownload: (id: number, failed: boolean): void => {
        this.calls.push({ kind: 'download', id, arg: `${failed}` });
      },
      toast: (message: string): void => { this.toasts.push(message); }
    };
  }

  kinds(): string {
    return this.calls.map((c: Call): string => `${c.kind}:${c.id}`).join(',');
  }
}

export default function musicQueueTest() {
  describe('musicQueue', () => {
    it('adjacent skips non-audio messages', 0, () => {
      const list: MessageEntry[] = [
        audioEntry(1, 60), textEntry(2), audioEntry(3, 60), audioEntry(5, 60)
      ];
      expect(adjacentAudioEntry(list, 1, 1)!.id).assertEqual(3);
      expect(adjacentAudioEntry(list, 3, 1)!.id).assertEqual(5);
      expect(adjacentAudioEntry(list, 3, -1)!.id).assertEqual(1);
    });

    it('adjacent returns null at both ends', 0, () => {
      const list: MessageEntry[] = [audioEntry(1, 60), audioEntry(3, 60)];
      expect(adjacentAudioEntry(list, 1, -1) === null).assertTrue();
      expect(adjacentAudioEntry(list, 3, 1) === null).assertTrue();
    });

    it('adjacent returns null for a non-audio or unknown id', 0, () => {
      const list: MessageEntry[] = [audioEntry(1, 60), textEntry(2), audioEntry(3, 60)];
      expect(adjacentAudioEntry(list, 2, 1) === null).assertTrue();
      expect(adjacentAudioEntry(list, 99, 1) === null).assertTrue();
    });

    it('length and position count only audio, 1-based', 0, () => {
      const list: MessageEntry[] = [
        textEntry(1), audioEntry(2, 60), textEntry(3), audioEntry(4, 60)
      ];
      expect(audioQueueLength(list)).assertEqual(2);
      expect(audioQueuePosition(list, 2)).assertEqual(1);
      expect(audioQueuePosition(list, 4)).assertEqual(2);
      expect(audioQueuePosition(list, 3)).assertEqual(0);
      expect(audioQueuePosition(list, 99)).assertEqual(0);
    });

    it('play toggles a downloaded track, starts it when forced', 0, () => {
      const rec = new Recorder();
      const q = new MusicQueue(rec.deps());
      const list: MessageEntry[] = [downloaded(audioEntry(1, 60), '/a.mp3')];
      q.play(list, 1, false);
      q.play(list, 1, true);
      expect(rec.kinds()).assertEqual('toggle:1,start:1');
      expect(q.getPendingPlayId()).assertEqual(0);
    });

    // 2026-09-18：音频改成边下边放（视频一直是）。只要 file id 和总大小都在，
    // 点了就出声，不再排队等整首下完，也不再弹"开始下载"。
    it('play streams an undownloaded track instead of waiting', 0, () => {
      const rec = new Recorder();
      const q = new MusicQueue(rec.deps());
      const list: MessageEntry[] = [audioEntry(1, 60)];
      q.play(list, 1, false);
      expect(rec.kinds()).assertEqual('stream:1');
      expect(q.getPendingPlayId()).assertEqual(0);
      expect(rec.toasts.length).assertEqual(0);
    });

    // 总大小不明时流没法按 Range 定位，必须退回老路：排队 + 下载 + 提示。
    it('play falls back to downloading when the size is unknown', 0, () => {
      const rec = new Recorder();
      const q = new MusicQueue(rec.deps());
      const entry = audioEntry(1, 60);
      entry.videoFileSize = 0;
      q.play([entry], 1, false);
      expect(rec.kinds()).assertEqual('download:1');
      expect(q.getPendingPlayId()).assertEqual(1);
      expect(rec.toasts[0]).assertEqual('mq_download_started');
    });

    // 下载失败过的那条也走下载重试，不流——流会一头撞进同一个失败。
    it('play retries the download for a failed track', 0, () => {
      const rec = new Recorder();
      const q = new MusicQueue(rec.deps());
      const entry = audioEntry(1, 60);
      entry.videoFailed = true;
      q.play([entry], 1, false);
      expect(rec.kinds()).assertEqual('download:1');
      expect(q.getPendingPlayId()).assertEqual(1);
      expect(rec.toasts[0]).assertEqual('mq_redownloading');
    });

    it('play refuses a track with no file at all', 0, () => {
      const rec = new Recorder();
      const q = new MusicQueue(rec.deps());
      const entry = audioEntry(1, 60);
      entry.videoFileId = 0;
      q.play([entry], 1, false);
      expect(rec.calls.length).assertEqual(0);
      expect(q.getPendingPlayId()).assertEqual(0);
      expect(rec.toasts[0]).assertEqual('mq_audio_unavailable');
    });

    it('play ignores a non-audio target', 0, () => {
      const rec = new Recorder();
      const q = new MusicQueue(rec.deps());
      q.play([textEntry(1)], 1, false);
      expect(rec.calls.length).assertEqual(0);
      expect(rec.toasts.length).assertEqual(0);
    });

    it('settlePending starts the awaited track once it has a path', 0, () => {
      const rec = new Recorder();
      const q = new MusicQueue(rec.deps());
      // size 未知才会进排队那条路（有 size 就直接流了，见上面那条用例）。
      const pendingEntry = audioEntry(1, 60);
      pendingEntry.videoFileSize = 0;
      q.play([pendingEntry], 1, false);
      expect(q.getPendingPlayId()).assertEqual(1);
      q.settlePending([downloaded(audioEntry(1, 60), '/a.mp3')]);
      expect(rec.kinds()).assertEqual('download:1,start:1');
      expect(q.getPendingPlayId()).assertEqual(0);
    });

    it('settlePending gives up when the download failed', 0, () => {
      const rec = new Recorder();
      const q = new MusicQueue(rec.deps());
      const pendingEntry = audioEntry(1, 60);
      pendingEntry.videoFileSize = 0;
      q.play([pendingEntry], 1, false);
      const failed = audioEntry(1, 60);
      failed.videoFailed = true;
      q.settlePending([failed]);
      expect(q.getPendingPlayId()).assertEqual(0);
      expect(rec.toasts[rec.toasts.length - 1]).assertEqual('mq_download_failed');
    });

    it('settlePending gives up when the message vanished', 0, () => {
      const rec = new Recorder();
      const q = new MusicQueue(rec.deps());
      const pendingEntry = audioEntry(1, 60);
      pendingEntry.videoFileSize = 0;
      q.play([pendingEntry], 1, false);
      q.settlePending([]);
      expect(q.getPendingPlayId()).assertEqual(0);
      expect(rec.kinds()).assertEqual('download:1');
    });

    it('settlePending is a no-op with nothing pending', 0, () => {
      const rec = new Recorder();
      const q = new MusicQueue(rec.deps());
      q.settlePending([downloaded(audioEntry(1, 60), '/a.mp3')]);
      expect(rec.calls.length).assertEqual(0);
    });

    it('completion advances to the next track', 0, () => {
      const rec = new Recorder();
      const q = new MusicQueue(rec.deps());
      const list: MessageEntry[] = [
        downloaded(audioEntry(1, 60), '/a.mp3'), downloaded(audioEntry(3, 60), '/b.mp3')
      ];
      q.onCompleted(list, 1);
      expect(rec.kinds()).assertEqual('start:3');
    });

    it('completion on the last track does nothing', 0, () => {
      const rec = new Recorder();
      const q = new MusicQueue(rec.deps());
      q.onCompleted([downloaded(audioEntry(1, 60), '/a.mp3')], 1);
      expect(rec.calls.length).assertEqual(0);
    });

    it('previous restarts the track when past 3s', 0, () => {
      const rec = new Recorder();
      rec.state.mode = 'music';
      rec.state.playingId = 3;
      rec.state.positionMs = 3001;
      const q = new MusicQueue(rec.deps());
      const list: MessageEntry[] = [
        downloaded(audioEntry(1, 60), '/a.mp3'), downloaded(audioEntry(3, 60), '/b.mp3')
      ];
      q.previous(list, 3);
      expect(rec.kinds()).assertEqual('seek:3');
    });

    it('previous skips back when within the first 3s', 0, () => {
      const rec = new Recorder();
      rec.state.mode = 'music';
      rec.state.playingId = 3;
      rec.state.positionMs = 2999;
      const q = new MusicQueue(rec.deps());
      const list: MessageEntry[] = [
        downloaded(audioEntry(1, 60), '/a.mp3'), downloaded(audioEntry(3, 60), '/b.mp3')
      ];
      q.previous(list, 3);
      expect(rec.kinds()).assertEqual('start:1');
    });

    it('previous on the first track rewinds instead of stalling', 0, () => {
      const rec = new Recorder();
      rec.state.mode = 'music';
      rec.state.playingId = 1;
      rec.state.positionMs = 500;
      const q = new MusicQueue(rec.deps());
      q.previous([downloaded(audioEntry(1, 60), '/a.mp3')], 1);
      expect(rec.kinds()).assertEqual('seek:1');
    });

    it('reset clears a pending play', 0, () => {
      const rec = new Recorder();
      const q = new MusicQueue(rec.deps());
      const pendingEntry = audioEntry(1, 60);
      pendingEntry.videoFileSize = 0;
      q.play([pendingEntry], 1, false);
      q.reset();
      expect(q.getPendingPlayId()).assertEqual(0);
    });
  });
}
