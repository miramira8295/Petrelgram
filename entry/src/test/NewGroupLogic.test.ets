import { describe, it, expect } from '@ohos/hypium';
import { TdObject } from '../main/ets/tdkit/TdTypes';
import {
  maxSelectableBasicGroupMembers, newGroupCreationErrorText,
  newGroupCreationOutcomeUncertain, newGroupTitleError, parseNewBasicGroupResult
} from '../main/ets/util/newGroupLogic';

export default function newGroupLogicTest() {
  describe('NewGroupLogic', (): void => {
    it('parses_current_tdlib_result_and_failed_members', 0, (): void => {
      const firstFailure: TdObject = { 'user_id': 11, 'error': { '@type': 'error' } as TdObject };
      const duplicateFailure: TdObject = { 'user_id': 11 };
      const secondFailure: TdObject = { 'user_id': 22 };
      const failed: TdObject = {
        'failed_to_add_members': [firstFailure, duplicateFailure, secondFailure]
      };
      const result: TdObject = {
        '@type': 'createdBasicGroupChat',
        'chat_id': 987,
        'failed_to_add_members': failed
      };

      const parsed = parseNewBasicGroupResult(result);
      expect(parsed.chatId).assertEqual(987);
      expect(parsed.failedUserIds.length).assertEqual(2);
      expect(parsed.failedUserIds[0]).assertEqual(11);
      expect(parsed.failedUserIds[1]).assertEqual(22);
    });

    it('keeps_legacy_flattened_chat_id_compatible', 0, (): void => {
      const result: TdObject = { 'id': 123 };
      expect(parseNewBasicGroupResult(result).chatId).assertEqual(123);
    });

    it('validates_title_and_member_limit', 0, (): void => {
      expect(newGroupTitleError('   ')).assertEqual('new_group_name_required');
      expect(newGroupTitleError('测试群组')).assertEqual('');
      expect(newGroupTitleError('a'.repeat(129))).assertEqual('new_group_name_too_long');
      expect(maxSelectableBasicGroupMembers(200)).assertEqual(199);
      expect(maxSelectableBasicGroupMembers(0)).assertEqual(1);
    });

    it('maps_creation_errors_to_actionable_copy', 0, (): void => {
      expect(newGroupCreationErrorText('FLOOD_WAIT_20')).assertEqual('new_group_error_flood');
      expect(newGroupCreationErrorText('USERS_TOO_MUCH'))
        .assertEqual('new_group_error_too_many');
      expect(newGroupCreationErrorText('NETWORK_ERROR'))
        .assertEqual('new_group_error_network');
      expect(newGroupCreationOutcomeUncertain('request timeout')).assertTrue();
      expect(newGroupCreationOutcomeUncertain('NETWORK_ERROR')).assertFalse();
    });
  });
}
