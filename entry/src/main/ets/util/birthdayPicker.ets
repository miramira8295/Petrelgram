// 生日选择器的初始日期。纯函数。
//
// 【为什么需要它】原来 DatePickerDialog 的 `selected` 是写死的 2000-01-01，
// 存过生日之后再点开，转盘还是停在 2000/01/01，用户以为没存上
// （用户 2026-09-08 实测）。
//
// 【为什么年份要单独兜底】TDLib 的 birthdate 里 **year 是可选的**——Telegram
// 允许只填月日不填年。缺年时若直接 `new Date(0, m-1, d)`，JS 会解释成 1900 年，
// 转盘一开就滚到最底下。所以缺年时用一个中性的占位年，和原来那个默认值一致。

// 缺年份时的占位年。取值本身无意义，只是要给 Date 一个年；界面上也不显示年。
export const BIRTHDAY_FALLBACK_YEAR: number = 2000;

// day / month 是 1 起的（TDLib 口径）。任一为 0（没存过生日）返回 null，
// 调用方据此退回自己的默认值。
export function birthdayPickerDate(day: number, month: number, year: number): Date | null {
  if (day <= 0 || month <= 0 || month > 12 || day > 31) {
    return null;
  }
  const y: number = year > 0 ? year : BIRTHDAY_FALLBACK_YEAR;
  return new Date(y, month - 1, day);
}
