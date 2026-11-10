// 分享面板的 LocalStorage：**同一个实例**必须在两侧可见。
//
// 原来页面用 `LocalStorage.getShared()`（API 18 起废弃）拿应用级共享实例，
// 而分享 Ability 又自己 `new LocalStorage()` 再 loadContent 传过去——两条路
// 谁生效取决于 ArkUI 版本。这里收敛成一个模块单例：Ability 和页面 import
// 的是同一个对象，@Entry(shareStorage) 与 loadContent(…, shareStorage) 一致。


export const shareStorage: LocalStorage = new LocalStorage();
