// 从 TDLib 的小程序应答里取网址。
//
// 【真机实测，别信文档】随包的 TDLib 里 mainWebApp.url **不是字符串**，而是一个对象：
//   {"@type": …, "url": "https://…", "require_same_origin": …}
// （[MainApp] 探针 2026-09-24：urlType=object urlKeys=[@type,url,require_same_origin]）。
// 原来当字符串直接用，一调 substring/trim 就抛 `undefined is not callable`——机器人资料页
// 的「打开应用」和 t.me 的主小程序链接都因此点了没反应。
// 同一批接口（openWebApp / getWebAppLinkUrl / 菜单按钮）的 url 字段可能也一样换了形状，
// 所以统一走这里：字符串和对象两种都认，拿不到就给 ''，由调用方提示「打不开」。
export function webAppUrlOf(value: Object | undefined | null): string {
  if (value === undefined || value === null) {
    return '';
  }
  if (typeof value === 'string') {
    return value as string;
  }
  if (typeof value === 'object') {
    const inner: Object | undefined = (value as Record<string, Object>)['url'];
    return typeof inner === 'string' ? inner as string : '';
  }
  return '';
}
