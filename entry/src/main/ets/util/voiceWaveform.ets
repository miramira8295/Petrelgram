const BASE64_ALPHABET: string =
  'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

function decodeBase64Bytes(encoded: string): number[] {
  const bytes: number[] = [];
  let value: number = 0;
  let bitCount: number = 0;
  for (let i: number = 0; i < encoded.length; i++) {
    const code: number = BASE64_ALPHABET.indexOf(encoded.charAt(i));
    if (code < 0) {
      continue;
    }
    value = (value << 6) | code;
    bitCount += 6;
    if (bitCount >= 8) {
      bitCount -= 8;
      bytes.push((value >> bitCount) & 0xFF);
      // Only the unconsumed low bits are needed by the next base64 digit.
      value &= (1 << bitCount) - 1;
    }
  }
  return bytes;
}

// TDLib exposes Telegram voice waveforms as base64-wrapped packed 5-bit
// amplitudes. Values are little-endian within the decoded byte stream.
export function decodeVoiceWaveform(encoded: string): number[] {
  const bytes: number[] = decodeBase64Bytes(encoded.trim());
  const samples: number[] = [];
  let packed: number = 0;
  let bitCount: number = 0;
  for (const byte of bytes) {
    packed |= byte << bitCount;
    bitCount += 8;
    while (bitCount >= 5) {
      samples.push(packed & 0x1F);
      packed >>= 5;
      bitCount -= 5;
    }
  }
  return samples;
}

function fallbackAmplitude(index: number, seed: number): number {
  // A stable fallback is preferable to a flat placeholder when old/locally
  // recorded notes have no server waveform yet.
  const mixed: number = Math.abs((seed % 997) * 17 + index * 29 + (index % 5) * 13);
  return 5 + (mixed % 24);
}

// Resample the packed waveform to a fixed number of bars and return bar heights
// in vp. Keeping a stable width prevents a download/content update from
// resizing the message row and moving the scroll position.
export function voiceWaveformBars(encoded: string, count: number, seed: number = 0): number[] {
  const safeCount: number = Math.max(1, Math.floor(count));
  const samples: number[] = decodeVoiceWaveform(encoded);
  const bars: number[] = [];
  if (samples.length === 0) {
    for (let i: number = 0; i < safeCount; i++) {
      const amplitude: number = fallbackAmplitude(i, seed);
      bars.push(4 + Math.round((amplitude / 31) * 16));
    }
    return bars;
  }
  for (let i: number = 0; i < safeCount; i++) {
    const start: number = Math.floor((i * samples.length) / safeCount);
    const end: number = Math.max(start + 1,
      Math.floor(((i + 1) * samples.length) / safeCount));
    let peak: number = 0;
    for (let j: number = start; j < end && j < samples.length; j++) {
      peak = Math.max(peak, samples[j]);
    }
    bars.push(4 + Math.round((peak / 31) * 16));
  }
  return bars;
}

export function formatVoiceDuration(totalSeconds: number): string {
  if (totalSeconds < 0 || !Number.isFinite(totalSeconds)) {
    return '—:—';
  }
  const rounded: number = Math.max(0, Math.floor(totalSeconds));
  const hours: number = Math.floor(rounded / 3600);
  const minutes: number = Math.floor((rounded % 3600) / 60);
  const seconds: number = rounded % 60;
  const secondText: string = `${seconds}`.padStart(2, '0');
  if (hours > 0) {
    return `${hours}:${`${minutes}`.padStart(2, '0')}:${secondText}`;
  }
  return `${minutes}:${secondText}`;
}
