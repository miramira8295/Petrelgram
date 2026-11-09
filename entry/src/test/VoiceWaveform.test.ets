import { describe, it, expect } from '@ohos/hypium';
import {
  decodeVoiceWaveform,
  formatVoiceDuration,
  voiceWaveformBars
} from '../main/ets/util/voiceWaveform';

export default function voiceWaveformTest() {
  describe('VoiceWaveform', () => {
    it('decodes_tdlib_packed_five_bit_samples', 0, () => {
      const samples: number[] = decodeVoiceWaveform('//8=');
      expect(samples.length).assertEqual(3);
      expect(samples.join(',')).assertEqual('31,31,31');
    });
    it('resamples_to_stable_bounded_bar_heights', 0, () => {
      const bars: number[] = voiceWaveformBars('//8=', 12, 7);
      expect(bars.length).assertEqual(12);
      expect(bars.every((height: number): boolean => height >= 4 && height <= 20)).assertTrue();
      expect(voiceWaveformBars('', 12, 7).join(','))
        .assertEqual(voiceWaveformBars('', 12, 7).join(','));
    });
    it('formats_short_and_long_durations', 0, () => {
      expect(formatVoiceDuration(65)).assertEqual('1:05');
      expect(formatVoiceDuration(3661)).assertEqual('1:01:01');
      expect(formatVoiceDuration(-1)).assertEqual('—:—');
    });
  });
}
