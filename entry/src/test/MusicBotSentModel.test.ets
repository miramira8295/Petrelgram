import { describe, expect, it } from '@ohos/hypium';
import {
  findMusicBotSent, forgetMusicBotSent, MUSIC_BOT_SENT_LIMIT, MusicBotSentEntry,
  parseMusicBotSent, rememberMusicBotSent, serializeMusicBotSent
} from '../main/ets/util/musicBotSentModel';

// 「机器人搜来的歌已经发过哪些」的数据模型（2026-09-20）。
//
// 背景：机器人搜索结果没有 chatId/messageId，进不了合集。做法是点播放那一刻把它
// 发进收藏夹换成一条真音频消息。副作用是同一首歌隔天再搜再播会再堆一条——这张表
// 记下 resultId → 曲目键，再遇到同一个结果就复用那条消息。
//
// 全部纯函数且不改入参（仓库规矩：返回新数组）。

function entry(resultId: string, key: string, at: number): MusicBotSentEntry {
  return { resultId: resultId, trackKey: key, sentAt: at };
}

export default function musicBotSentModelTest() {
  describe('musicBotSentModel', () => {
    it('roundtrips_through_json', 0, () => {
      const rows: MusicBotSentEntry[] = [
        entry('SJKoWAd5ySo', '-100123_4096', 1000),
        entry('DxpndDEAqGk', '-100123_4097', 2000)
      ];
      const back: MusicBotSentEntry[] = parseMusicBotSent(serializeMusicBotSent(rows));
      expect(back.length).assertEqual(2);
      expect(back[0].resultId).assertEqual('SJKoWAd5ySo');
      expect(back[1].trackKey).assertEqual('-100123_4097');
      expect(back[1].sentAt).assertEqual(2000);
    });

    it('parses_garbage_as_empty', 0, () => {
      expect(parseMusicBotSent('').length).assertEqual(0);
      expect(parseMusicBotSent('not json').length).assertEqual(0);
      expect(parseMusicBotSent('{"a":1}').length).assertEqual(0);
      // 缺字段的行整条丢掉，别让空键进到查找里。
      expect(parseMusicBotSent('[{"resultId":"x"},{"trackKey":"y"}]').length).assertEqual(0);
    });

    it('finds_by_result_id', 0, () => {
      const rows: MusicBotSentEntry[] = [entry('a', '-1_2', 10), entry('b', '-1_3', 20)];
      expect(findMusicBotSent(rows, 'b')).assertEqual('-1_3');
      expect(findMusicBotSent(rows, 'zzz')).assertEqual('');
      expect(findMusicBotSent([], 'a')).assertEqual('');
    });

    it('remember_overwrites_the_same_result', 0, () => {
      // 用户删了收藏夹里那条、我们重发一条：同一个 resultId 只能留最新的键，
      // 否则 find 会拿到那条已经不存在的消息。
      const once: MusicBotSentEntry[] = rememberMusicBotSent([], 'a', '-1_2', 10);
      const twice: MusicBotSentEntry[] = rememberMusicBotSent(once, 'a', '-1_9', 20);
      expect(twice.length).assertEqual(1);
      expect(findMusicBotSent(twice, 'a')).assertEqual('-1_9');
      // 不改入参
      expect(once.length).assertEqual(1);
      expect(findMusicBotSent(once, 'a')).assertEqual('-1_2');
    });

    it('remember_ignores_empty_ids', 0, () => {
      expect(rememberMusicBotSent([], '', '-1_2', 10).length).assertEqual(0);
      expect(rememberMusicBotSent([], 'a', '', 10).length).assertEqual(0);
    });

    it('remember_trims_oldest_past_the_limit', 0, () => {
      let rows: MusicBotSentEntry[] = [];
      for (let i = 0; i < MUSIC_BOT_SENT_LIMIT; i++) {
        rows = rememberMusicBotSent(rows, `r${i}`, `-1_${i}`, i);
      }
      expect(rows.length).assertEqual(MUSIC_BOT_SENT_LIMIT);
      const over: MusicBotSentEntry[] = rememberMusicBotSent(rows, 'newest', '-1_x', 999999);
      expect(over.length).assertEqual(MUSIC_BOT_SENT_LIMIT);
      // 最旧的那条被裁掉，最新的留下。
      expect(findMusicBotSent(over, 'r0')).assertEqual('');
      expect(findMusicBotSent(over, 'newest')).assertEqual('-1_x');
    });

    it('forget_removes_one_entry', 0, () => {
      const rows: MusicBotSentEntry[] = [entry('a', '-1_2', 10), entry('b', '-1_3', 20)];
      const after: MusicBotSentEntry[] = forgetMusicBotSent(rows, 'a');
      expect(after.length).assertEqual(1);
      expect(findMusicBotSent(after, 'a')).assertEqual('');
      expect(findMusicBotSent(after, 'b')).assertEqual('-1_3');
      // 不改入参
      expect(rows.length).assertEqual(2);
    });
  });
}
