// 「这首机器人搜来的歌已经发过了」的记录（2026-09-20）。
//
// 【为什么需要】机器人结果要能进合集、能下载、能离线，唯一稳妥的办法是把它
// 发进自己的收藏夹，变成一条真正的音频消息——之后 chatId/messageId 齐全，
// 后续逻辑和曲库里的歌完全一样（合集、下载中心、文件引用自动刷新都免费拿到）。
//
// 但"播放即发送"有个副作用：同一首歌隔天再搜一次再播，会在收藏夹里再堆一条。
// 这张表把 `resultId → 曲目键` 记下来，再遇到同一个结果就直接复用那条消息。
//
// 【自愈】记录可能失效（用户手动删了那条消息）。调用方取不到消息时把这条删掉
// 重发即可——所以这里只做纯粹的读写，不判断有效性。
//
// 【为什么单独一个模型文件】序列化要能单测；存取在 store/MusicBotSentStore。

export interface MusicBotSentEntry {
  // 内联结果 id（LyBot 给的是 YouTube 视频 id，跨次搜索稳定）。
  resultId: string;
  // 发出去之后那条消息的曲目键（chatId_messageId）。
  trackKey: string;
  // 记下来的时间，毫秒。只用于按时间裁剪，不参与判断。
  sentAt: number;
}

// 上限。收藏夹里真发过的歌不会多到哪儿去，但这张表要随账号常驻，给个天花板，
// 超了按时间从旧到新裁掉——裁掉只是下次会重发一条，不会丢数据。
export const MUSIC_BOT_SENT_LIMIT: number = 500;

export function parseMusicBotSent(raw: string): MusicBotSentEntry[] {
  if (raw === '') {
    return [];
  }
  let parsed: Object | null = null;
  try {
    parsed = JSON.parse(raw) as Object;
  } catch (e) {
    return [];
  }
  if (!Array.isArray(parsed)) {
    return [];
  }
  const out: MusicBotSentEntry[] = [];
  for (const row of parsed as Object[]) {
    const record = row as Record<string, Object>;
    const resultId: string = (record['resultId'] as string | undefined) ?? '';
    const trackKey: string = (record['trackKey'] as string | undefined) ?? '';
    if (resultId === '' || trackKey === '') {
      continue;
    }
    out.push({
      resultId: resultId,
      trackKey: trackKey,
      sentAt: (record['sentAt'] as number | undefined) ?? 0
    });
  }
  return out;
}

export function serializeMusicBotSent(entries: MusicBotSentEntry[]): string {
  return JSON.stringify(entries);
}

export function findMusicBotSent(entries: MusicBotSentEntry[], resultId: string): string {
  const hit: MusicBotSentEntry | undefined =
    entries.find((e: MusicBotSentEntry): boolean => e.resultId === resultId);
  return hit !== undefined ? hit.trackKey : '';
}

// 记一条。同一个 resultId 覆盖旧的（消息被删之后重发会走到这里）。
// 超过上限就按 sentAt 从旧到新裁掉。
export function rememberMusicBotSent(
  entries: MusicBotSentEntry[], resultId: string, trackKey: string, now: number
): MusicBotSentEntry[] {
  if (resultId === '' || trackKey === '') {
    return entries;
  }
  const kept: MusicBotSentEntry[] =
    entries.filter((e: MusicBotSentEntry): boolean => e.resultId !== resultId);
  kept.push({ resultId: resultId, trackKey: trackKey, sentAt: now });
  if (kept.length <= MUSIC_BOT_SENT_LIMIT) {
    return kept;
  }
  const sorted: MusicBotSentEntry[] = kept.slice().sort(
    (a: MusicBotSentEntry, b: MusicBotSentEntry): number => a.sentAt - b.sentAt);
  return sorted.slice(sorted.length - MUSIC_BOT_SENT_LIMIT);
}

// 那条消息没了（用户删了收藏夹里的记录）：忘掉它，下次重发。
export function forgetMusicBotSent(
  entries: MusicBotSentEntry[], resultId: string
): MusicBotSentEntry[] {
  return entries.filter((e: MusicBotSentEntry): boolean => e.resultId !== resultId);
}
