import { TdObject } from '../tdkit/TdTypes';

// Empty names also occur before user metadata arrives; only TDLib's explicit
// type is authoritative. Never infer deletion from a missing title/photo.
export function isDeletedUser(user: TdObject | undefined): boolean {
  return (user?.['type'] as TdObject | undefined)?.['@type'] === 'userTypeDeleted';
}
