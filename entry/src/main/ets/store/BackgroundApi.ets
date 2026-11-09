import { getTdClient } from '../tdkit/Globals';
import { TdObject, TdRequest } from '../tdkit/TdTypes';

// Chat wallpapers stay entirely inside TDLib: the official gallery comes from
// getBackgrounds, and applying one syncs across the account's devices. The
// chat page re-renders through its updateDefaultBackground subscription.

export async function listBackgrounds(forDarkTheme: boolean): Promise<TdObject[]> {
  // TDLib 1.8.14+ renamed getBackgrounds — the old name is gone in 1.8.65.
  const request: TdRequest = { '@type': 'getInstalledBackgrounds' };
  request['for_dark_theme'] = forDarkTheme;
  const result = await getTdClient().send(request, 15000);
  return ((result['backgrounds'] as TdObject[] | undefined) ?? []).slice();
}

// Applies a gallery background as the account-wide default for one theme.
// The background's own type object is reused so pattern intensity and fill
// rotation survive the round trip.
export async function applyRemoteBackground(
  background: TdObject, forDarkTheme: boolean
): Promise<void> {
  const remote: TdObject = { '@type': 'inputBackgroundRemote' };
  remote['background_id'] = (background['id'] as string | number | undefined) ?? '';
  const request: TdRequest = { '@type': 'setDefaultBackground' };
  request['background'] = remote;
  request['type'] = (background['type'] as TdObject | undefined) ?? { '@type': 'backgroundTypeFill' } as TdObject;
  request['for_dark_theme'] = forDarkTheme;
  await getTdClient().send(request, 20000);
}

export async function resetDefaultBackground(forDarkTheme: boolean): Promise<void> {
  const request: TdRequest = { '@type': 'deleteDefaultBackground' };
  request['for_dark_theme'] = forDarkTheme;
  await getTdClient().send(request, 15000);
}

// Downloads a (small) file synchronously and resolves to its local path, or ''
// when TDLib finishes without a usable path.
export async function downloadFileToPath(fileId: number): Promise<string> {
  if (fileId <= 0) { return ''; }
  const request: TdRequest = { '@type': 'downloadFile' };
  request['file_id'] = fileId;
  request['priority'] = 8;
  request['offset'] = 0;
  request['limit'] = 0;
  request['synchronous'] = true;
  const file = await getTdClient().send(request, 30000);
  const local = (file['local'] as TdObject | undefined) ?? {} as TdObject;
  return ((local['is_downloading_completed'] as boolean | undefined) ?? false)
    ? ((local['path'] as string | undefined) ?? '') : '';
}

// Applies a gallery background to ONE chat instead of the account default.
// only_for_self keeps the peer's view unchanged (mirrors官方 default choice).
export async function applyChatBackground(
  chatId: number, background: TdObject, onlyForSelf: boolean
): Promise<void> {
  const remote: TdObject = { '@type': 'inputBackgroundRemote' };
  remote['background_id'] = (background['id'] as string | number | undefined) ?? '';
  const request: TdRequest = { '@type': 'setChatBackground' };
  request['chat_id'] = chatId;
  request['background'] = remote;
  request['type'] = (background['type'] as TdObject | undefined) ?? { '@type': 'backgroundTypeFill' } as TdObject;
  request['dark_theme_dimming'] = 0;
  request['only_for_self'] = onlyForSelf;
  await getTdClient().send(request, 20000);
}

// Removes this chat's dedicated background so the account default shows again.
export async function clearChatBackground(chatId: number): Promise<void> {
  const request: TdRequest = { '@type': 'deleteChatBackground' };
  request['chat_id'] = chatId;
  request['restore_previous'] = false;
  await getTdClient().send(request, 15000);
}

// 纯色背景（backgroundTypeFill + backgroundFillSolid）。TDLib 的 background 参数传
// null 就是"新建一个填充背景"，和图库背景一样同步到账号的其它设备，回流也走同一条
// updateDefaultBackground / updateChatBackground。color 是 24 位 RGB 整数。
function solidFillType(color: number): TdObject {
  const fill: TdObject = { '@type': 'backgroundFillSolid' };
  fill['color'] = color;
  const type: TdObject = { '@type': 'backgroundTypeFill' };
  type['fill'] = fill;
  return type;
}

export async function applySolidDefaultBackground(color: number, forDarkTheme: boolean): Promise<void> {
  const request: TdRequest = { '@type': 'setDefaultBackground' };
  request['type'] = solidFillType(color);
  request['for_dark_theme'] = forDarkTheme;
  await getTdClient().send(request, 20000);
}

export async function applySolidChatBackground(chatId: number, color: number): Promise<void> {
  const request: TdRequest = { '@type': 'setChatBackground' };
  request['chat_id'] = chatId;
  request['type'] = solidFillType(color);
  request['dark_theme_dimming'] = 0;
  request['only_for_self'] = true;
  await getTdClient().send(request, 20000);
}
