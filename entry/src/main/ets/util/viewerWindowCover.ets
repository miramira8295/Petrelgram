// 媒体查看器占用整个窗口的跨组件标志（issue #139 / #201）。
//
// 查看器是 ChatPage 里的一个图层，分栏时 ChatPage 只占右栏。原来靠 bindContentCover
// 把它提成全模态盖住整个窗口，但**全模态里视频画面显示不出来**（#201：平板分栏看视频
// 黑屏，取消分栏就能播）。现在查看器始终留在页面内，打开时由会话页发布这个标志：
//   · ChatListPage 据此 hideNavBar——Split 模式下 hideNavBar(true) 的实际效果就是单栏，
//     右栏的 ChatPage 铺满整个导航容器；
//   · MainScreen 据此收起 dock，包括旋转期间的中间布局。
// 标志只代表查看器是否打开，不能与打开瞬间的分栏状态取交集：手机在竖屏打开
// 视频后转横屏，可能跨入大宽度分栏，但媒体目标不变，不会再次发布标志。
// ChatListPage 在消费端按当前断点决定是否 hideNavBar；查看器关闭/页面销毁撤回。
export const KEY_CHAT_VIEWER_COVERS_WINDOW: string = 'chatViewerCoversWindow';

// 同值 setOrCreate 也会惊动订阅方（见 CHAT_NAV_BAR_VISIBLE_KEY 的说明），先比一次。
export function publishViewerCoversWindow(covers: boolean): void {
  if (AppStorage.get<boolean>(KEY_CHAT_VIEWER_COVERS_WINDOW) !== covers) {
    AppStorage.setOrCreate<boolean>(KEY_CHAT_VIEWER_COVERS_WINDOW, covers);
  }
}
