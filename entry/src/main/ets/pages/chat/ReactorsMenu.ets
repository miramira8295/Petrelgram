// 「谁回应了」名单：点气泡表情条末尾的「>」，在它旁边弹出，按表情分组列出
// 回应人（#211 第 3 条）：
//   ❤️ 3
//     [头像] aaa
//     [头像] bbbb
//   👍 2
//     [头像] djdoq
//
// 原来只有「长按某个表情胶囊 → 系统对话框里一列纯文字名字」，入口藏得深、也没头像。
// 外观与文件夹选单（JoinFolderMenu）同一套菜单材质和行尺寸，名单多了自己滚。
import { ComponentContent, UIContext, promptAction } from '@kit.ArkUI';
import { getChatStore, getTdClient, getUserStore } from '../../tdkit/Globals';
import { TdError, TdObject, TdRequest } from '../../tdkit/TdTypes';
import { ReactionInfo } from '../../store/MessageEntry';
import { reactionDisplayLabel, reactionKeyFrom } from '../../util/reactions';
import { ReactorGroup, ReactorRow, groupReactors } from '../../util/reactorGroups';
import { containerBlur, overlayMaterial } from '../../util/overlayMaterial';
import { COLOR_BUBBLE_TEXT, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { LiveUserAvatar } from '../common/LiveUserAvatar';
import { str } from '../../util/strings';
import { logE } from '../../util/log';

const REACTORS_MENU_MAX_H: number = 360;
const REACTORS_MENU_WIDTH: number = 240;
// getMessageAddedReactions 单次上限是 100。再多的人很少见，也不适合塞进菜单。
const REACTORS_LIMIT: number = 100;
const AVATAR_SIZE: number = 28;
// 行高估算，弹出那一刻用来定死菜单高度（菜单尺寸只在弹出时量一次，之后内容变高
// 会被裁掉——ChatHeaderMenu 实测过）。与下面 builder 里的 padding/尺寸对应。
const EST_PAD_V: number = 12;
const EST_HEADER_H: number = 34;
const EST_ROW_H: number = 40;
const EST_DIVIDER_H: number = 9;
const EST_MORE_H: number = 30;
// 名单缓存：同一条消息再点不再等网络；回应数变了（签名不同）才重拉。
const CACHE_MAX: number = 50;

interface ReactorsGroupView {
  label: string;       // unicode 表情本身；自定义表情没有可显示字符时是文字说明
  imagePath: string;   // 自定义表情已下载的位图，'' = 用 label
  count: number;       // 这个表情的真实总数（来自消息本身，不受单次拉取上限影响）
  rows: ReactorRow[];
}

interface ReactorsMenuParams {
  groups: ReactorsGroupView[];
  more: number;        // 没拉回来的人数（总数超过单次上限时）
  loading: boolean;    // 名单还在路上：组标题先画，下面转圈
  height: number;      // 弹出时定死的高度
}

interface CachedReactors {
  sig: string;
  groups: ReactorsGroupView[];
  more: number;
}

const cache: Map<string, CachedReactors> = new Map<string, CachedReactors>();

function initialsOf(name: string): string {
  const t: string = name.trim();
  return t !== '' ? t.substring(0, 1).toUpperCase() : '?';
}

@Builder
function reactorsMenuLayer(params: ReactorsMenuParams) {
  Scroll() {
    Column() {
      ForEach(params.groups, (g: ReactorsGroupView, gi: number): void => {
        if (gi > 0) {
          Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ top: 4, bottom: 4 });
        }
        Row({ space: 6 }) {
          if (g.imagePath !== '') {
            Image(g.imagePath).width(18).height(18).objectFit(ImageFit.Contain).draggable(false);
          } else {
            Text(g.label).fontSize(16);
          }
          Text(`${g.count}`).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
        }
        .width('100%').padding({ left: 14, right: 14, top: 8, bottom: 4 })
        .alignItems(VerticalAlign.Center);
        if (params.loading && gi === 0) {
          Row() {
            LoadingProgress().width(22).height(22).color(COLOR_TEXT_SECONDARY);
          }
          .width('100%').height(EST_ROW_H).justifyContent(FlexAlign.Center);
        }
        ForEach(g.rows, (r: ReactorRow): void => {
          Row({ space: 10 }) {
            if (r.userId > 0) {
              LiveUserAvatar({
                userId: r.userId, initials: initialsOf(r.name), avatarSize: AVATAR_SIZE,
                avatarFileId: getUserStore().photoFileId(r.userId)
              });
            } else {
              Text(initialsOf(r.name)).fontSize(13).fontColor(Color.White)
                .width(AVATAR_SIZE).height(AVATAR_SIZE).borderRadius(AVATAR_SIZE / 2)
                .textAlign(TextAlign.Center).backgroundColor('#8E8E93');
            }
            Text(r.name).fontSize(15).fontColor(COLOR_BUBBLE_TEXT)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1);
          }
          .width('100%').padding({ left: 14, right: 14, top: 6, bottom: 6 })
          .alignItems(VerticalAlign.Center);
        }, (r: ReactorRow, ri: number): string => `${g.label}_${r.userId}_${r.chatId}_${ri}`);
      }, (g: ReactorsGroupView, gi: number): string => `grp_${gi}_${g.label}`);
      if (params.more > 0) {
        Text(`+${params.more}`).fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
          .width('100%').padding({ left: 14, right: 14, top: 6, bottom: 6 });
      }
    }
    .width('100%');
  }
  .width(REACTORS_MENU_WIDTH)
  .height(params.height)
  .padding({ top: 6, bottom: 6 })
  .scrollBar(BarState.Off)
  .align(Alignment.Top);
}

