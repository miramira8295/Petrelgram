import { documentEmbedUrl, documentEmbedDirectVideo } from './documentEmbedNavigation';
import { TdObject } from '../tdkit/TdTypes';
import { documentFileId } from './drawnDocumentMedia';
export interface DrawnDocumentWidget {
  html?: string; allowScrolling?: boolean;
  url?: string; date?: number; avatar?: TdObject; avatarMini?: string;
  coverFileId?: number; coverMini?: string; thumbnailFile?: TdObject; thumbnailMini?: string;
  duration?: number; waveform?: string; performer?: string; title?: string;
  key: string; kind: string; file?: TdObject; name: string; mimeType: string; size: number;
  latitude: number; longitude: number; zoom: number; width: number; height: number;
}
export interface DrawnDocumentWidgetPlacement { widget: DrawnDocumentWidget; x: number; y: number; width: number; height: number; }
export function drawnDocumentWidget(node: TdObject, key: string): DrawnDocumentWidget | null {
  const type = node['@type'];
  const result: DrawnDocumentWidget = { key, kind: '', name: '', mimeType: '', size: 0,
    latitude: 0, longitude: 0, zoom: 15, width: 320, height: 180 };
  if (type === 'pageBlockEmbedded') {
    const html = (node['html'] as string | undefined) ?? '';
    const url = (node['url'] as string | undefined) ?? '';
    const width = node['width'] as number, height = node['height'] as number;
    // HTML and HTTP(S) documents use ArkWeb; zero dimensions await resize_frame.
    // tg-widget requires its own host; never treat a widget as arbitrary HTML.
    if ((html === '' && !documentEmbedUrl(url)) || html.length > 131072 || url.length > 8192 || url.startsWith('tg-widget:') ||
      !Number.isFinite(width) || !Number.isFinite(height) || width < 0 || height < 0) { return null; }
    result.kind = documentEmbedDirectVideo(url, html) ? 'video-embed' : 'html-embed'; result.html = html; result.url = url;
    if (result.kind === 'video-embed' && (width === 0 || height === 0)) { result.width = 16; result.height = 9; }
    const poster: TdObject = { '@type': 'pageBlockEmbeddedPost' }; poster['author_photo'] = node['poster_photo'];
    const image = drawnDocumentWidget(poster, key);
    result.avatar = image?.avatar; result.avatarMini = image?.avatarMini;
    if (result.kind !== 'video-embed' || (width > 0 && height > 0)) { result.width = width; result.height = height; }
    result.allowScrolling = node['allow_scrolling'] === true;
    return result;
  }
  if (type === 'pageBlockChatLink') {
    const username = (node['username'] as string | undefined) ?? '';
    if (!/^[A-Za-z0-9_]+$/.test(username)) { return null; }
    result.kind = 'chat-link'; result.name = (node['title'] as string | undefined) || username;
    result.url = `https://t.me/${username}`;
    const photo = node['photo'] as TdObject | undefined;
    result.avatar = photo?.['small'] as TdObject | undefined;
    const mini = photo?.['minithumbnail'] as TdObject | undefined;
    const image = (mini?.['data'] as string | undefined) ?? '';
    result.avatarMini = image !== '' ? `data:image/jpeg;base64,${image}` : '';
    return result;
  }
  if (type === 'pageBlockEmbeddedPost') {
    result.kind = 'post-author'; result.name = (node['author'] as string | undefined) ?? '';
    result.url = (node['url'] as string | undefined) ?? '';
    const date = (node['date'] as number | undefined) ?? 0;
    result.date = Number.isFinite(date) && date > 0 && date <= 8640000000000 ? date : 0;
    const photo = node['author_photo'] as TdObject | undefined;
    const sizes = (photo?.['sizes'] as TdObject[] | undefined) ?? [];
    let distance = Number.POSITIVE_INFINITY;
    for (const size of sizes) {
      const file = size['photo'] as TdObject | undefined;
      const width = size['width'] as number, height = size['height'] as number;
      if (!Number.isSafeInteger(documentFileId(file)) || documentFileId(file) <= 0 ||
        !Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) { continue; }
      const next = Math.abs(Math.max(width, height) - 80);
      if (next < distance) { distance = next; result.avatar = file; }
    }
    const mini = photo?.['minithumbnail'] as TdObject | undefined;
    const image = (mini?.['data'] as string | undefined) ?? '';
    result.avatarMini = image !== '' ? `data:image/jpeg;base64,${image}` : '';
    return result;
  }
  if (type === 'pageBlockMap') {
    const location = node['location'] as TdObject | undefined;
    const lat = location?.['latitude'] as number, lon = location?.['longitude'] as number;
    if (!Number.isFinite(lat) || !Number.isFinite(lon) || Math.abs(lat) > 90 || Math.abs(lon) > 180) { return null; }
    result.kind = 'map'; result.latitude = lat; result.longitude = lon;
    const zoom = (node['zoom'] as number | undefined) ?? 15;
    result.zoom = Number.isFinite(zoom) ? Math.max(13, Math.min(20, Math.round(zoom))) : 15;
    const width = node['width'] as number, height = node['height'] as number;
    if (Number.isFinite(width) && width > 0) { result.width = width; }
    if (Number.isFinite(height) && height > 0) { result.height = height; }
    return result;
  }
  if (type === 'pageBlockDocument' || type === 'pageBlockVoiceNote' || type === 'pageBlockAudio') {
    const voice = type === 'pageBlockVoiceNote', music = type === 'pageBlockAudio';
    const doc = node[voice ? 'voice_note' : music ? 'audio' : 'document'] as TdObject | undefined;
    const file = doc?.[voice ? 'voice' : music ? 'audio' : 'document'] as TdObject | undefined;
    if (file === undefined || !Number.isSafeInteger(documentFileId(file)) || documentFileId(file) <= 0) { return null; }
    result.kind = voice ? 'voice' : music ? 'audio' : 'file'; result.file = file;
    if (!voice && !music) {
      const thumb = doc?.['thumbnail'] as TdObject | undefined;
      result.thumbnailFile = thumb?.['file'] as TdObject | undefined;
      const mini = doc?.['minithumbnail'] as TdObject | undefined;
      const data = (mini?.['data'] as string | undefined) ?? '';
      result.thumbnailMini = data !== '' ? `data:image/jpeg;base64,${data}` : '';
    }
    const cover = doc?.['album_cover_thumbnail'] as TdObject | undefined;
    result.coverFileId = documentFileId(cover?.['file'] as TdObject | undefined);
    const mini = doc?.['album_cover_minithumbnail'] as TdObject | undefined;
    const miniData = (mini?.['data'] as string | undefined) ?? '';
    result.coverMini = miniData !== '' ? `data:image/jpeg;base64,${miniData}` : '';
    result.performer = (doc?.['performer'] as string | undefined) ?? '';
    result.title = (doc?.['title'] as string | undefined) ?? '';
    const duration = (doc?.['duration'] as number | undefined) ?? 0;
    result.duration = Number.isFinite(duration) ? Math.max(0, duration) : 0;
    result.waveform = (doc?.['waveform'] as string | undefined) ?? '';
    result.name = (doc?.['file_name'] as string | undefined) ?? '';
    result.mimeType = (doc?.['mime_type'] as string | undefined) ?? '';
    result.size = ((file['size'] as number | undefined) ?? 0) || ((file['expected_size'] as number | undefined) ?? 0);
    return result;
  }
  return null;
}
