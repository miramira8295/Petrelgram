import { TdObject, TdRequest } from '../tdkit/TdTypes';
import { TdClient } from '../tdkit/TdClient';
import { getTdClient } from '../tdkit/Globals';
import { DrawnDocumentWidget } from './drawnDocumentWidget';
// Bounded single-flight metadata cache. Pixel lifetime/downloads stay in the
// existing file channel. No scan through documents for map updates.
const cache: Map<string, TdObject> = new Map<string, TdObject>();
const pending: Map<string, Promise<TdObject>> = new Map<string, Promise<TdObject>>();
let epoch: number = 0;
let owner: TdClient | null = null;
export function documentMapFile(widget: DrawnDocumentWidget, chatId: number, width: number, height: number): Promise<TdObject> {
  const client = getTdClient();
  if (client !== owner) { owner = client; epoch++; cache.clear(); pending.clear(); }
  const generation = epoch;
  const w = Math.max(16, Math.min(1024, Math.round(width))), h = Math.max(16, Math.min(1024, Math.round(height)));
  const key = `${chatId}:${widget.latitude}:${widget.longitude}:${widget.zoom}:${w}:${h}`;
  const hit = cache.get(key); if (hit !== undefined) { return Promise.resolve(hit); }
  const job = pending.get(key); if (job !== undefined) { return job; }
  if (pending.size >= 16) { return Promise.reject(new Error('map request capacity')); }
  const location: TdObject = { '@type': 'location' }; location['latitude'] = widget.latitude; location['longitude'] = widget.longitude;
  const request: TdRequest = { '@type': 'getMapThumbnailFile' };
  request['location'] = location; request['zoom'] = widget.zoom; request['width'] = w; request['height'] = h;
  request['scale'] = 2; request['chat_id'] = chatId;
  const promise = client.send(request).then((file: TdObject): TdObject => {
    if (owner === client && generation === epoch) {
      pending.delete(key); cache.set(key, file);
      if (cache.size > 64) { cache.delete(cache.keys().next().value as string); }
    }
    return file;
  }).catch((error: Object): TdObject => {
    if (owner === client && generation === epoch) { pending.delete(key); }
    throw new Error(`Map thumbnail request failed: ${String(error)}`);
  });
  pending.set(key, promise); return promise;
}
