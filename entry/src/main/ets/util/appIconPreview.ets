// 预览图资源名 → Resource。
//
// **只能写成一串 if**：$r() 的参数必须是编译期字面量，拼不出
// `$r('app.media.' + name)`。util/appIcon 那张目录存的是名字（它要被单测读，
// 塞不进 Resource），所以名字翻成 Resource 这一步总得有个地方做。
//
// 单独成文件而不是留在 AppIconPicker 里：启动首帧（StartupSplash）也要画这些
// 图，两个调用方共用一份表，才不会出现"设置里加了一张、启动页还认不出"。
// 加图标时这里是四个必改点之一（另外三处：AppScope 的三个资源、app.json5 的
// alternateIcons、util/appIcon 的目录）。
export function previewResource(previewName: string): Resource {
  if (previewName === 'iconprev_frost') { return $r('app.media.iconprev_frost'); }
  if (previewName === 'iconprev_neon') { return $r('app.media.iconprev_neon'); }
  if (previewName === 'iconprev_aurora') { return $r('app.media.iconprev_aurora'); }
  if (previewName === 'iconprev_midnight') { return $r('app.media.iconprev_midnight'); }
  if (previewName === 'iconprev_graphite') { return $r('app.media.iconprev_graphite'); }
  if (previewName === 'iconprev_forest') { return $r('app.media.iconprev_forest'); }
  if (previewName === 'iconprev_sunset') { return $r('app.media.iconprev_sunset'); }
  if (previewName === 'iconprev_violet') { return $r('app.media.iconprev_violet'); }
  // 兜底给默认那张而不是空——名字对不上时给一张看得见的图，比给一个空洞更容易
  // 在开发期被发现，启动首帧也不会开天窗。
  return $r('app.media.iconprev_default');
}
