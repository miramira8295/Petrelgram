import { unifiedDataChannel as udc } from '@kit.ArkData';
import { fileUri, fileIo } from '@kit.CoreFileKit';
import { messageDragOriginTag } from '../util/messageDragOrigin';
import { getActiveTdAccountSlot, getTdClient } from '../tdkit/Globals';
import { TdObject, TdRequest } from '../tdkit/TdTypes';
import { completedDragFilePath, messageDragPayload } from '../util/messageDrag';
import { logW } from '../util/log';

// The system owns this one-shot provider after drag start. Do not bind its lifetime
// to a recycled bubble or to onDragEnd (receivers may still be reading then).
export function configureMessageDrag(event: DragEvent, chatId: number, messageId: number, type: string): DragItemInfo {
  const client = getTdClient();
  const originTag = messageDragOriginTag(getActiveTdAccountSlot(), chatId);
  let pending: Promise<udc.UnifiedData | null> | undefined = undefined;
  const load = async (): Promise<udc.UnifiedData | null> => {
    try {
      if (client !== getTdClient()) { return null; }
      const req: TdRequest = { '@type': 'getMessage' };
      req['chat_id'] = chatId; req['message_id'] = messageId;
      const propsReq: TdRequest = { '@type': 'getMessageProperties' };
      propsReq['chat_id'] = chatId; propsReq['message_id'] = messageId;
      const results: TdObject[] = await Promise.all([client.send(req, 3000), client.send(propsReq, 3000)]);
      const payload = messageDragPayload(results[0], results[1]);
      if (!payload || payload.type !== type || client !== getTdClient()) { return null; }
      if (payload.fileId === 0) {
        const record = new udc.PlainText();
        record.textContent = payload.text;
        return new udc.UnifiedData(record);
      }
      const fileReq: TdRequest = { '@type': 'getFile' };
      fileReq['file_id'] = payload.fileId;
      const path = completedDragFilePath(await client.send(fileReq, 3000));
      if (path === '' || !await fileIo.access(path) || client !== getTdClient()) { return null; }
      const uri = fileUri.getUriFromPath(path);
      let record: udc.File;
      if (type === 'general.image') { const image = new udc.Image(); image.imageUri = uri; record = image; }
      else if (type === 'general.video') { const video = new udc.Video(); video.videoUri = uri; record = video; }
      else if (type === 'general.audio') { const audio = new udc.Audio(); audio.audioUri = uri; record = audio; }
      else { record = new udc.File(); record.uri = uri; }
      return new udc.UnifiedData(record);
    } catch (_) {
      logW('[DragOut] content unavailable');
      return null;
    }
  };
  event.setDataLoadParams({
    dataLoadInfo: { types: new Set<string>([type]), recordCount: 1 },
    loadHandler: (): udc.UnifiedData | null => null,
    delayedDataLoadHandler: (): Promise<udc.UnifiedData | null> => {
      if (!pending) { pending = load(); }
      return pending.then((data: udc.UnifiedData | null): udc.UnifiedData | null => {
        if (client !== getTdClient() || data === null) { return null; }
        const properties = data.properties;
        properties.tag = originTag;
        data.properties = properties;
        return data;
      });
    }
  });
  return { extraInfo: originTag };
}
