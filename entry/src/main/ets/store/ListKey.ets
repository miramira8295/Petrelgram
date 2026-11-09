import { TdObject } from '../tdkit/TdTypes';

export function listKeyOf(chatList: TdObject): string {
  const type = chatList['@type'] as string | undefined;
  if (type === 'chatListMain') {
    return 'main';
  }
  if (type === 'chatListArchive') {
    return 'archive';
  }
  if (type === 'chatListFolder') {
    const fid = chatList['chat_folder_id'] as number | undefined;
    return fid !== undefined ? `folder:${fid}` : '';
  }
  return '';
}

export function chatListOf(listKey: string): TdObject {
  if (listKey === 'archive') {
    return { '@type': 'chatListArchive' };
  }
  if (listKey.startsWith('folder:')) {
    const fid = Number.parseInt(listKey.substring(7), 10);
    const cl: TdObject = { '@type': 'chatListFolder' };
    cl['chat_folder_id'] = fid;
    return cl;
  }
  return { '@type': 'chatListMain' };
}
