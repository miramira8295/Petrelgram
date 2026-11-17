import { DrawnDocumentWidget } from './drawnDocumentWidget';
import { documentFileId } from './drawnDocumentMedia';
import { documentFileState } from './documentFileChannel';
import { MusicTrack } from './musicTrackModel';

// Android retains realId alongside each embedded audio's synthetic identity.
// A single O(1) snapshot is published on user action, never on playback ticks.
export function documentAudioTrack(widget: DrawnDocumentWidget, chatId: number,
  messageId: number, path: string): MusicTrack {
  const fileId = documentFileId(widget.file);
  return { chatId, messageId: -fileId, sourceMessageId: messageId,
    title: widget.title || widget.name, artist: widget.performer ?? '', album: '',
    durationSec: widget.duration ?? 0, fileId, fileSize: widget.size, mimeType: widget.mimeType,
    fileName: widget.name, localPath: path, coverFileId: widget.coverFileId ?? 0, coverMini: widget.coverMini ?? '', botResultId: '' };
}

interface DocumentAudioSnapshot { chatId: number; messageId: number; tracks: MusicTrack[]; }
// Weak ownership: source eviction releases the snapshot. One build per source,
// not one copy per audio control. Duplicate file identities are coalesced.
const playlists: WeakMap<DrawnDocumentWidget[], DocumentAudioSnapshot> = new WeakMap();
export function documentAudioPlaylist(items: DrawnDocumentWidget[], chatId: number, messageId: number): MusicTrack[] {
  const hit = playlists.get(items);
  if (hit !== undefined && hit.chatId === chatId && hit.messageId === messageId) { return hit.tracks; }
  const tracks: MusicTrack[] = [], ids = new Set<number>();
  for (const item of items) {
    const id = documentFileId(item.file);
    if (item.kind !== 'audio' || id <= 0 || ids.has(id)) { continue; }
    ids.add(id);
    tracks.push(documentAudioTrack(item, chatId, messageId, item.file !== undefined ? documentFileState(item.file).path : ''));
    if (tracks.length === 2048) { break; }
  }
  playlists.set(items, { chatId, messageId, tracks }); return tracks;
}
