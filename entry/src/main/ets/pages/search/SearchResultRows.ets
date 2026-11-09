import { SearchHitText } from './SearchHitText';
import { SearchIdentity, MessageMatch, searchHit, searchExcerpt } from '../../util/searchPresentation';
import { AvatarView } from '../chatlist/AvatarView';
import {
  COLOR_ICON_SECONDARY, COLOR_ON_PRIMARY, COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY, mainCardFill
} from '../../util/theme';
import { str } from '../../util/strings';

// 全局搜索页的结果行（原 GlobalSearchPage 里的 chatRow / msgRow / 媒体格 / downloadRow builder）。
//
// 都是 @Reusable 组件，配 LazyForEach 用：只画。点击、长按菜单、无障碍文本挂在页面的
// ListItem / GridItem 上，闭包随行 key 重建。行内按钮的回调只报 id——回调是普通成员，
// 跟着节点进出复用池、不随新的一行更新，攥行对象就会拿到上一行。
//
// 按压态留在行里：原来就是行自己的 stateStyles 叠在卡片 / ListItem 的底色之上，保持同样的叠法。

// 会话 / 频道结果的一行。
@Reusable
@Component
export struct SearchChatRow {
  @Require @Prop query: string = '';
  @Prop identity: SearchIdentity | undefined = undefined;
  @Prop chatId: number = 0;
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop avatarPath: string = '';
  @Prop initials: string = '';
  @Prop savedMessages: boolean = false;
  @Prop opening: boolean = false;
  @Prop wallpaperOn: boolean = false;

  private matchLabel(): string {
    const labels: string[] = [];
    if (searchHit(this.title, this.query)) {
      labels.push(str(this.identity?.kind === 'channel' ? 'gs_hit_channel' :
        (this.identity?.kind === 'group' ? 'gs_hit_group' : 'gs_hit_name')));
    }
    if (this.identity?.usernames.some((name: string): boolean => searchHit('@' + name, this.query))) {
      labels.push(str('gs_hit_username'));
    }
    return labels.join(' · ');
  }

  @Styles
  normalStyle() {
    .backgroundColor(mainCardFill(this.wallpaperOn, false))
  }

  @Styles
  pressedStyle() {
    .backgroundColor(mainCardFill(this.wallpaperOn, true))
  }

  build() {
    Row({ space: 12 }) {
      AvatarView({
        avatarPath: this.avatarPath, initials: this.initials, colorSeed: this.chatId, avatarSize: 48,
        savedMessages: this.savedMessages
      });
      Column({ space: 3 }) {
        SearchHitText({ text: this.title !== '' ? this.title : '…', query: this.query, textSize: 16, lines: 1 });
        if (this.identity !== undefined && this.identity.usernames.length > 0 && (this.query ?? '').trim() !== '') {
          SearchHitText({ text: this.identity.usernames.map((name: string): string => '@' + name).join(' · '),
            query: this.query, textSize: 12, lines: 2, color: COLOR_TEXT_SECONDARY });
        }
        if (this.matchLabel() !== '') {
          Text(this.matchLabel()).fontSize(11).fontColor(COLOR_PRIMARY);
        }
        if (this.identity?.joined !== undefined && (this.query ?? '').trim() !== '') {
          Text(this.identity!.joined ? str('gs_member_joined') : str('gs_member_not_joined'))
            .fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
        }
        if (this.subtitle !== '') {
          Text(this.subtitle).fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        }
      }.alignItems(HorizontalAlign.Start).layoutWeight(1);
      if (this.opening) {
        LoadingProgress().width(18).height(18).color(COLOR_PRIMARY);
      }
    }
    .width('100%')
    .constraintSize({ minHeight: 64 })
    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
    .stateStyles({ normal: this.normalStyle, pressed: this.pressedStyle });
  }
}

// 消息结果的一行。时间标签由页面算好传进来（页面持有「现在」的基准秒）。
@Reusable
@Component
export struct SearchMessageRow {
  @Require @Prop query: string = '';
  @Prop match: MessageMatch | undefined = undefined;
  @Prop chatId: number = 0;
  @Prop chatTitle: string = '';
  @Prop avatarPath: string = '';
  @Prop initials: string = '';
  @Prop preview: string = '';
  @Prop timeLabel: string = '';
  @Prop opening: boolean = false;
  @Prop wallpaperOn: boolean = false;

  @Styles
  normalStyle() {
    .backgroundColor(mainCardFill(this.wallpaperOn, false))
  }

  @Styles
  pressedStyle() {
    .backgroundColor(mainCardFill(this.wallpaperOn, true))
  }

