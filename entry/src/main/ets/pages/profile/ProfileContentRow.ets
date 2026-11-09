import { ProfileContentItem } from '../../store/ChatProfileStore';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_ICON_SECONDARY, COLOR_TEXT_SECONDARY } from '../../util/theme';

// 共享内容（文件 / 链接 / 音乐 / 投票…）列表的一行，群资料页、个人资料页共用。
// 原来两页各有一份 Column + ForEach，翻了很多页就是几百行一起活着；现在走 LazyForEach，
// 这个组件在滚动时进出复用池。回调只收 messageId（它跟着复用节点走）。

// LazyForEach 的 key：内容一变（下载中、下完有了本地路径）就换 key，行跟着刷新。
export function profileContentKey(it: ProfileContentItem): string {
  return `${it.messageId}_${it.thumbPath}_${it.title}_${it.preview}_${it.meta}_` +
    `${it.downloading ? 1 : 0}_${it.fileId}_${it.filePath}`;
}

@Reusable
@Component
export struct ProfileContentRow {
  @Prop item: ProfileContentItem;
  // 没有缩略图时画的系统图标名（由页面按类型/页签算好）。
  @Prop icon: string = 'sys.symbol.message';
  // 群资料页给文档和音乐挂就地下载 / 打开按钮；个人资料页没有。
  @Prop fileActions: boolean = false;
  onOpen: (messageId: number) => void = (_messageId: number): void => {};
  onFileAction: (messageId: number) => void = (_messageId: number): void => {};

  @Styles
  rowNormalStyle() {
    .backgroundColor(Color.Transparent)
  }

  @Styles
  rowPressedStyle() {
    .backgroundColor($r('app.color.press_overlay'))
  }

  build() {
    Row({ space: 11 }) {
      Stack() {
        if (this.item.thumbPath !== '') {
          Image(`file://${this.item.thumbPath}`).draggable(false).width(46).height(46)
            .objectFit(ImageFit.Cover).borderRadius(10);
        } else {
          SymbolGlyph($r(this.icon)).fontSize(22).fontColor([COLOR_PRIMARY]);
        }
      }
      .width(46).height(46).borderRadius(10)
      .backgroundColor($r('app.color.surface_alt'));
      Column({ space: 3 }) {
        Text(this.item.title).fontSize(15).fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_PRIMARY).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
        if (this.item.preview !== '') {
          Text(this.item.preview).fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        }
        if (this.item.meta !== '') {
          Text(this.item.meta).fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        }
      }.alignItems(HorizontalAlign.Start).layoutWeight(1);
      // 文档和音乐给一个就地下载 / 打开的按钮；按钮自己吃掉点击，不连带整行的跳转。
      if (this.fileActions && this.item.downloading) {
        Row() {
          LoadingProgress().width(18).height(18).color(COLOR_PRIMARY);
        }
        .width(34).height(34).justifyContent(FlexAlign.Center);
      } else if (this.fileActions && this.item.fileId > 0) {
        Row() {
          SymbolGlyph($r(this.item.filePath !== ''
            ? 'sys.symbol.arrow_up_right' : 'sys.symbol.arrow_down_circle'))
            .fontSize(18).fontColor([COLOR_PRIMARY]);
        }
        .width(34).height(34).borderRadius(17)
        .justifyContent(FlexAlign.Center)
        .onClick((): void => { this.onFileAction(this.item.messageId); })
        .accessibilityText(this.item.filePath !== ''
          ? $r('app.string.open') : $r('app.string.gs_downloads'));
      } else {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(13).fontColor([COLOR_ICON_SECONDARY]);
      }
    }
    .width('100%').constraintSize({ minHeight: 64 })
    .padding({ left: 12, right: 10, top: 9, bottom: 9 })
    .stateStyles({ normal: this.rowNormalStyle, pressed: this.rowPressedStyle })
    .onClick((): void => { this.onOpen(this.item.messageId); });
  }
}
