// 本机自选壁纸：用户从相册挑一张图当聊天背景，**只存在这台设备上**。
//
// 【为什么不走 TDLib】setChatBackground / setDefaultBackground 的
// inputBackgroundLocal 会把这张图**上传到 Telegram 服务器**并同步到所有设备和
// 官方客户端。那是另一件事（也是另一个隐私决定）。这里选的是本地方案：图片
// 拷进应用沙箱，路径记在设置里，一个字节都不出这台机器。代价是不跨设备同步。
//
// 【优先级】会话自己的背景 > 本地壁纸 > 账号默认背景 > 内置底色。
// 本地壁纸压过账号默认，是因为它是用户**在这台设备上明确挑的**，而账号默认多半
// 是服务端下发或从别的端同步过来的；但让位于会话自己的背景——更具体的意图应该
// 压过更笼统的。

// 深浅色各存一张：既有的 ChatBackgroundPage 本来就带 forDark 开关，服务端背景
// 也是分两套存的，本地这套跟着同一套心智，免得用户在深色下换了图、回到浅色发现
// 也跟着变了。
export function localWallpaperFileName(forDark: boolean, stamp: number): string {
  const safe: number = Number.isFinite(stamp) && stamp > 0 ? Math.floor(stamp) : 0;
  return `local_bg_${forDark ? 'dark' : 'light'}_${safe}.jpg`;
}

// 文件名带时间戳，而不是固定一个名字覆盖写。
//
// 固定名会撞上图片缓存：ArkUI 的 Image 按路径缓存解码结果，换了图但路径没变，
// 屏幕上还是旧图，要杀进程才更新。带时间戳等于每次换图都是一个新路径，缓存天然
// 失效；代价是换图时要**自己把上一张删掉**，否则沙箱里会堆一地废图。
export function isLocalWallpaperFile(name: string): boolean {
  return name.startsWith('local_bg_light_') || name.startsWith('local_bg_dark_');
}

// 本地壁纸该不该盖过账号默认背景。
//
// hasChatSpecific：这个会话有没有自己的背景（服务端下发的 chat.background）。
export function localWallpaperWins(hasChatSpecific: boolean, localPath: string): boolean {
  return !hasChatSpecific && localPath !== '';
}

// APP 背景图（主界面壁纸）的文件名。与聊天壁纸分开命名，两者互不覆盖。
export function appWallpaperFileName(forDark: boolean, stamp: number): string {
  const safe: number = Number.isFinite(stamp) && stamp > 0 ? Math.floor(stamp) : 0;
  return `app_bg_${forDark ? 'dark' : 'light'}_${safe}.jpg`;
}

// APP 壁纸此刻生不生效。
//
// stateRaw：APP 槽位里存的**序列化 ChatBackgroundState**（'' = 没设）。存状态而
// 不是裸路径，是为了让原生壁纸（渐变/图案）也能给 APP 背景用——见
// pages/common/AppBackdrop。
// split：是不是分栏（平板/折叠屏展开）。**分栏下不提供这个功能**——右栏被聊天
// 壁纸盖住，这张图只能从左栏那一条窄缝里露出来，既不好看也没意义；设置项在分栏
// 下也一并藏掉，免得给一个看不出效果的开关。
export function appWallpaperActive(stateRaw: string, split: boolean): boolean {
  return stateRaw !== '' && !split;
}
