import { describe, expect, it } from '@ohos/hypium';
import { TdObject } from '../main/ets/tdkit/TdTypes';
import {
  GroupPermissions, MEDIA_PERMISSION_KEYS, PERM_SEND_MESSAGES, PERM_SEND_VOICE_NOTES,
  RESTRICT_DAY_SECONDS, allPermissions, clampToChatPermissions, defaultPermissions,
  mediaOnCount, permissionValue, permissionsFromTd, permissionsToTd,
  restrictUntilDate, withAllMedia, withPermission
} from '../main/ets/util/chatPermissions';

export default function chatPermissionsTest() {
  describe('chatPermissions', () => {
    it('每个 TDLib 标志都单独往返，不会被合并的媒体开关冲掉', 0, () => {
      const raw: TdObject = { '@type': 'chatPermissions' };
      raw['can_send_basic_messages'] = true;
      raw['can_send_photos'] = true;
      raw['can_send_voice_notes'] = false;
      raw['can_send_videos'] = true;
      const parsed: GroupPermissions = permissionsFromTd(raw);
      expect(parsed.sendPhotos).assertTrue();
      expect(parsed.sendVoiceNotes).assertFalse();
      const back = permissionsToTd(parsed);
      expect(back['can_send_photos'] as boolean).assertTrue();
      // 这一条是回归点：旧实现会把语音重新打开。
      expect(back['can_send_voice_notes'] as boolean).assertFalse();
    });

    it('读不到权限对象时退回默认集合', 0, () => {
      const p = permissionsFromTd(undefined);
      expect(p.sendMessages).assertTrue();
      expect(p.changeInfo).assertFalse();
    });

    it('withPermission 返回新对象，不改原来的', 0, () => {
      const base = defaultPermissions();
      const next = withPermission(base, PERM_SEND_MESSAGES, false);
      expect(base.sendMessages).assertTrue();
      expect(next.sendMessages).assertFalse();
      // 其余项原样带过去
      expect(next.inviteUsers).assertEqual(base.inviteUsers);
    });

    it('媒体计数就是子组里开着的项数', 0, () => {
      const all = allPermissions(true);
      expect(mediaOnCount(all)).assertEqual(MEDIA_PERMISSION_KEYS.length);
      const one = withPermission(all, PERM_SEND_VOICE_NOTES, false);
      expect(mediaOnCount(one)).assertEqual(MEDIA_PERMISSION_KEYS.length - 1);
      expect(mediaOnCount(withAllMedia(all, false))).assertEqual(0);
      // 媒体开关不该动到非媒体项
      expect(withAllMedia(all, false).sendMessages).assertTrue();
    });

    it('成员权限被群默认权限压住', 0, () => {
      const chat = withPermission(allPermissions(true), PERM_SEND_MESSAGES, false);
      const member = allPermissions(true);
      const clamped = clampToChatPermissions(member, chat);
      expect(permissionValue(clamped, PERM_SEND_MESSAGES)).assertFalse();
      expect(clamped.sendPhotos).assertTrue();
    });

    it('时限 0 是永久，其余是绝对时间戳', 0, () => {
      expect(restrictUntilDate(1000, 0)).assertEqual(0);
      expect(restrictUntilDate(1000, -5)).assertEqual(0);
      expect(restrictUntilDate(1000, RESTRICT_DAY_SECONDS)).assertEqual(1000 + RESTRICT_DAY_SECONDS);
    });
  });
}
