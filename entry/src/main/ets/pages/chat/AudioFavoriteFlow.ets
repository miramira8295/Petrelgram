import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import {
  createCollection, ensureMusicCollections, musicCollections, subscribeMusicCollections,
  toggleTrackInCollectionById
} from '../../store/MusicCollectionStore';
import { MusicCollection } from '../../util/musicCollectionModel';
import { musicTrackKey } from '../../util/musicTrackModel';
import { MusicAddToSheet, MusicCreateDialog } from '../music/MusicSheets';
import { str } from '../../util/strings';

// 聊天里点音频卡片上那枚「收藏」胶囊之后弹的那层：合集列表 + 新建合集。
//
// **独立成件而不是写进 ChatPage**（用户明令：逻辑进独立文件，ChatPage 只留薄接线）。
// 面板本身直接复用音乐中心那两张（MusicSheets 的 MusicAddToSheet / MusicCreateDialog）
// ——两处是同一件事，长得不一样才是问题。
//
// 收藏的单位是**曲目键**（会话 id + 消息 id），和音乐中心的合集是同一套数据，
// 所以在这儿收藏的歌，音乐中心的「我的」里立刻就在。

// **V2**：宿主 ChatPage 是 @ComponentV2，V1 组件带 @Link 挂不上去（编译期就报）。
// 所以关闭走回调而不是双向绑定，安全区高度也由宿主传进来——V2 读不了 AppStorage。
@ComponentV2
export struct AudioFavoriteFlow {
  // 0 = 不显示。由 ChatPage 在点击胶囊时填。
  @Param targetMessageId: number = 0;
  @Param chatId: number = 0;
  @Param trackTitle: string = '';
  @Param trackArtist: string = '';
  @Param bottomSafe: number = 0;
  @Param onClose: () => void = (): void => {};
  @Local private collections: MusicCollection[] = [];
  @Local private creating: boolean = false;
  @Local private newName: string = '';
  private unsub: (() => void) | null = null;

  aboutToAppear(): void {
    ensureMusicCollections(getContext(this) as common.UIAbilityContext);
    this.unsub = subscribeMusicCollections((): void => {
      this.collections = musicCollections().slice();
    });
  }

  aboutToDisappear(): void {
    if (this.unsub !== null) {
      this.unsub();
      this.unsub = null;
    }
  }

  private close(): void {
    this.creating = false;
    this.newName = '';
    this.onClose();
  }

  private trackKey(): string {
    return musicTrackKey(this.chatId, this.targetMessageId);
  }

  private confirmCreate(): void {
    const created: MusicCollection | null = createCollection(this.newName);
    if (created === null) {
      // 空名或重名，判据在 musicCollectionModel。提示一下再让他改，别静默吞掉。
      promptAction.showToast({ message: str('mc_create_rejected'), duration: 1600 });
      return;
    }
    toggleTrackInCollectionById(created.id, this.trackKey());
    this.creating = false;
    this.newName = '';
  }

  build() {
    if (this.targetMessageId !== 0) {
      Stack({ alignContent: Alignment.Bottom }) {
        Column()
          .width('100%').height('100%')
          .backgroundColor('#73000000')
          .onClick((): void => { this.close(); });
        if (this.creating) {
          Column() {
            MusicCreateDialog({
              fromAddTo: true,
              trackTitle: this.trackTitle,
              name: this.newName,
              onNameChange: (name: string): void => { this.newName = name; },
              onCancel: (): void => { this.creating = false; this.newName = ''; },
              onConfirm: (): void => { this.confirmCreate(); }
            });
          }
          .width('100%').height('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ left: 20, right: 20 });
        } else {
          MusicAddToSheet({
            collections: this.collections,
            trackKey: this.trackKey(),
            trackTitle: this.trackTitle,
            trackArtist: this.trackArtist,
            bottomInset: this.bottomSafe,
            onToggle: (collectionId: string): void => {
              toggleTrackInCollectionById(collectionId, this.trackKey());
            },
            onCreate: (): void => { this.creating = true; }
          });
        }
      }
      .width('100%').height('100%');
    }
  }
}