// TDLib 的 ReactionType → util/reactions 的 key。
function keyOfType(type: TdObject | undefined): string {
  if (type === undefined) {
    return '';
  }
  if (type['@type'] === 'reactionTypeCustomEmoji') {
    return reactionKeyFrom('', (type['custom_emoji_id'] as string | undefined) ?? '');
  }
  if (type['@type'] === 'reactionTypePaid') {
    return '⭐';
  }
  return (type['emoji'] as string | undefined) ?? '';
}

function rowOf(added: TdObject): ReactorRow {
  const key: string = keyOfType(added['type'] as TdObject | undefined);
  const sender = added['sender_id'] as TdObject | undefined;
  if (sender !== undefined && sender['@type'] === 'messageSenderUser') {
    const uid: number = (sender['user_id'] as number | undefined) ?? 0;
    const name: string = getUserStore().displayName(uid);
    if (name === '') {
      getUserStore().ensure(uid);
    }
    return { reactionKey: key, userId: uid, chatId: 0, name: name !== '' ? name : str('cp_user_id', uid) };
  }
  const cid: number = sender !== undefined ? ((sender['chat_id'] as number | undefined) ?? 0) : 0;
  const entry = getChatStore().entryOf(cid);
  return { reactionKey: key, userId: 0, chatId: cid, name: entry !== undefined ? entry.title : str('cp_anonymous') };
}

function imagePathOf(info: ReactionInfo): string {
  // 本地路径要带 file:// 才认，同 MessageBubble.reactionImageSource。
  if (info.customEmojiPath === '') {
    return '';
  }
  return info.customEmojiPath.startsWith('/') ? `file://${info.customEmojiPath}` : info.customEmojiPath;
}

function signatureOf(reactions: ReactionInfo[]): string {
  return reactions.map((r: ReactionInfo): string =>
    `${reactionKeyFrom(r.emoji, r.customEmojiId)}:${r.count}`).join(',');
}

// 本地就有的东西（表情、每种的真实人数），弹出那一刻用：组标题先画，名单空着。
function placeholderGroups(reactions: ReactionInfo[]): ReactorsGroupView[] {
  return reactions.map((r: ReactionInfo): ReactorsGroupView => ({
    label: reactionDisplayLabel(reactionKeyFrom(r.emoji, r.customEmojiId)),
    imagePath: imagePathOf(r),
    count: r.count,
    rows: []
  }));
}

// 按本地人数估一个高度，名单到了刚好装得下；封顶后交给滚动。
function estimateHeight(reactions: ReactionInfo[]): number {
  let people: number = 0;
  for (const r of reactions) {
    people += r.count;
  }
  const rows: number = Math.min(people, REACTORS_LIMIT);
  const groups: number = Math.max(1, reactions.length);
  const h: number = EST_PAD_V + groups * EST_HEADER_H + (groups - 1) * EST_DIVIDER_H +
    Math.max(1, rows) * EST_ROW_H + (people > REACTORS_LIMIT ? EST_MORE_H : 0);
  return Math.min(REACTORS_MENU_MAX_H, h);
}