  build() {
    Row({ space: 12 }) {
      AvatarView({ avatarPath: this.avatarPath, initials: this.initials, colorSeed: this.chatId, avatarSize: 44 });
      Column({ space: 3 }) {
        Row() {
          Text(this.chatTitle !== '' ? this.chatTitle : '...')
            .fontSize(15).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1);
          if (this.opening) {
            LoadingProgress().width(16).height(16).color(COLOR_PRIMARY);
          } else {
            Text(this.timeLabel).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
          }
        }.width('100%');
        SearchHitText({ text: searchExcerpt(this.match?.body || this.preview, this.query),
          query: this.match?.body ? this.query : '', textSize: 14, color: COLOR_TEXT_SECONDARY });
        if (this.match !== undefined && this.match.fileName !== '') {
          SearchHitText({ text: searchExcerpt(this.match.fileName, this.query), query: this.query,
            textSize: 13, lines: 2, color: COLOR_TEXT_SECONDARY });
        }
        if (searchHit(this.match?.body ?? '', this.query) || searchHit(this.match?.fileName ?? '', this.query)) {
          Text([searchHit(this.match?.body ?? '', this.query) ? str('gs_hit_message') : '',
            searchHit(this.match?.fileName ?? '', this.query) ? str('gs_hit_filename') : '']
            .filter((label: string): boolean => label !== '').join(' · '))
            .fontSize(11).fontColor(COLOR_PRIMARY);
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .constraintSize({ minHeight: 66 })
    .stateStyles({ normal: this.normalStyle, pressed: this.pressedStyle });
  }
}

// 媒体 tab 宫格的一格。
@Reusable
@Component
export struct SearchMediaCell {
  @Prop thumbPath: string = '';
  @Prop isVideo: boolean = false;
  @Prop duration: string = '';
  @Prop wallpaperOn: boolean = false;

  @Styles
  normalStyle() {
    .opacity(1)
  }

  @Styles
  pressedStyle() {
    .opacity(0.82)
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      if (this.thumbPath !== '') {
        Image(`file://${this.thumbPath}`).draggable(false)
          .width('100%').height('100%').objectFit(ImageFit.Cover);
      } else {
        Column().width('100%').height('100%').backgroundColor(mainCardFill(this.wallpaperOn, true));
      }
      if (this.isVideo) {
        Row({ space: 3 }) {
          SymbolGlyph($r('sys.symbol.play_fill')).fontSize(10).fontColor([Color.White]);
          Text(this.duration).fontSize(11).fontColor(Color.White);
        }
        .backgroundColor('#00000066').borderRadius(8)
        .padding({ left: 5, right: 5, top: 1, bottom: 1 })
        .margin({ right: 4, bottom: 4 });
      }
    }
    .width('100%').aspectRatio(1)
    .clip(true)
    .stateStyles({ normal: this.normalStyle, pressed: this.pressedStyle });
  }
}

// 应用（小程序机器人）结果的一行。「打开」键只是样式，点击在页面的 ListItem 上。
@Reusable
@Component
export struct SearchAppRow {
  @Require @Prop query: string = '';
  @Prop identity: SearchIdentity | undefined = undefined;
  @Prop userId: number = 0;
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop avatarPath: string = '';
  @Prop initials: string = '';
  @Prop opening: boolean = false;
  @Prop wallpaperOn: boolean = false;

  private matchLabel(): string {
    const labels: string[] = [];
    if (searchHit(this.title, this.query)) {
      labels.push(str(this.identity?.kind === 'channel' ? 'gs_hit_channel' :
        (this.identity?.kind === 'group' ? 'gs_hit_group' : 'gs_hit_name')));
    }
    if (this.identity?.usernames.some((name: string): boolean => searchHit('@' + name, this.query))) {
      labels.push(str('gs_hit_username'));
    }
    return labels.join(' · ');
  }

  @Styles
  normalStyle() {
    .backgroundColor(mainCardFill(this.wallpaperOn, false))
  }

  @Styles
  pressedStyle() {
    .backgroundColor(mainCardFill(this.wallpaperOn, true))
  }

  build() {
    Row({ space: 12 }) {
      AvatarView({ avatarPath: this.avatarPath, initials: this.initials, colorSeed: this.userId, avatarSize: 48 });
      Column({ space: 3 }) {
        SearchHitText({ text: this.title !== '' ? this.title : '…', query: this.query, textSize: 16, lines: 1 });
        if (this.identity !== undefined && this.identity.usernames.length > 0 && (this.query ?? '').trim() !== '') {
          SearchHitText({ text: this.identity.usernames.map((name: string): string => '@' + name).join(' · '),
            query: this.query, textSize: 12, lines: 2, color: COLOR_TEXT_SECONDARY });
        }
        if (this.matchLabel() !== '') {
          Text(this.matchLabel()).fontSize(11).fontColor(COLOR_PRIMARY);
        }
        if (this.identity?.joined !== undefined && (this.query ?? '').trim() !== '') {
          Text(this.identity!.joined ? str('gs_member_joined') : str('gs_member_not_joined'))
            .fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
        }
        if (this.subtitle !== '') {
          Text(this.subtitle).fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        }
      }.alignItems(HorizontalAlign.Start).layoutWeight(1);
      Row() {
        if (this.opening) {
          LoadingProgress().width(16).height(16).color(Color.White);
        } else {
          Text($r('app.string.open')).fontSize(14).fontWeight(FontWeight.Medium).fontColor(COLOR_ON_PRIMARY);
        }
      }
      .width(58).height(30)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(COLOR_PRIMARY)
      .borderRadius(15);
    }
    .width('100%')
    .constraintSize({ minHeight: 64 })
    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
    .stateStyles({ normal: this.normalStyle, pressed: this.pressedStyle });
  }
}

// 搜索首页「常用联系人」横排的一格。点击和按压态在页面的 ListItem 上。
@Reusable
@Component
export struct SearchFrequentCell {
  @Prop chatId: number = 0;
  @Prop title: string = '';
  @Prop avatarPath: string = '';
  @Prop initials: string = '';
  @Prop savedMessages: boolean = false;
  @Prop opening: boolean = false;

  build() {
    Column({ space: 6 }) {
      Stack({ alignContent: Alignment.Center }) {
        AvatarView({
          avatarPath: this.avatarPath,
          initials: this.initials,
          colorSeed: this.chatId,
          avatarSize: 58,
          savedMessages: this.savedMessages
        });
        if (this.opening) {
          Circle({ width: 58, height: 58 }).fill('#66000000');
          LoadingProgress().width(20).height(20).color(Color.White);
        }
      }
      Text(this.title)
        .fontSize(13)
        .fontColor(COLOR_TEXT_PRIMARY)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width(68)
        .textAlign(TextAlign.Center);
    }
    .width(78)
    .height(92)
    .padding({ top: 6 });
  }
}
