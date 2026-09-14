import { router } from '@kit.ArkUI';
import { logW } from '../../util/log';

// 登录前的代理设置外壳。
//
// 【为什么需要一个外壳】ProxyPage 迁成了 NavDestination（根节点是
// HdsSubDestination），必须挂在某个 Navigation 里才渲染得出来；而登录阶段
// MainScreen 根本没建，设置页签的那个 HdsNavigation 不存在。原来登录页那句
// `router.pushUrl('pages/main/ProxyPage')` 在页面从 main_pages.json 摘出之后
// **必然失败**——需要代理才能连上服务器的用户，卡在登录页没有出路
// （2026-09-14 与"点通知提示无法识别的链接"同一批查出来的，见 util/pendingNav）。
//
// 这里只做一件事：起一个空的 Navigation，把 ProxyPage 作为目的地推进去
// （目的地名由 router_map.json 解析，不需要本地 builder）。用户返回时栈空了，
// 连整页一起退掉，回到登录页。
@Entry
@Component
struct LoginProxyPage {
  private stack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    // 目的地被弹掉（点标题栏的返回箭头，或系统返回键）之后栈就空了，空的
    // Navigation 是一片白——拦截到"要回 navBar 了"就连整页一起退掉。
    // 只有这一条能覆盖标题栏那个箭头：它走的是 HdsSubDestination.popSelf()，
    // 页面的 onBackPress 根本收不到。
    this.stack.setInterception({
      willShow: (_from: NavDestinationContext | NavBar, to: NavDestinationContext | NavBar,
        _operation: NavigationOperation, _animated: boolean): void => {
        if (typeof to === 'string' && to === 'navBar') {
          router.back();
        }
      }
    });
    this.stack.pushPath({ name: 'ProxyPage' });
  }

  build() {
    Navigation(this.stack) {
      // navBar 是空的：这一页的全部内容就是被推进去的那个目的地。
    }
    .hideNavBar(true)
    .mode(NavigationMode.Stack)
    .width('100%').height('100%')
    .onNavigationModeChange((mode: NavigationMode): void => {
      logW(`[LoginProxy] navigation mode ${mode}`);
    });
  }

  // 目的地被弹掉之后栈就空了，空的 Navigation 是一片白。系统返回键先走
  // NavDestination 自己的处理；处理完它已经出栈，这时这一层才收到，把整页退掉。
  onBackPress(): boolean {
    if (this.stack.size() > 0) {
      return false;   // 还有目的地在，交给它自己处理
    }
    router.back();
    return true;
  }
}
