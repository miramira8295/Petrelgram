import { showActionMenu, showDialog } from '../util/uiContext';
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest } from '../tdkit/TdTypes';
import { saveMediaToGallery } from '../util/mediaSaver';
import { str } from '../util/strings';

// Always fetch current story permissions before exposing destructive actions.
// The caller owns the page/account lifetime and the operation's busy gate.
export async function showProfileStoryActions(context: common.UIAbilityContext, client: TdClient,
  chatId: number, storyId: number, isCurrent: () => boolean,
  onView: () => void, onChanged: () => void): Promise<void> {
  const get: TdRequest = { '@type': 'getStory' };
  get['story_poster_chat_id'] = chatId;
  get['story_id'] = storyId;
  get['only_local'] = false;
  const story = await client.send(get);
  if (!isCurrent()) { return; }
  const actions: string[] = ['view', 'save'];
  const buttons: promptAction.Button[] = [
    { text: str('view'), color: '#3390EC' },
    { text: str('ms_save_to_gallery'), color: '#3390EC' }
  ];
  const posted = story['is_posted_to_chat_page'] === true;
  if (story['can_toggle_is_posted_to_chat_page'] === true) {
    actions.push('toggle');
    buttons.push({ text: str(posted ? 'mp_story_hide_profile' : 'mp_story_show_profile'), color: '#3390EC' });
  }
  if (story['can_be_deleted'] === true) {
    actions.push('delete');
    buttons.push({ text: str('mm_story_delete'), color: '#E64545' });
  }
  let index: number;
  try {
    index = (await showActionMenu({ buttons: buttons as [promptAction.Button,
      promptAction.Button?, promptAction.Button?, promptAction.Button?] })).index;
  } catch (_) { return; } // Dismissing the menu is not a request failure.
  if (!isCurrent()) { return; }
  const action = actions[index];
  if (action === 'view') { onView(); return; }
  if (action === 'save') {
    const content = story['content'] as TdObject | undefined;
    const isVideo = content?.['@type'] === 'storyContentVideo';
    let file: TdObject | undefined = undefined;
    if (isVideo) {
      const video = content?.['video'] as TdObject | undefined;
      file = video?.['video'] as TdObject | undefined;
    } else if (content?.['@type'] === 'storyContentPhoto') {
      const photo = content['photo'] as TdObject | undefined;
      const sizes = (photo?.['sizes'] as TdObject[] | undefined) ?? [];
      file = sizes.length > 0 ? sizes[sizes.length - 1]['photo'] as TdObject | undefined : undefined;
    }
    const fileId = (file?.['id'] as number | undefined) ?? 0;
    if (fileId <= 0) { throw new Error('Story media unavailable'); }
    let local = file?.['local'] as TdObject | undefined;
    let path = local?.['is_downloading_completed'] === true
      ? (local['path'] as string | undefined) ?? '' : '';
    if (path === '') {
      const download: TdRequest = { '@type': 'downloadFile' };
      download['file_id'] = fileId;
      download['priority'] = 32;
      download['synchronous'] = true;
      const result = await client.send(download);
      local = result['local'] as TdObject | undefined;
      path = local?.['is_downloading_completed'] === true
        ? (local['path'] as string | undefined) ?? '' : '';
    }
    if (!isCurrent()) { return; }
    if (path === '') { throw new Error('Story download incomplete'); }
    await saveMediaToGallery(context, path, isVideo);
    return;
  }
  if (action === 'delete') {
    let confirmed = false;
    try {
      const confirmation = await showDialog({
        title: str('mm_story_delete'), message: str('mp_story_delete_confirm'),
        buttons: [{ text: str('cancel'), color: '#3390EC' }, { text: str('delete'), color: '#E64545' }]
      });
      confirmed = confirmation.index === 1;
    } catch (_) { return; }
    if (!confirmed || !isCurrent()) { return; }
  } else if (action !== 'toggle') { return; }
  const request: TdRequest = { '@type': action === 'delete' ? 'deleteStory' : 'toggleStoryIsPostedToChatPage' };
  request['story_poster_chat_id'] = chatId;
  request['story_id'] = storyId;
  if (action === 'toggle') { request['is_posted_to_chat_page'] = !posted; }
  await client.send(request);
  if (isCurrent()) { onChanged(); }
}
