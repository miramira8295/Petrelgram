import { describe, it, expect } from '@ohos/hypium';
import {
  callPhaseLabel, callDurationLabel, callEndLabel
} from '../main/ets/util/callPresentation';

export default function callPresentationTest() {
  describe('CallPresentation', () => {
    it('phase_labels', 0, () => {
      expect(callPhaseLabel('dialing', false)).assertEqual('call_state_dialing');
      expect(callPhaseLabel('ringing', false)).assertEqual('call_state_incoming_voice');
      expect(callPhaseLabel('ringing', true)).assertEqual('call_state_incoming_video');
      expect(callPhaseLabel('connecting', false)).assertEqual('call_state_connecting');
      expect(callPhaseLabel('active', false)).assertEqual('');
      expect(callPhaseLabel('idle', false)).assertEqual('');
    });
    it('duration_formats_h_m_s', 0, () => {
      expect(callDurationLabel(1000, 1000)).assertEqual('0:00');
      expect(callDurationLabel(1000, 62000)).assertEqual('1:01');
      expect(callDurationLabel(1000, 3662000)).assertEqual('1:01:01');
      // 未接通（startedAtMs=0）不显示计时。
      expect(callDurationLabel(0, 5000)).assertEqual('');
    });
    it('end_labels', 0, () => {
      expect(callEndLabel('hangup', '')).assertEqual('call_ended_normal');
      expect(callEndLabel('declined', '')).assertEqual('call_ended_declined');
      expect(callEndLabel('missed', '')).assertEqual('call_ended_missed');
      expect(callEndLabel('busy', '')).assertEqual('call_ended_busy');
      expect(callEndLabel('error', '连接失败')).assertEqual('连接失败');
      expect(callEndLabel('error', '')).assertEqual('call_ended_failed');
    });
  });
}
