import { router } from '@kit.ArkUI';
import { NavStackLike, snapshotOf, stackOf, TabKind } from './navStacks';
import { decidePush, PushOrigin, StackAction, StackFrame } from './splitRouting';
import { CHAT_TAB_INDEX, KEY_MAIN_TAB } from './chatNav';
import { logE } from './log';

// 聊天页签栈里**除会话详情之外**的目的地漏斗：用户资料页、群/频道资料页、
// 话题列表、归档列表。会话详情自己有 chatNav.ets，形状与本文件一致。
//
// 文件名按计划叫 profileNav，但住进来的不止两张资料页——话题列表和归档列表
// 是同一个形状（推进聊天页签的栈、要不要清栈由 origin 决定），各自单开一个
// 文件只会把「这条规则写在哪」这个问题变成四份。真正需要写对一次的东西是
// pushInto() 那十几行，它们在这里只有一份。
//
// 为什么要漏斗：这四个页面从 main_pages.json 摘出去之后，任何直连
// router.pushUrl 都会跳不动（页面不再是 router 页），而调用点散在
// ChatPage(4)、openTelegramLink(5)、ChatProfilePage(1)、ChatRow(1)、
// MainTabBody(1) 共十二处。
export const PROFILE_PAGE_URL: string = 'pages/profile/ProfilePage';
export const PROFILE_DEST_NAME: string = 'ProfilePage';
export const CHAT_PROFILE_PAGE_URL: string = 'pages/profile/ChatProfilePage';
export const CHAT_PROFILE_DEST_NAME: string = 'ChatProfilePage';
export const FORUM_TOPICS_PAGE_URL: string = 'pages/chat/ForumTopicsPage';
export const FORUM_TOPICS_DEST_NAME: string = 'ForumTopicsPage';
export const DIRECT_MESSAGES_TOPICS_PAGE_URL: string = 'pages/chat/DirectMessagesTopicsPage';
export const DIRECT_MESSAGES_TOPICS_DEST_NAME: string = 'DirectMessagesTopicsPage';
export const ARCHIVE_PAGE_URL: string = 'pages/chatlist/ArchivePage';
export const ARCHIVE_DEST_NAME: string = 'ArchivePage';

// 栈里一层的实例键。同一个 name 下，不同用户/不同会话是不同实例——decidePush
// 只比栈顶，键相同才算「已经打开」。归档页没有参数，键恒为空串，这正确：
// 全应用只有一个归档列表。
//
// 注意这个 keyOf 会被 snapshotOf 套在栈里**每一层**上，包括 ChatPage。
// ChatPage 的 param 里也有 chatId，于是会算出与 ChatProfilePage 相同的键——
// 但 decidePush 比的是 (name, key) 二元组，name 不同就不会误判成同一层。
export function profileFrameKey(name: string, param: Object | undefined): string {
  if (param === undefined || param === null) {
    return '';
  }
  const bag = param as Record<string, Object>;
  const userId = bag['userId'] as number | undefined;
  if (userId !== undefined) {
    return `u${userId}`;
  }
  const chatId = bag['chatId'] as number | undefined;
  if (chatId !== undefined) {
    return `c${chatId}`;
  }
  return '';
}

// MainScreen.build() 里 TabContent 的顺序：ChatListPage / ContactsPage /
// SettingsPage / MyProfilePage。
export const CONTACTS_TAB_INDEX: number = 1;

// 目标页签对应的 TabContent 下标。只列本文件真会推的两个：'settings' /
// 'profile' 落到这里是调用错误（那两条栈里没有资料页这类目的地），归到聊天页签
// 也无从补救，所以不为它们单开一支——settingsNav.ets 和 MyProfilePage.pushEditor
// 才是那两条线各自的漏斗。
function tabIndexOf(tab: TabKind): number {
  return tab === 'contacts' ? CONTACTS_TAB_INDEX : CHAT_TAB_INDEX;
}

