// 直接展示完整的具体成员/订阅者数量，不做 K / M 缩写。
export function formatMemberCount(n: number): string {
  if (!Number.isFinite(n) || n <= 0) {
    return '0';
  }
  return `${Math.floor(n)}`;
}
