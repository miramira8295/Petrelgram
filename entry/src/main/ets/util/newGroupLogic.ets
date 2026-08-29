import { requestOutcomeUncertain } from './tdRequestTimeout';
import { TdObject } from '../tdkit/TdTypes';
import { str } from './strings';

export interface NewBasicGroupResult {
  chatId: number;
  failedUserIds: number[];
}

export function parseNewBasicGroupResult(result: TdObject): NewBasicGroupResult {
  // Current TDLib returns createdBasicGroupChat rather than chat. Keep the
  // legacy `id` fallback for older native bridges that flattened the result.
  const chatId = (result['chat_id'] as number | undefined) ??
    ((result['id'] as number | undefined) ?? 0);
  const failed = result['failed_to_add_members'] as TdObject | undefined;
  const entries = failed !== undefined
    ? ((failed['failed_to_add_members'] as TdObject[] | undefined) ?? []) : [];
  const failedUserIds: number[] = [];
  for (const entry of entries) {
    const userId = (entry['user_id'] as number | undefined) ?? 0;
    if (userId > 0 && failedUserIds.indexOf(userId) < 0) {
      failedUserIds.push(userId);
    }
  }
  return { chatId, failedUserIds };
}

export function newGroupTitleError(rawTitle: string): string {
  const title = rawTitle.trim();
  if (title === '') { return str('new_group_name_required'); }
  if (title.length > 128) { return str('new_group_name_too_long'); }
  return '';
}

export function maxSelectableBasicGroupMembers(groupSizeMax: number): number {
  // The current account is also a group member, while user_ids only contains
  // the other people selected on this page.
  return Math.max(1, groupSizeMax - 1);
}

export function newGroupCreationOutcomeUncertain(rawMessage: string): boolean {
  // TdClient stops waiting after its local timeout, but TDLib may still have
  // accepted the mutating request. Retrying Create in that state can produce
  // a duplicate group.
  return requestOutcomeUncertain(rawMessage);
}

export function newGroupCreationErrorText(rawMessage: string): string {
  const message = rawMessage.toUpperCase();
  if (message.indexOf('FLOOD_WAIT') >= 0 || message.indexOf('TOO_MANY_REQUESTS') >= 0) {
    return str('new_group_error_flood');
  }
  if (message.indexOf('USERS_TOO_MUCH') >= 0 || message.indexOf('GROUP_TOO_LARGE') >= 0) {
    return str('new_group_error_too_many');
  }
  if (message.indexOf('USER_PRIVACY_RESTRICTED') >= 0) {
    return str('new_group_error_privacy');
  }
  if (message.indexOf('CHAT_TITLE_EMPTY') >= 0 || message.indexOf('TITLE_INVALID') >= 0) {
    return str('new_group_error_bad_name');
  }
  if (message.indexOf('NETWORK') >= 0 || message.indexOf('TIMEOUT') >= 0 ||
    message.indexOf('CONNECTION') >= 0) {
    return str('new_group_error_network');
  }
  return str('new_group_error_generic');
}
