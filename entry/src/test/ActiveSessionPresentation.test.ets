import { describe, it, expect } from '@ohos/hypium';
import { TdObject } from '../main/ets/tdkit/TdTypes';
import {
  activeSessionError, freshSessionSeconds, inactiveSessionTtlLabel,
  sessionDeviceType, sessionWaitText
} from '../main/ets/util/ActiveSessionPresentation';

export default function activeSessionPresentationTest() {
  describe('ActiveSessionPresentation', () => {
    it('reads_official_device_type_and_legacy_fallback', 0, () => {
      const official: TdObject = {
        '@type': 'session',
        'device_type': { '@type': 'sessionDeviceTypeAndroid' } as TdObject
      };
      const legacy: TdObject = {
        '@type': 'session',
        'type': { '@type': 'sessionDeviceTypeDesktop' } as TdObject
      };
      expect(sessionDeviceType(official)).assertEqual('sessionDeviceTypeAndroid');
      expect(sessionDeviceType(legacy)).assertEqual('sessionDeviceTypeDesktop');
    });

    it('calculates_fresh_session_protection_and_wait_text', 0, () => {
      expect(freshSessionSeconds(100, 100)).assertEqual(86400);
      expect(freshSessionSeconds(100, 86500)).assertEqual(0);
      expect(sessionWaitText(3660)).assertEqual('session_wait_in_two(session_unit_hours(1,1),session_unit_minutes(1,1))');
      expect(sessionWaitText(60)).assertEqual('session_wait_in(session_unit_minutes(1,1))');
    });

    it('maps_server_errors_without_leaking_raw_text', 0, () => {
      expect(activeSessionError('FRESH_RESET_AUTHORISATION_FORBIDDEN').kind)
        .assertEqual('fresh');
      expect(activeSessionError('SESSION_NOT_FOUND').shouldRefresh).assertTrue();
      expect(activeSessionError('FLOOD_WAIT_65').text)
        .assertEqual('session_error_flood_minutes(2)');
      expect(activeSessionError('AUTH_TOKEN_EXPIRED').kind).assertEqual('qr');
    });

    it('keeps_nonstandard_server_ttl_visible', 0, () => {
      expect(inactiveSessionTtlLabel(30)).assertEqual('session_ttl_1_month');
      expect(inactiveSessionTtlLabel(60)).assertEqual('session_unit_days(60,60)');
      expect(inactiveSessionTtlLabel(366)).assertEqual('session_ttl_1_year');
    });
  });
}