// 名单到货后的分组：顺序按表情条的顺序（弹出前后不跳），表情条上没有的排在后面。
function resolvedGroups(groups: ReactorGroup[], reactions: ReactionInfo[]): ReactorsGroupView[] {
  const views: ReactorsGroupView[] = [];
  for (const r of reactions) {
    const key: string = reactionKeyFrom(r.emoji, r.customEmojiId);
    const hit: ReactorGroup | undefined = groups.find((g: ReactorGroup): boolean => g.reactionKey === key);
    if (hit !== undefined) {
      views.push({ label: reactionDisplayLabel(key), imagePath: imagePathOf(r),
        count: Math.max(r.count, hit.rows.length), rows: hit.rows });
    }
  }
  for (const g of groups) {
    const known: boolean = reactions.some((r: ReactionInfo): boolean =>
      reactionKeyFrom(r.emoji, r.customEmojiId) === g.reactionKey);
    if (!known) {
      views.push({ label: reactionDisplayLabel(g.reactionKey), imagePath: '',
        count: g.rows.length, rows: g.rows });
    }
  }
  return views;
}

function remember(key: string, entry: CachedReactors): void {
  if (cache.size >= CACHE_MAX && !cache.has(key)) {
    const oldest: string | undefined = cache.keys().next().value;
    if (oldest !== undefined) {
      cache.delete(oldest);
    }
  }
  cache.set(key, entry);
}

// 点「>」：立刻在 anchorId 旁边弹出（组标题先画、下面转圈），名单到了再填进去。
// 同一条消息再点、回应数没变，直接用上次的名单，不等网络。
// reactions：这条消息自己的表情条数据——表情、自定义表情位图、真实人数都从这里来。
export function openReactorsMenu(uiContext: UIContext, chatId: number, messageId: number,
  anchorId: string, reactions: ReactionInfo[]): void {
  const cacheKey: string = `${chatId}:${messageId}`;
  const sig: string = signatureOf(reactions);
  const height: number = estimateHeight(reactions);
  const hit: CachedReactors | undefined = cache.get(cacheKey);
  if (hit !== undefined && hit.sig === sig) {
    showMenu(uiContext, anchorId, { groups: hit.groups, more: hit.more, loading: false, height: height });
    return;
  }
  const menu: OpenReactorsMenu | null = showMenu(uiContext, anchorId,
    { groups: placeholderGroups(reactions), more: 0, loading: true, height: height });
  const req: TdRequest = { '@type': 'getMessageAddedReactions' };
  req['chat_id'] = chatId;
  req['message_id'] = messageId;
  req['offset'] = '';
  req['limit'] = REACTORS_LIMIT;
  getTdClient().send(req, 10000).then((result: TdObject): void => {
    const added: TdObject[] = (result['reactions'] as TdObject[] | undefined) ?? [];
    const total: number = (result['total_count'] as number | undefined) ?? added.length;
    const groups: ReactorGroup[] = groupReactors(added.map((a: TdObject): ReactorRow => rowOf(a)));
    if (groups.length === 0) {
      menu?.close();
      promptAction.showToast({ message: $r('app.string.cp_no_reaction_details'), duration: 1600 });
      return;
    }
    const views: ReactorsGroupView[] = resolvedGroups(groups, reactions);
    const more: number = Math.max(0, total - added.length);
    remember(cacheKey, { sig: sig, groups: views, more: more });
    menu?.update({ groups: views, more: more, loading: false, height: height });
  }).catch((e: TdError): void => {
    logE(`ReactorsMenu fetch failed: ${e.message}`);
    menu?.close();
    promptAction.showToast({ message: $r('app.string.cp_no_reaction_details'), duration: 1600 });
  });
}

// 弹出之后留给调用方的两个动作；菜单已经关掉时两者都什么也不做。
interface OpenReactorsMenu {
  update: (params: ReactorsMenuParams) => void;
  close: () => void;
}

function showMenu(uiContext: UIContext, anchorId: string, params: ReactorsMenuParams): OpenReactorsMenu | null {
  try {
    const content: ComponentContent<ReactorsMenuParams> =
      new ComponentContent(uiContext, wrapBuilder(reactorsMenuLayer), params);
    let alive: boolean = true;
    uiContext.getPromptAction().openMenu(content, { id: anchorId }, {
      mask: false,
      placement: Placement.BottomLeft,
      // 与 ChatHeaderMenu / JoinFolderMenu 同一套：模糊是基底、材质在支持时叠上。
      backgroundBlurStyle: containerBlur('menu'),
      systemMaterial: overlayMaterial('menu'),
      onDidDisappear: (): void => {
        alive = false;
        content.dispose();
      }
    }).catch((error: Object): void => {
      alive = false;
      content.dispose();
      logE(`ReactorsMenu open failed: ${error}`);
    });
    return {
      update: (next: ReactorsMenuParams): void => {
        if (alive) {
          content.update(next);
        }
      },
      close: (): void => {
        if (alive) {
          uiContext.getPromptAction().closeMenu(content).catch((): void => {});
        }
      }
    };
  } catch (error) {
    logE(`ReactorsMenu create failed: ${error}`);
    return null;
  }
}