// 推一个目的地进**指定页签**的栈。四个 navigateToXxx 的公共体。
//
// tab 曾经硬编码成 'chat'。联系人页签自己也成了路由容器之后，平板上「点一个
// 联系人」要把资料页开在联系人页签的右栏里，而不是切到聊天页签去——同一个
// 目的地、同一套去重规则，只是落在哪个栈上不同，所以是加参数而不是抄一份。
function pushInto(destName: string, fallbackUrl: string,
    params: Record<string, Object> | undefined, origin: PushOrigin, tab: TabKind): void {
  const stack: NavStackLike | undefined = stackOf(tab);
  if (stack === undefined) {
    // 栈还没注册（冷启动早期，ChatListPage 尚未挂树）时的回退。这四个页面
    // 已从 main_pages.json 摘出，整页路由多半也跳不动——保留这一支不是指望它
    // 成功，而是不让失败变成静默无操作：日志里能看见。
    router.pushUrl({ url: fallbackUrl, params: params }).catch((e: Error): void => {
      logE(`profileNav fallback pushUrl ${fallbackUrl} failed: ${e.message}`);
    });
    return;
  }
  // 与 navigateToChat 同理：推进去的是目标页签的栈，页签不对的话页面就在
  // 屏幕外。深链（openTelegramLink）可以在设置/联系人页签上被触发。
  // tab === 'contacts' 时这一句通常是同值写入（用户此刻就在联系人页签上），
  // 无害：MainScreen 的 @Watch 里有 tab !== appliedTab 的守卫。
  AppStorage.setOrCreate<number>(KEY_MAIN_TAB, tabIndexOf(tab));
  const target: StackFrame = { name: destName, key: profileFrameKey(destName, params) };
  const snap: StackFrame[] = snapshotOf(stack, profileFrameKey);
  const action: StackAction = decidePush(snap, origin, target);
  if (action === 'skip') {
    return;
  }
  if (action === 'clearAndPush') {
    stack.clear(false);
  }
  stack.pushPath({ name: destName, param: params });
}

// 用户资料页。**不返回 Promise、也不 reject**——与 navigateToChat 不同。
// navigateToChat 之所以要 reject，是因为 NewGroupPage 建完群要靠那个 rejection
// 决定是弹掉自己还是报错；资料页的十处调用点全部是「点一下打开看看」的即发
// 即忘，没有任何一处的后续动作取决于它成没成。给它一个所有人都得 .catch()
// 的 Promise，只会在十处调用点上各摊一行噪音，外加一个「忘了接住就是未捕获
// rejection」的新坑。
//
// 【原注释，现在只描述 tab === 'chat' 这一支】「origin 用 'content'：资料页是
// 从右栏内部打开的（会话里点头像、群资料里点成员、深链落到某个用户），要叠加
// 不要清栈，返回键得能退回会话。」
//
// **tab 默认 'chat'**，所以既有的八个调用点（ChatPage ×4、openTelegramLink ×4）
// 一个字都不用改，行为逐字不变。只有联系人页签在平板分栏下传 'contacts'。
//
// origin 跟着 tab 走，因为两处的语义本就不同：
//   'chat'     资料页是从右栏内部打开的（会话里点头像、群资料里点成员、深链
//              落到某个用户），要叠加不要清栈，返回键得能退回会话；
//   'contacts' 资料页是从**左栏**那张联系人列表选出来的，语义与「选一个会话」
//              完全一致——右栏该被替换而不是叠出第二层，否则连点两个联系人
//              之后要按两次返回才回得到空态。
export function navigateToProfile(params: Record<string, Object>, tab: TabKind = 'chat'): void {
  const origin: PushOrigin = tab === 'chat' ? 'content' : 'navbar';
  pushInto(PROFILE_DEST_NAME, PROFILE_PAGE_URL, params, origin, tab);
}

// 群/频道资料页。同 navigateToProfile，'content'。
export function navigateToChatProfile(params: Record<string, Object>): void {
  pushInto(CHAT_PROFILE_DEST_NAME, CHAT_PROFILE_PAGE_URL, params, 'content', 'chat');
}

// 话题群的话题列表。origin 由**入口所在的栏**决定，不再写死：
//   'navbar'  会话列表里点一个话题群——语义与「选一个会话」一致，右栏被换成
//             这个话题列表，而不是叠在一个不相干的会话上面；
//   'content' 归档列表里点一个话题群——归档页本身就是栈里的一层，'navbar'
//             的 clearAndPush 会把它一起清掉，返回时直接落回首页而不是归档
//             （issue #117 的形状）。chatNav.ets 头部那条「尚未覆盖」说的正是它。
export function navigateToForumTopics(
  params: Record<string, Object>, origin: PushOrigin = 'navbar'
): void {
  pushInto(FORUM_TOPICS_DEST_NAME, FORUM_TOPICS_PAGE_URL, params, origin, 'chat');
}

export function navigateToDirectMessagesTopics(
  params: Record<string, Object>, origin: PushOrigin = 'navbar'
): void {
  pushInto(DIRECT_MESSAGES_TOPICS_DEST_NAME, DIRECT_MESSAGES_TOPICS_PAGE_URL,
    params, origin, 'chat');
}

// 归档会话列表。同样是 'navbar'：入口在 MainTabBody（会话列表第 0 行），
// 是左栏里的一次选择，右栏该被替换而不是被叠加。
export function navigateToArchive(): void {
  pushInto(ARCHIVE_DEST_NAME, ARCHIVE_PAGE_URL, undefined, 'navbar', 'chat');
}
