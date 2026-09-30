// 「加入并添加到文件夹」的文件夹选单。
//
// 外观照右上角菜单里「添加到文件夹」那一面（ChatHeaderMenu.folderPanel）：同一套
// 行尺寸、按压反馈、菜单材质，文件夹多了自己滚。区别只有两处：
//   - 没有 ✓：会话此时还没加入，谈不上已在哪个文件夹里；
//   - 点一行就收菜单——这里是「选一个然后去做」，不是连着勾好几个。
// 第一版用的是系统 ActionSheet，和应用里其它菜单不是一个样子（用户：「太糙了，
// 和菜单里面的文件夹列表一样就行」）。
import { ComponentContent, UIContext } from '@kit.ArkUI';
import { getFolderStore } from '../../tdkit/Globals';
import { containerBlur, overlayMaterial } from '../../util/overlayMaterial';
import { COLOR_BUBBLE_TEXT } from '../../util/theme';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import { menuWidthFor } from '../../util/menuWidth';
import { str } from '../../util/strings';
import { logE } from '../../util/log';

// 与 ChatHeaderMenu 的文件夹子面板同一个上限：一行 44 左右，再多就滚。
const FOLDER_MENU_MAX_H: number = 320;

// 与 actionMenuRow 同一套按压反馈（@Styles 跨文件用不了，同参数复制，
// ChatHeaderMenu 里也是这么做的）。
@Styles
function rowNormalStyle() {
  .opacity(1)
  .scale({ x: 1, y: 1 })
}

@Styles
function rowPressedStyle() {
  .opacity(0.72)
  .scale({ x: 0.97, y: 0.94 })
}

interface FolderItem {
  id: number;
  title: string;
}

interface JoinFolderMenuParams {
  folders: FolderItem[];
  width: number;
  onPick: (folderId: number) => void;
}

@Builder
function joinFolderMenuLayer(params: JoinFolderMenuParams) {
  Column() {
    Row({ space: 14 }) {
      SymbolGlyph($r('sys.symbol.folder_badge_plus')).fontSize(19).fontColor([COLOR_BUBBLE_TEXT]);
      Text(str('cp_join_to_folder')).fontSize(16).fontColor(COLOR_BUBBLE_TEXT)
        .fontWeight(FontWeight.Medium).layoutWeight(1)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
    }
    .width('100%').padding({ left: 16, right: 16, top: 11, bottom: 11 })
    .alignItems(VerticalAlign.Center);
    Divider().color($r('app.color.divider')).strokeWidth(0.7);
    Scroll() {
      Column() {
        ForEach(params.folders, (folder: FolderItem): void => {
          Row() {
            Text(folder.title).fontSize(16).fontColor(COLOR_BUBBLE_TEXT)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1);
          }
          .width('100%').padding({ left: 16, right: 16, top: 11, bottom: 11 })
          .alignItems(VerticalAlign.Center)
          .borderRadius(10)
          .stateStyles({ normal: rowNormalStyle, pressed: rowPressedStyle })
          .animation({ duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110), curve: Curve.EaseOut })
          .onClick((): void => { params.onPick(folder.id); });
        }, (folder: FolderItem): string => `join_folder_${folder.id}`);
      }
      .width('100%');
    }
    .scrollBar(BarState.Off)
    .constraintSize({ maxHeight: FOLDER_MENU_MAX_H });
  }
  .width(params.width)
  .padding({ top: 6, bottom: 6 })
  .clip(true);
}

// 在 anchorId 那颗按钮上方弹出文件夹选单；选中后先收菜单，再回调 onPick。
// 没有文件夹就直接提示，不走加入——否则用户点的是"加入并添加"，结果只加入了。
export function openJoinFolderMenu(uiContext: UIContext, anchorId: string,
  onPick: (folderId: number) => void): void {
  const folders: FolderItem[] = getFolderStore().getFolders().map((f): FolderItem => ({
    id: f.id, title: f.title
  }));
  if (folders.length === 0) {
    uiContext.getPromptAction().showToast({ message: str('cl_no_folders'), duration: 1600 });
    return;
  }
  let node: ComponentContent<JoinFolderMenuParams> | null = null;
  const params: JoinFolderMenuParams = {
    folders: folders,
    width: menuWidthFor([str('cp_join_to_folder'), ...folders.map((f: FolderItem): string => f.title)]),
    onPick: (folderId: number): void => {
      const open: ComponentContent<JoinFolderMenuParams> | null = node;
      if (open === null) {
        return;
      }
      node = null;
      uiContext.getPromptAction().closeMenu(open)
        .catch((error: Object): void => { logE(`JoinFolderMenu close failed: ${error}`); })
        .finally((): void => { onPick(folderId); });
    }
  };
  try {
    const content: ComponentContent<JoinFolderMenuParams> =
      new ComponentContent(uiContext, wrapBuilder(joinFolderMenuLayer), params);
    node = content;
    uiContext.getPromptAction().openMenu(content, { id: anchorId }, {
      mask: false,
      // 按钮贴着屏幕底部，从它上方弹出。
      placement: Placement.Top,
      // 与 ChatHeaderMenu 同一套：模糊是基底、材质在支持时叠上，不设 backgroundColor。
      backgroundBlurStyle: containerBlur('menu'),
      systemMaterial: overlayMaterial('menu'),
      onDidDisappear: (): void => {
        node = null;
        content.dispose();
      }
    }).catch((error: Object): void => {
      node = null;
      content.dispose();
      logE(`JoinFolderMenu open failed: ${error}`);
    });
  } catch (error) {
    logE(`JoinFolderMenu create failed: ${error}`);
  }
}
