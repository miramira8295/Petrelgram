import { TdObject } from '../tdkit/TdTypes';

export interface MessageDragPayload {
  type: string;
  text: string;
  fileId: number;
}

export function messageDragType(contentType: string): string {
  if (contentType === 'text' || contentType === 'emoji') { return 'general.plain-text'; }
  if (contentType === 'photo') { return 'general.image'; }
  if (contentType === 'video') { return 'general.video'; }
  if (contentType === 'audio' || contentType === 'voice') { return 'general.audio'; }
  if (contentType === 'file') { return 'general.file'; }
  return '';
}

// Resolve original TDLib files, never the renderer's thumbnail/poster paths.
export function messageDragPayload(message: TdObject, properties: TdObject): MessageDragPayload | null {
  if (message['has_protected_content'] === true ||
    properties['has_protected_content_by_current_user'] === true ||
    properties['has_protected_content_by_other_user'] === true || properties['can_be_forwarded'] !== true ||
    message['self_destruct_type'] || message['sending_state']) { return null; }
  const content = message['content'] as TdObject | undefined;
  if (!content) { return null; }
  const kind = content['@type'] as string;
  if (kind === 'messageText') {
    const formatted = content['text'] as TdObject | undefined;
    const text = (formatted?.['text'] as string | undefined) ?? '';
    return text === '' ? null : { type: 'general.plain-text', text, fileId: 0 };
  }
  if (properties['can_be_saved'] !== true) { return null; }
  let file: TdObject | undefined;
  let type: string = '';
  if (kind === 'messagePhoto') {
    const photo = content['photo'] as TdObject | undefined;
    const sizes = (photo?.['sizes'] as TdObject[] | undefined) ?? [];
    let area: number = -1;
    for (const size of sizes) {
      const candidate = (size['width'] as number) * (size['height'] as number);
      if (candidate > area) { area = candidate; file = size['photo'] as TdObject; }
    }
    type = 'general.image';
  } else {
    let field: string = '';
    if (kind === 'messageVideo') { field = 'video'; type = 'general.video'; }
    if (kind === 'messageAnimation') { field = 'animation'; type = 'general.video'; }
    if (kind === 'messageAudio') { field = 'audio'; type = 'general.audio'; }
    if (kind === 'messageVoiceNote') { field = 'voice_note'; type = 'general.audio'; }
    if (kind === 'messageDocument') { field = 'document'; type = 'general.file'; }
    const media = content[field] as TdObject | undefined;
    file = media?.[field] as TdObject | undefined;
  }
  const fileId = (file?.['id'] as number | undefined) ?? 0;
  return type !== '' && fileId > 0 ? { type, text: '', fileId } : null;
}

export function completedDragFilePath(file: TdObject): string {
  const local = file['local'] as TdObject | undefined;
  const path = (local?.['path'] as string | undefined) ?? '';
  return local?.['is_downloading_completed'] === true && path.startsWith('/') ? path : '';
}
