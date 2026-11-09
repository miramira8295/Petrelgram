import { decimal } from './intlFormat';
import { str } from './strings';

// Human-readable byte size: 532 B / 24.3 KB / 1.2 MB / 3.4 GB.
//
// Split deliberately: the number goes through Intl (decimal separator varies —
// "1,2 MB" in German) while the unit is a resource string, so a translator can
// change the symbol or move it in front of the number without touching code.
export function formatFileSize(bytes: number): string {
  if (bytes <= 0) {
    return '';
  }
  if (bytes < 1024) {
    return str('size_bytes', `${bytes}`);
  }
  if (bytes < 1024 * 1024) {
    return str('size_kb', decimal(bytes / 1024, 1));
  }
  if (bytes < 1024 * 1024 * 1024) {
    return str('size_mb', decimal(bytes / (1024 * 1024), 1));
  }
  return str('size_gb', decimal(bytes / (1024 * 1024 * 1024), 1));
}
