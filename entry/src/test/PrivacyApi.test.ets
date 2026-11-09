import { describe, expect, it } from '@ohos/hypium';
import { TdObject } from '../main/ets/tdkit/TdTypes';
import {
  RULE_CONTACTS, RULE_EVERYBODY, RULE_NOBODY,
  composePrivacyRules, parsePrivacyRules, ruleLabel
} from '../main/ets/store/PrivacyApi';

export default function privacyApiTest() {
  describe('PrivacyApi', (): void => {
    it('parses_contact_base_and_exception_counts', 0, (): void => {
      const rules: TdObject[] = [
        { '@type': 'userPrivacySettingRuleAllowUsers', 'user_ids': [1, 2] } as TdObject,
        { '@type': 'userPrivacySettingRuleRestrictChatMembers', 'chat_ids': [9] } as TdObject,
        { '@type': 'userPrivacySettingRuleAllowContacts' } as TdObject,
        { '@type': 'userPrivacySettingRuleRestrictAll' } as TdObject
      ];
      const value = parsePrivacyRules(rules);
      expect(value.base).assertEqual(RULE_CONTACTS);
      expect(value.allowExceptions).assertEqual(2);
      expect(value.restrictExceptions).assertEqual(1);
      expect(value.extra.length).assertEqual(2);
      expect(ruleLabel(value)).assertEqual('privacy_contacts · +2 / −1');
    });

    it('preserves_all_future_non_base_rules', 0, (): void => {
      const rules: TdObject[] = [
        { '@type': 'userPrivacySettingRuleAllowBots' } as TdObject,
        { '@type': 'userPrivacySettingRuleAllowPremiumUsers' } as TdObject,
        { '@type': 'userPrivacySettingRuleRestrictContacts' } as TdObject,
        { '@type': 'futurePrivacyRule', 'opaque': 'keep-me' } as TdObject,
        { '@type': 'userPrivacySettingRuleAllowAll' } as TdObject
      ];
      const parsed = parsePrivacyRules(rules);
      expect(parsed.base).assertEqual(RULE_EVERYBODY);
      expect(parsed.extra.length).assertEqual(4);
      const composed = composePrivacyRules(RULE_NOBODY, parsed.extra);
      expect(composed.length).assertEqual(5);
      expect(composed[0]['@type'] as string).assertEqual('userPrivacySettingRuleAllowBots');
      expect(composed[3]['opaque'] as string).assertEqual('keep-me');
      expect(composed[4]['@type'] as string).assertEqual('userPrivacySettingRuleRestrictAll');
    });

    it('removes_stale_base_rules_before_write', 0, (): void => {
      const preserved: TdObject[] = [
        { '@type': 'userPrivacySettingRuleAllowContacts' } as TdObject,
        { '@type': 'userPrivacySettingRuleRestrictAll' } as TdObject,
        { '@type': 'userPrivacySettingRuleAllowUsers', 'user_ids': [7] } as TdObject
      ];
      const composed = composePrivacyRules(RULE_EVERYBODY, preserved);
      expect(composed.length).assertEqual(2);
      expect(composed[0]['@type'] as string).assertEqual('userPrivacySettingRuleAllowUsers');
      expect(composed[1]['@type'] as string).assertEqual('userPrivacySettingRuleAllowAll');
    });
  });
}
