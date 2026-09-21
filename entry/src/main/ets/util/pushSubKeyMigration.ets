// 华为通道的 subKey 从「借用 MeoW 那把」改成「自己存一把」时，该不该沿用旧的。
//
// 【为什么要分开 —— 2026-09-21 从中转库里查出来的】
// HmsRelayRegistration 一直调 `getOrCreateMeowSubKey()`，两条通道共用同一把
// subKey，而这把 key 的生命周期归 MeoW 管，有两处会清空它：
//   · MeoW 注销（MeowPushRegistration 末尾一次性清 subKey/secret/昵称/三元组）
//   · 「secret 丢失」自愈（issue #60/#39，故意换新 key 重来）
// 两处都不知道 HMS 也在用。于是每清一次，中转上那条 hms 订阅就成孤儿，下次注册
// 再建一条。中转实测：全部 hms 订阅只属于个位数台设备，其中一台重复注册了 19 次
// ——订阅数是设备数的五倍多。而 hms 订阅**没有任何删除路径**
// （deleteRelaySubscription 要 secret，HMS 注册根本不发 secret），只能一直堆着。
//
// 【迁移为什么不能简单地"生成一把新的"】
// 老用户此刻可能已经有一条能用的 hms 订阅，而 Telegram 服务端记着的正是那条的
// endpoint。如果升级后直接换新 subKey，中转上会多一条新订阅，**而 Telegram 仍然
// 往旧的推**——旧订阅还在（没人删得掉）所以推送照常，但从此两边永远对不上，
// 下次真要换 token 时就查不清了。所以已经注册过的，必须把旧 key 原样接过来。
//
// 【判据为什么是"HMS 注册过"而不是"有 meowSubKey"】只用过 MeoW 的人也有
// meowSubKey，把它接过来等于又把两条通道绑回一起，这次改动就白做了。
// 「注册过」看的是 HmsRelayRegistration 成功落盘的那两样（token + endpoint）——
// 它们只在完整注册成功后才写（见该文件 setString 那一段）。

// 返回本次该用的 hms subKey；空串表示"没有可沿用的，去生成一把新的"。
export function hmsSubKeyToAdopt(
  storedHmsSubKey: string, legacyMeowSubKey: string, hmsAlreadyRegistered: boolean
): string {
  const own: string = storedHmsSubKey.trim();
  if (own !== '') {
    return own;
  }
  const legacy: string = legacyMeowSubKey.trim();
  return hmsAlreadyRegistered && legacy !== '' ? legacy : '';
}
