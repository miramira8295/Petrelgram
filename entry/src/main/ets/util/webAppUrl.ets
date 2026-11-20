// 从 TDLib 的小程序应答里取网址。
//
// 【真机实测，别信文档】随包的 TDLib 里 mainWebApp.url **不是字符串**，而是一个对象：
//   {"@type": …, "url": "https://…", "require_same_origin": …}
// （[MainApp] 探针 2026-09-24：urlType=object urlKeys=[@type,url,require_same_origin]）。
// 原来当字符串直接用，一调 substring/trim 就抛 `undefined is not callable`——机器人资料页
// 的「打开应用」和 t.me 的主小程序链接都因此点了没反应。
// 同一批接口（openWebApp / getWebAppLinkUrl / 菜单按钮）的 url 字段可能也一样换了形状，
// 所以统一走这里：字符串和对象两种都认，拿不到就给 ''，由调用方提示「打不开」。
// 【真机实测】有的机器人「菜单按钮」url 带 menu:// 前缀：
//   实测值 menu://https://ncloudbot-vip.216.158.228.201.sslip.io/hj2/
// （海角资源库 2026-11-20，日志 openBotMiniApp url="menu://https://…"）。
// 带前缀时 miniAppOrigin 认不出 https 开头，直接判非法，点小程序只会看到
// 「无法打开 Mini App」。这里统一剥掉 https:// 之前的那层伪协议。
export function miniAppUrlOf(value: Object | undefined | null): string {
  const raw: string = webAppUrlOf(value);
  const at: number = raw.indexOf('https://');
  if (at <= 0) { return raw; }
  const prefix: string = raw.substring(0, at);
  return /^[A-Za-z0-9.+-]+:\/\/$/.test(prefix) ? raw.substring(at) : raw;
}

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
