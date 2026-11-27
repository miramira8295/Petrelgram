// Unicode 安全的头像首字符提取：
// 避免用 substring(0, 1) 把 emoji（UTF-16 代理对，如 🍊）拦腰截断成乱码 。
// 同时保留紧随其后的变体选择符（FE0F）、肤色修饰符与 ZWJ 连接序列。
export function avatarInitialOf(raw: string): string {
  const trimmed: string = raw.trim();
  if (trimmed === '') {
    return '?';
  }
  const len: number = trimmed.length;
  let end: number = 0;
  const firstCp: number = trimmed.codePointAt(0) ?? 0;
  end = firstCp > 0xFFFF ? 2 : 1;
  while (end < len) {
    const cp: number = trimmed.codePointAt(end) ?? 0;
    const step: number = cp > 0xFFFF ? 2 : 1;
    // 变体选择符 FE0E/FE0F、组合键帽 20E3、肤色修饰符 1F3FB..1F3FF
    if (cp === 0xFE0F || cp === 0xFE0E || cp === 0x20E3 || (cp >= 0x1F3FB && cp <= 0x1F3FF)) {
      end += step;
      continue;
    }
    // ZWJ 连接序列（如 👨‍👩‍👧）：连同后面的码点一并保留
    if (cp === 0x200D && end + 1 < len) {
      end += 1;
      const nextCp: number = trimmed.codePointAt(end) ?? 0;
      end += nextCp > 0xFFFF ? 2 : 1;
      continue;
    }
    // 区域指示符对（国旗 🇨🇳：两个 1F1E6..1F1FF 码点）
    if (firstCp >= 0x1F1E6 && firstCp <= 0x1F1FF && cp >= 0x1F1E6 && cp <= 0x1F1FF && end === 2) {
      end += step;
    }
    break;
  }
  const first: string = trimmed.substring(0, end);
  return firstCp > 0xFFFF ? first : first.toUpperCase();
}
