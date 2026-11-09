import { getTdClient } from '../tdkit/Globals';
import { TdObject, TdRequest } from '../tdkit/TdTypes';

// Account-wide notification defaults, per scope (private / group / channel).
// Per-chat overrides keep using setChatNotificationSettings elsewhere.

export const SCOPE_PRIVATE: string = 'private';
export const SCOPE_GROUP: string = 'group';
export const SCOPE_CHANNEL: string = 'channel';

export interface ScopeSettings {
  muted: boolean;
  showPreview: boolean;
  disablePinned: boolean;
  disableMentions: boolean;
}

function scopeObject(scope: string): TdObject {
  const name = scope === SCOPE_GROUP ? 'notificationSettingsScopeGroupChats'
    : (scope === SCOPE_CHANNEL ? 'notificationSettingsScopeChannelChats'
      : 'notificationSettingsScopePrivateChats');
  return { '@type': name } as TdObject;
}

export function defaultScopeSettings(): ScopeSettings {
  return { muted: false, showPreview: true, disablePinned: false, disableMentions: false };
}

export async function getScopeSettings(scope: string): Promise<ScopeSettings> {
  const request: TdRequest = { '@type': 'getScopeNotificationSettings' };
  request['scope'] = scopeObject(scope);
  const result = await getTdClient().send(request, 12000);
  return {
    muted: ((result['mute_for'] as number | undefined) ?? 0) > 0,
    showPreview: (result['show_preview'] as boolean | undefined) ?? true,
    disablePinned: (result['disable_pinned_message_notifications'] as boolean | undefined) ?? false,
    disableMentions: (result['disable_mention_notifications'] as boolean | undefined) ?? false
  };
}

export async function setScopeSettings(scope: string, value: ScopeSettings): Promise<void> {
  const settings: TdObject = { '@type': 'scopeNotificationSettings' };
  settings['mute_for'] = value.muted ? 2147483647 : 0;
  settings['sound_id'] = '0';
  settings['show_preview'] = value.showPreview;
  settings['use_default_mute_stories'] = true;
  settings['mute_stories'] = false;
  settings['story_sound_id'] = '0';
  settings['show_story_poster'] = true;
  settings['disable_pinned_message_notifications'] = value.disablePinned;
  settings['disable_mention_notifications'] = value.disableMentions;
  const request: TdRequest = { '@type': 'setScopeNotificationSettings' };
  request['scope'] = scopeObject(scope);
  request['notification_settings'] = settings;
  await getTdClient().send(request, 12000);
}

export async function resetAllNotificationSettings(): Promise<void> {
  await getTdClient().send({ '@type': 'resetAllNotificationSettings' } as TdRequest, 12000);
}
