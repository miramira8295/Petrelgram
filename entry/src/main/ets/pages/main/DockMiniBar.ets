// 底栏的迷你播放条——HdsTabs 的 `barFloatingStyle.miniBar` 收的那块内容。
//
// **它自己订阅曲目和播放态，不收任何入参。** 这不是偷懒：miniBar 收的是
// ComponentContent（脱离主树的子树），要让它跟着曲名/暂停态变，就得在外面
// 维护一份参数并逐次 update()。而这两样本来就有全局来源——nowPlayingChannel
// 和 getVoicePlayback()，组件直接订阅就永远是最新的，外面那份持有者也因此可以
// 原样复用 SplitPlaceholderHolder（它收的正是 WrappedBuilder<[]>）。
//
// 折叠/展开由 HDS 自己管（HdsBarStyle.COLLAPSE / EXPAND），这里只负责画内容。

import { AvatarView } from '../chatlist/AvatarView';
import { getVoicePlayback, VoiceState } from '../../services/VoicePlayback';
import {
  clearNowPlaying, NowPlaying, subscribeNowPlaying
} from '../../util/nowPlayingChannel';
import { nowPlayingTitle } from '../../util/dockMiniBar';
import { logChatNavFailure, navigateToChat } from '../../util/chatNav';
import { COLOR_PRIMARY, COLOR_TAB_UNSELECTED, COLOR_TEXT_PRIMARY } from '../../util/theme';
import { str } from '../../util/strings';

const COVER: number = 34;

@Component
struct DockMiniBarView {
  @State private track: NowPlaying | null = null;
  @State private paused: boolean = false;
  private unsubTrack: (() => void) | null = null;
  private unsubVoice: (() => void) | null = null;

  aboutToAppear(): void {
    this.unsubTrack = subscribeNowPlaying((state: NowPlaying | null): void => {
      this.track = state;
    });
    this.unsubVoice = getVoicePlayback().subscribe((s: VoiceState): void => {
      // **判据是"在不在放"，不是"是不是被暂停"。** VoiceState.status 有六个值
      // （idle / loading / playing / paused / completed / error），原来只认
      // `paused`，于是曲子放完（status = 'completed'、paused 仍是 false）时按钮
      // 还停在暂停图标上——用户报的正是这个。只有 'playing' 才画暂停键，其余
      // 一律画播放键（放完之后点一下正好重播）。
      this.paused = s.status !== 'playing';
    });
  }

  aboutToDisappear(): void {
    if (this.unsubTrack !== null) { this.unsubTrack(); this.unsubTrack = null; }
    if (this.unsubVoice !== null) { this.unsubVoice(); this.unsubVoice = null; }
  }

  private coverSource(): string {
    const path: string = this.track?.coverPath ?? '';
    return path.startsWith('/') ? `file://${path}` : path;
  }

  // 播放/暂停走全局单例：通道里带了 path，所以不依赖任何页面。
  private toggle(): void {
    const t: NowPlaying | null = this.track;
    if (t === null) {
      return;
    }
    getVoicePlayback().toggleMusic(t.messageId, t.path, t.durationSec);
  }

  // 终止：整条收掉，底栏掉回普通页签。
  private stop(): void {
    const t: NowPlaying | null = this.track;
    getVoicePlayback().stop();
    if (t !== null) {
      clearNowPlaying(t.messageId);
    }
  }

  // 点信息区回到那条消息。navigateToChat 是所有会话入口的唯一漏斗。
  private openMessage(): void {
    const t: NowPlaying | null = this.track;
    if (t === null || t.chatId === 0) {
      return;
    }
    const params: Record<string, Object> = { 'chatId': t.chatId, 'jumpTo': t.messageId };
    navigateToChat(params, 'navbar').catch(logChatNavFailure);
  }

  build() {
    Row({ space: 8 }) {
      Stack() {
        if (this.coverSource() !== '') {
          Image(this.coverSource()).draggable(false)
            .width('100%').height('100%').objectFit(ImageFit.Cover);
        } else {
          SymbolGlyph($r('sys.symbol.music_note_list')).fontSize(16).fontColor([COLOR_PRIMARY]);
        }
      }
      .width(COVER).height(COVER).borderRadius(COVER / 2)
      .backgroundColor($r('app.color.surface_alt'))
      .clip(true);
      Column() {
        Text(nowPlayingTitle(this.track?.title ?? '', str('svc_playing')))
          .fontSize(13).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        if ((this.track?.performer ?? '') !== '') {
          Text(this.track?.performer ?? '').fontSize(11).fontColor(COLOR_TAB_UNSELECTED)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      // 信息区整块可点：回到那条消息。两颗键各自吃掉自己的点击。
      .onClick((): void => { this.openMessage(); });
      Row() {
        SymbolGlyph($r(this.paused ? 'sys.symbol.play_fill' : 'sys.symbol.pause_fill'))
          .fontSize(18).fontColor([COLOR_TEXT_PRIMARY]);
      }
      .width(32).height(32).justifyContent(FlexAlign.Center)
      .onClick((): void => { this.toggle(); });
      Row() {
        SymbolGlyph($r('sys.symbol.xmark')).fontSize(15).fontColor([COLOR_TAB_UNSELECTED]);
      }
      .width(30).height(30).justifyContent(FlexAlign.Center)
      .onClick((): void => { this.stop(); });
    }
    .width('100%').height('100%')
    .padding({ left: 10, right: 8 })
    .alignItems(VerticalAlign.Center);
  }
}

@Builder
export function dockMiniBarLayer() {
  DockMiniBarView();
}
