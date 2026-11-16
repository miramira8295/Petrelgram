import { formatFileSize } from '../../util/formatFileSize';
import { formatMediaDuration } from '../../util/mediaDuration';

// Computed values are recalculated on V2 reuse. Cache the formatted result,
// not just the Intl formatter. Numeric metadata is safe to share across rows;
// no message, component or player is retained. Average O(1) lookup/eviction,
// at most 128 labels, and a bounded clear when the language changes.
export class DrawnVideoMetaCache {
  private labels: Map<string, string> = new Map();
  private language: number = -1;

  prepare(bytes: number, seconds: number, wide: boolean, language: number): string {
    if (this.language !== language) {
      this.labels.clear(); this.language = language;
    }
    const key = `${bytes}:${seconds}:${wide}`;
    const cached = this.labels.get(key);
    if (cached !== undefined) {
      this.labels.delete(key); this.labels.set(key, cached);
      return cached;
    }
    const size = bytes > 0 ? formatFileSize(bytes) : '';
    const duration = seconds > 0 ? formatMediaDuration(seconds) : '';
    const label = duration !== '' && size !== '' && wide ? `${duration} · ${size}` : size || duration;
    // Commit only after successful formatting, so a failed request can retry.
    if (this.labels.size >= 128) {
      const oldest: string | undefined = this.labels.keys().next().value;
      if (oldest !== undefined) { this.labels.delete(oldest); }
    }
    this.labels.set(key, label);
    return label;
  }
}

export const drawnVideoMetaCache: DrawnVideoMetaCache = new DrawnVideoMetaCache();

// One numeric snapshot per physical video island. Reading an unchanged label
// does not create a key or touch the shared LRU, including after V2 reuse.
// No message, player, UI context or image is retained here.
export class DrawnVideoMetaMemo {
  private bytes: number = -1;
  private seconds: number = -1;
  private wide: boolean = false;
  private language: number = -1;
  private label: string = '';

  prepare(bytes: number, seconds: number, wide: boolean, language: number): string {
    if (this.bytes === bytes && this.seconds === seconds && this.wide === wide && this.language === language) {
      return this.label;
    }
    const label = drawnVideoMetaCache.prepare(bytes, seconds, wide, language);
    this.bytes = bytes; this.seconds = seconds; this.wide = wide; this.language = language;
    this.label = label;
    return label;
  }
}
