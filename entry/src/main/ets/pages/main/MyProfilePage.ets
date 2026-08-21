import { promptAction, router } from '@kit.ArkUI';
import {
  HdsNavigation, HdsNavigationIconOptions, HdsNavigationMenuItemOptions,
  HdsNavigationTitleMode, TitleBarContentOptions
} from '@kit.UIDesignKit';
import { titleBarStyle } from '../../util/hdsTitleBar';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { cameraPicker } from '@kit.CameraKit';
import { camera } from '@kit.CameraKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { image } from '@kit.ImageKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { StickerPicker, StickerItem } from '../chat/StickerPicker';
import { getTdClient } from '../../tdkit/Globals';
import { ProfileStore, StoryItem } from '../../store/ProfileStore';
import { AvatarView } from '../chatlist/AvatarView';
import { QrDialog } from '../common/QrDialog';
import { TgsStickerView } from '../chat/TgsStickerView';
import { WebmStickerView } from '../chat/WebmStickerView';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { publicLink } from '../../util/telegramLink';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import { plural, str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import {
  overlayBackdropBlur, overlayGlassFill, MATERIAL_EPOCH
} from '../../util/overlayMaterial';
import { materialModifier } from '../../util/materialModifier';
import { logE } from '../../util/log';

const CARD_BG: ResourceColor = $r('app.color.surface');
const CARD_RADIUS: number = 14;
const PAGE_BG: ResourceColor = $r('app.color.page_bg');
const TOP_ACTION_SIZE: number = 44;
const PROFILE_LOAD_TIMEOUT_MS: number = 8000;

// The current user's own profile tab (Telegram-style "my profile"): avatar
// header, 设置照片/编辑信息/设置 quick actions, an info card (phone/username/
// birthday) and the 动态 posts section. Mirrors ProfileStore snapshot into
// @State so every card re-renders on updates.
@Preview
// 组件冻结：这四个页签由 MainScreen 的 Tabs 保活，同一时刻只有一个在屏上，
// 其余三棵树却照样响应各自 store 的状态更新、照样重跑 build。冻结之后非
// 激活的页签不再刷新，切回来时框架补上延后的那次更新。
@Component({ freezeWhenInactive: true })
export struct MyProfilePage {
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @Prop active: boolean = false;
  onOpenSettings: () => void = (): void => {};
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @StorageProp('screenWidthVp') screenW: number = 360;
  @StorageProp('appIsForeground') appIsForeground: boolean = false;
  @State myId: number = 0;
  @State name: string = '';
  @State initials: string = '?';
  @State avatarPath: string = '';
  @State avatarAnimPath: string = '';
  @State statusEmojiPath: string = '';
  @State statusEmojiFormat: string = '';
  @State statusText: string = '';
  @State phone: string = '';
  @State usernames: string[] = [];
  @State birthday: string = '';
  @State postTab: number = 0; // 0 动态 / 1 已归档的动态
  @State stories: StoryItem[] = [];
  @State storiesLoading: boolean = true;
  @State storiesError: string = '';
  @State archivedStories: StoryItem[] = [];
  @State archivedStoriesLoading: boolean = false;
  @State archivedStoriesLoaded: boolean = false;
  @State archivedStoriesError: string = '';
  @State profileLoading: boolean = true;
  @State profileError: string = '';
  @State headerVisible: boolean = false;
  @State avatarPressed: boolean = false;
  @State photoUploading: boolean = false;
  @State openingEditor: boolean = false;
  private profileScroller: Scroller = new Scroller();
  @State topMenuOpen: boolean = false;
  @State photoMenuOpen: boolean = false;
  @State switchingToSettings: boolean = false;
  @State pressedQuickAction: string = '';
  @State pressedInfoKey: string = '';
  @State copyingInfoKey: string = '';
  @State copiedInfoKey: string = '';
  @State pressedPostTab: number = -1;
  @State postTabsWidth: number = 0;
  @State pressedPostStateAction: string = '';
  @State storyPickerOpen: boolean = false;
  @State storyPosting: boolean = false;
  private store: ProfileStore | null = null;
  private unsub: (() => void) | null = null;
  private profileLoadSequence: number = 0;
  private profileLoadTimer: number = -1;
  private headerRevealTimer: number = -1;
  private editorNavigationTimer: number = -1;
  private settingsNavigationTimer: number = -1;
  private copiedInfoTimer: number = -1;
  private photoUploadSequence: number = 0;
  private storyUploadSequence: number = 0;
  private storyChatId: number = 0;

  aboutToAppear(): void {
    this.loadProfile();
  }

  private loadProfile(): void {
    const sequence = ++this.profileLoadSequence;
    this.closeProfileStore();
    this.clearProfileLoadTimer();
    this.profileLoading = true;
    this.profileError = '';
    this.stories = [];
    this.storiesLoading = true;
    this.storiesError = '';
    this.archivedStories = [];
    this.archivedStoriesLoading = false;
    this.archivedStoriesLoaded = false;
    this.archivedStoriesError = '';
    this.headerVisible = false;
    this.headerRevealTimer = setTimeout((): void => {
      this.headerRevealTimer = -1;
      this.headerVisible = true;
    }, powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 40));
    const req: TdRequest = { '@type': 'getMe' };
    getTdClient().send(req, PROFILE_LOAD_TIMEOUT_MS).then((me: TdObject) => {
      if (sequence !== this.profileLoadSequence) {
        return;
      }
      this.myId = (me['id'] as number | undefined) ?? 0;
      if (this.myId === 0) {
        this.profileLoading = false;
        this.profileError = str('mp_unreadable');
        return;
      }
      const store = new ProfileStore(getTdClient(), this.myId);
      this.store = store;
      this.unsub = store.subscribe(() => { this.refresh(); });
      store.open();
      if (this.postTab === 1) {
        store.loadArchivedStories();
      }
      this.profileLoadTimer = setTimeout((): void => {
        this.profileLoadTimer = -1;
        if (sequence === this.profileLoadSequence && this.profileLoading) {
          this.profileLoading = false;
          this.profileError = str('mp_timeout');
        }
      }, PROFILE_LOAD_TIMEOUT_MS);
    }).catch((e: TdError) => {
      if (sequence !== this.profileLoadSequence) {
        return;
      }
      this.clearProfileLoadTimer();
      this.profileLoading = false;
      this.profileError = str('mp_load_failed');
      logE(`MyProfilePage.getMe failed: ${e.message}`);
    });
  }

  aboutToDisappear(): void {
    this.profileLoadSequence++;
    this.photoUploadSequence++;
    this.storyUploadSequence++;
    this.clearProfileLoadTimer();
    this.closeProfileStore();
    if (this.headerRevealTimer !== -1) {
      clearTimeout(this.headerRevealTimer);
      this.headerRevealTimer = -1;
    }
    if (this.editorNavigationTimer !== -1) {
      clearTimeout(this.editorNavigationTimer);
      this.editorNavigationTimer = -1;
    }
    if (this.settingsNavigationTimer !== -1) {
      clearTimeout(this.settingsNavigationTimer);
      this.settingsNavigationTimer = -1;
    }
    if (this.copiedInfoTimer !== -1) {
      clearTimeout(this.copiedInfoTimer);
      this.copiedInfoTimer = -1;
    }
    this.headerVisible = false;
    this.avatarPressed = false;
    this.openingEditor = false;
    this.topMenuOpen = false;
    this.photoMenuOpen = false;
    this.switchingToSettings = false;
    this.pressedQuickAction = '';
    this.pressedInfoKey = '';
    this.copyingInfoKey = '';
    this.copiedInfoKey = '';
    this.pressedPostTab = -1;
    this.pressedPostStateAction = '';
    this.storyPickerOpen = false;
    this.storyPosting = false;
  }

  private closeProfileStore(): void {
    if (this.unsub !== null) { this.unsub(); this.unsub = null; }
    if (this.store !== null) { this.store.close(); this.store = null; }
  }

  private clearProfileLoadTimer(): void {
    if (this.profileLoadTimer !== -1) {
      clearTimeout(this.profileLoadTimer);
      this.profileLoadTimer = -1;
    }
  }

  private retryProfile(): void {
    if (this.profileLoading || this.photoUploading || this.openingEditor) {
      return;
    }
    this.loadProfile();
  }

  @State qrLink: string = '';
  private qrCtrl: CustomDialogController = new CustomDialogController({
    builder: QrDialog({ link: this.qrLink, title: this.name }),
    alignment: DialogAlignment.Center,
    autoCancel: true
  });

  private openQr(): void {
    if (this.profileLoading || this.profileError !== '' ||
      this.photoUploading || this.photoMenuOpen || this.openingEditor ||
      this.switchingToSettings || this.topMenuOpen) {
      return;
    }
    if (this.usernames.length === 0) {
      promptAction.showToast({ message: $r('app.string.mp_no_username_qr'), duration: 1800 });
      return;
    }
    this.qrLink = publicLink(this.usernames[0]);
    this.qrCtrl.open();
  }

  private openEditor(): void {
    if (this.profileLoading || this.profileError !== '' ||
      this.photoUploading || this.photoMenuOpen || this.openingEditor ||
      this.switchingToSettings || this.topMenuOpen) {
      return;
    }
    this.openingEditor = true;
    this.editorNavigationTimer = setTimeout((): void => {
      this.editorNavigationTimer = -1;
      this.openingEditor = false;
    }, 700);
    router.pushUrl({ url: 'pages/main/AccountEditPage' }).catch((error: Error): void => {
      logE(`MyProfilePage.openEditor failed: ${error.message}`);
      promptAction.showToast({ message: $r('app.string.settings_open_profile_failed'), duration: 1800 });
      if (this.editorNavigationTimer !== -1) {
        clearTimeout(this.editorNavigationTimer);
        this.editorNavigationTimer = -1;
      }
      this.openingEditor = false;
    });
  }

  private openSettings(): void {
    if (this.photoUploading || this.photoMenuOpen || this.openingEditor ||
      this.switchingToSettings || this.topMenuOpen) {
      return;
    }
    this.switchingToSettings = true;
    this.pressedQuickAction = '';
    this.settingsNavigationTimer = setTimeout((): void => {
      this.settingsNavigationTimer = -1;
      this.switchingToSettings = false;
    }, 520);
    this.onOpenSettings();
  }

  private showTopMenu(): void {
    if (this.profileLoading || this.profileError !== '' ||
      this.photoUploading || this.photoMenuOpen || this.openingEditor ||
      this.switchingToSettings || this.topMenuOpen) {
      return;
    }
    this.topMenuOpen = true;
    promptAction.showActionMenu({
      title: this.name !== '' ? this.name : $r('app.string.tab_profile'),
      buttons: [
        { text: $r('app.string.settings_edit_profile'), color: '#3390EC' },
        { text: $r('app.string.mp_set_photo'), color: '#3390EC' },
        { text: $r('app.string.mp_show_qr'), color: '#3390EC' }
      ]
    }).then((result): void => {
      this.topMenuOpen = false;
      if (result.index === 0) {
        this.openEditor();
      } else if (result.index === 1) {
        this.setPhotoMenu();
      } else if (result.index === 2) {
        this.openQr();
      }
    }).catch((): void => {
      this.topMenuOpen = false;
    });
  }

  private stickerCtrl: CustomDialogController = new CustomDialogController({
    builder: StickerAvatarDialog({ onPick: (st: StickerItem): void => { this.onStickerPicked(st); } }),
    alignment: DialogAlignment.Bottom,
    autoCancel: true,
    customStyle: true
  });

  // 设置照片: camera / gallery / sticker.
  private setPhotoMenu(): void {
    if (this.profileLoading || this.profileError !== '' ||
      this.photoUploading || this.photoMenuOpen || this.openingEditor ||
      this.switchingToSettings || this.topMenuOpen) {
      return;
    }
    this.photoMenuOpen = true;
    promptAction.showActionMenu({
      title: $r('app.string.mp_set_photo_title'),
      buttons: [
        { text: $r('app.string.mp_take_photo'), color: '#3390EC' },
        { text: $r('app.string.mp_from_gallery'), color: '#3390EC' },
        { text: $r('app.string.mp_emoji_sticker'), color: '#3390EC' }
      ]
    }).then((r) => {
      this.photoMenuOpen = false;
      if (r.index === 0) {
        this.photoFromCamera();
      } else if (r.index === 1) {
        this.photoFromGallery();
      } else if (r.index === 2) {
        this.stickerCtrl.open();
      }
    }).catch((e: Object) => {
      this.photoMenuOpen = false;
      logE(`MyProfilePage.setPhotoMenu failed: ${JSON.stringify(e)}`);
    });
  }

  private async photoFromCamera(): Promise<void> {
    try {
      const profile: cameraPicker.PickerProfile = {
        cameraPosition: camera.CameraPosition.CAMERA_POSITION_FRONT
      };
      const res = await cameraPicker.pick(getContext(this) as common.Context,
        [cameraPicker.PickerMediaType.PHOTO], profile);
      if (res.resultCode === 0 && res.resultUri !== '') {
        const path = this.copyUriToCache(res.resultUri);
        if (path !== '') {
          this.uploadPhoto(path);
        }
      }
    } catch (e) {
      logE(`MyProfilePage.photoFromCamera failed: ${e}`);
    }
  }

  private photoFromGallery(): void {
    const picker = new photoAccessHelper.PhotoViewPicker();
    const opts = new photoAccessHelper.PhotoSelectOptions();
    opts.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    opts.maxSelectNumber = 1;
    picker.select(opts).then((res: photoAccessHelper.PhotoSelectResult) => {
      const uris = res.photoUris;
      if (uris.length > 0) {
        const path = this.copyUriToCache(uris[0]);
        if (path !== '') {
          this.uploadPhoto(path);
        }
      }
    }).catch((e: Object) => {
      logE(`MyProfilePage.photoFromGallery failed: ${JSON.stringify(e)}`);
    });
  }

  // Emoji/sticker avatar: static raster of the picked sticker (webp source
  // directly; animated formats fall back to their raster thumbnail).
  private onStickerPicked(st: StickerItem): void {
    this.stickerCtrl.close();
    if (st.format === 'webp') {
      const req: TdRequest = { '@type': 'downloadFile' };
      req['file_id'] = st.fileId;
      req['priority'] = 1;
      req['synchronous'] = true;
      getTdClient().send(req).then((f: TdObject) => {
        const local = f['local'] as TdObject | undefined;
        const path = local !== undefined ? ((local['path'] as string | undefined) ?? '') : '';
        if (path !== '') {
          this.uploadPhotoScaled(path);
        }
      }).catch((e: TdError) => {
        logE(`MyProfilePage sticker download failed: ${e.message}`);
      });
    } else if (st.thumbPath !== '') {
      this.uploadPhotoScaled(st.thumbPath);
    } else if (st.thumbFileId > 0) {
      // Thumbnail wasn't downloaded yet (cell showed the fallback character).
      const req: TdRequest = { '@type': 'downloadFile' };
      req['file_id'] = st.thumbFileId;
      req['priority'] = 1;
      req['synchronous'] = true;
      getTdClient().send(req).then((f: TdObject) => {
        const local = f['local'] as TdObject | undefined;
        const path = local !== undefined ? ((local['path'] as string | undefined) ?? '') : '';
        if (path !== '') {
          this.uploadPhotoScaled(path);
        }
      }).catch((e: TdError) => {
        logE(`MyProfilePage thumb download failed: ${e.message}`);
      });
    } else {
      promptAction.showToast({ message: $r('app.string.mp_emoji_unsupported'), duration: 2000 });
    }
  }

  // Telegram rejects avatars smaller than 512px (PHOTO_CROP_SIZE_SMALL) —
  // sticker thumbnails are ~128px, so upscale and re-encode before upload.
  private async upscaleForAvatar(path: string): Promise<string> {
    try {
      const src = image.createImageSource(path);
      const info = await src.getImageInfo();
      const w = info.size.width;
      const h = info.size.height;
      if (Math.min(w, h) >= 512) {
        src.release();
        return path;
      }
      const scale = 640 / Math.min(w, h);
      const pm = await src.createPixelMap({
        desiredSize: { width: Math.round(w * scale), height: Math.round(h * scale) }
      });
      const packer = image.createImagePacker();
      const buf = await packer.packing(pm, { format: 'image/jpeg', quality: 92 });
      packer.release();
      pm.release();
      src.release();
      const dest = `${(getContext(this) as common.UIAbilityContext).cacheDir}/avatar_up_${Date.now()}.jpg`;
      const f = fs.openSync(dest, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
      fs.writeSync(f.fd, buf);
      fs.closeSync(f);
      return dest;
    } catch (e) {
      logE(`MyProfilePage.upscaleForAvatar failed: ${e}`);
      return path;
    }
  }

  private async uploadPhotoScaled(path: string): Promise<void> {
    this.uploadPhoto(await this.upscaleForAvatar(path));
  }

  private uploadPhoto(path: string): void {
    if (path === '' || this.photoUploading) {
      return;
    }
    const sequence = ++this.photoUploadSequence;
    this.photoUploading = true;
    const inputFile: TdObject = { '@type': 'inputFileLocal' };
    inputFile['path'] = path;
    const photo: TdObject = { '@type': 'inputChatPhotoStatic' };
    photo['photo'] = inputFile;
    const req: TdRequest = { '@type': 'setProfilePhoto' };
    req['photo'] = photo;
    req['is_public'] = false;
    getTdClient().send(req).then(() => {
      if (sequence !== this.photoUploadSequence) {
        return;
      }
      this.photoUploading = false;
      promptAction.showToast({ message: $r('app.string.mp_photo_updated'), duration: 1500 });
      if (this.store !== null) {
        this.store.reload();
      }
    }).catch((e: TdError) => {
      if (sequence !== this.photoUploadSequence) {
        return;
      }
      this.photoUploading = false;
      logE(`MyProfilePage.setProfilePhoto failed: ${e.message}`);
      promptAction.showToast({ message: $r('app.string.mp_photo_failed'), duration: 2000 });
    });
  }

  private copyUriToCache(uri: string): string {
    try {
      const name = decodeURIComponent(uri.substring(uri.lastIndexOf('/') + 1));
      const dest = `${(getContext(this) as common.UIAbilityContext).cacheDir}/avatar_${Date.now()}_${name}`;
      const src = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      fs.copyFileSync(src.fd, dest);
      fs.closeSync(src);
      return dest;
    } catch (e) {
      logE(`MyProfilePage.copyUriToCache failed: ${e}`);
      return '';
    }
  }

  private refresh(): void {
    const s = this.store;
    if (s === null) {
      return;
    }
    this.name = s.name;
    this.initials = s.initials;
    this.avatarPath = s.avatarPath;
    this.avatarAnimPath = s.avatarAnimPath;
    this.statusEmojiPath = s.statusEmojiPath;
    this.statusEmojiFormat = s.statusEmojiFormat;
    this.statusText = s.statusText;
    this.phone = s.phone;
    this.usernames = s.usernames;
    this.birthday = s.birthday;
    const postStateChanged = this.storyItemsChanged(this.stories, s.stories) ||
      this.storyItemsChanged(this.archivedStories, s.archivedStories) ||
      this.storiesLoading !== s.storiesLoading ||
      this.storiesError !== s.storiesError ||
      this.archivedStoriesLoading !== s.archivedStoriesLoading ||
      this.archivedStoriesLoaded !== s.archivedStoriesLoaded ||
      this.archivedStoriesError !== s.archivedStoriesError;
    if (postStateChanged && this.active) {
      animateTo({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
        curve: Curve.EaseOut
      }, (): void => {
        this.applyPostSnapshot(s);
      });
    } else {
      this.applyPostSnapshot(s);
    }
    if (this.name !== '') {
      this.clearProfileLoadTimer();
      this.profileLoading = false;
      this.profileError = '';
    }
  }

  private storyItemsChanged(current: StoryItem[], next: StoryItem[]): boolean {
    return current.length !== next.length ||
      current.some((item: StoryItem, index: number): boolean => {
        const candidate = next[index];
        return candidate === undefined || item.id !== candidate.id ||
          item.thumbPath !== candidate.thumbPath;
      });
  }

  private applyPostSnapshot(store: ProfileStore): void {
    this.stories = store.stories;
    this.storiesLoading = store.storiesLoading;
    this.storiesError = store.storiesError;
    this.archivedStories = store.archivedStories;
    this.archivedStoriesLoading = store.archivedStoriesLoading;
    this.archivedStoriesLoaded = store.archivedStoriesLoaded;
    this.archivedStoriesError = store.archivedStoriesError;
  }

  private displayedStatusText(): string {
    if (this.appIsForeground) {
      return str('status_online');
    }
    return this.statusText !== '' ? this.statusText : str('settings_telegram_account');
  }

  private quickActionBusy(key: string): boolean {
    if (key === 'photo') {
      return this.photoUploading || this.photoMenuOpen;
    }
    if (key === 'edit') {
      return this.openingEditor;
    }
    return key === 'settings' && this.switchingToSettings;
  }

  private quickActionEnabled(key: string): boolean {
    if (this.photoUploading || this.photoMenuOpen || this.openingEditor ||
      this.switchingToSettings || this.topMenuOpen) {
      return false;
    }
    if (key === 'settings') {
      return true;
    }
    return !this.profileLoading && this.profileError === '';
  }

  private quickActionLabel(key: string, label: string): string {
    if (key === 'photo') {
      return this.photoUploading ? str('uploading') : (this.photoMenuOpen ? str('selecting') : label);
    }
    if (key === 'edit' && this.openingEditor) {
      return str('opening');
    }
    if (key === 'settings' && this.switchingToSettings) {
      return str('switching');
    }
    return label;
  }

  private infoValue(key: string): string {
    if (key === 'phone') {
      return this.phone !== '' ? `+${this.phone}` : '';
    }
    if (key === 'username') {
      return this.usernames.length > 0 ? `@${this.usernames[0]}` : '';
    }
    return key === 'birthday' ? this.birthday : '';
  }

  private infoTitle(key: string): string {
    if (key === 'phone') {
      return str('ct_phone');
    }
    if (key === 'username') {
      return str('ae_username');
    }
    return str('mp_birthday');
  }

  private infoHint(key: string): string {
    if (key === 'phone') {
      return str('mp_phone_sub');
    }
    if (key === 'username') {
      return str('mp_username_sub');
    }
    return str('mp_birthday_sub');
  }

  private infoIcon(key: string): string {
    if (key === 'phone') {
      return 'sys.symbol.phone_fill';
    }
    if (key === 'username') {
      return 'sys.symbol.at';
    }
    return 'sys.symbol.cake';
  }

  private infoColor(key: string): string {
    if (key === 'phone') {
      return '#34C759';
    }
    if (key === 'username') {
      return '#FF9500';
    }
    return '#3478F6';
  }

  private infoTint(key: string): string {
    if (key === 'phone') {
      return '#1834C759';
    }
    if (key === 'username') {
      return '#18FF9500';
    }
    return '#183478F6';
  }

  private infoItemCount(): number {
    let count = 0;
    if (this.phone !== '') { count++; }
    if (this.usernames.length > 0) { count++; }
    if (this.birthday !== '') { count++; }
    return count;
  }

  private copyInfo(key: string): void {
    const value = this.infoValue(key);
    if (value === '' || this.copyingInfoKey !== '' || this.openingEditor) {
      return;
    }
    this.pressedInfoKey = '';
    this.copyingInfoKey = key;
    this.copiedInfoKey = '';
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, value);
    pasteboard.getSystemPasteboard().setData(data).then((): void => {
      this.copyingInfoKey = '';
      this.copiedInfoKey = key;
      promptAction.showToast({
        message: str('mp_copied', this.infoTitle(key)),
        duration: 1200
      });
      if (this.copiedInfoTimer !== -1) {
        clearTimeout(this.copiedInfoTimer);
      }
      this.copiedInfoTimer = setTimeout((): void => {
        this.copiedInfoTimer = -1;
        if (this.copiedInfoKey === key) {
          this.copiedInfoKey = '';
        }
      }, 1000);
    }).catch((caught: Object): void => {
      this.copyingInfoKey = '';
      logE(`MyProfilePage.copyInfo(${key}) failed: ${JSON.stringify(caught)}`);
      promptAction.showToast({ message: $r('app.string.copy_failed_retry'), duration: 1500 });
    });
  }

  private selectPostTab(index: number): void {
    this.pressedPostTab = -1;
    if (index < 0 || index > 1 || this.postTab === index) {
      return;
    }
    if (index === 1 && this.store !== null &&
      !this.archivedStoriesLoaded && !this.archivedStoriesLoading) {
      this.store.loadArchivedStories();
    }
    animateTo({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 220),
      curve: Curve.EaseOut
    }, (): void => {
      this.postTab = index;
    });
  }

  private handlePostPan(offsetX: number): void {
    if (Math.abs(offsetX) < 42) {
      return;
    }
    this.selectPostTab(offsetX < 0 ? 1 : 0);
  }

  private postTabIcon(index: number): string {
    return index === 0 ? 'sys.symbol.camera' : 'sys.symbol.archivebox';
  }

  private postIndicatorWidth(): number {
    return Math.max(0, (this.postTabsWidth - 6) / 2);
  }

  private storyCell(): number {
    return (this.screenW - 4) / 3;
  }

  private formatStoryDuration(totalSeconds: number): string {
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    return `${minutes}:${`${seconds}`.padStart(2, '0')}`;
  }

  private storyPostUnavailableText(result: TdObject): string {
    const type = (result['@type'] as string | undefined) ?? '';
    if (type === 'canPostStoryResultPremiumNeeded') {
      return str('mp_story_needs_premium');
    }
    if (type === 'canPostStoryResultActiveStoryLimitExceeded') {
      return str('mp_story_limit');
    }
    if (type === 'canPostStoryResultWeeklyLimitExceeded' ||
      type === 'canPostStoryResultMonthlyLimitExceeded') {
      return str('mp_story_rate_limit');
    }
    return str('mp_story_unavailable');
  }

  private openStoryComposer(): void {
    if (this.profileLoading || this.profileError !== '' || this.myId === 0 ||
      this.storyPickerOpen || this.storyPosting || this.photoMenuOpen) {
      return;
    }
    this.storyPickerOpen = true;
    const continueWithChat = (chatId: number): void => {
      const canPost: TdRequest = { '@type': 'canPostStory' };
      canPost['chat_id'] = chatId;
      getTdClient().send(canPost).then((result: TdObject): void => {
        if (!this.storyPickerOpen) {
          return;
        }
        if (result['@type'] !== 'canPostStoryResultOk') {
          this.storyPickerOpen = false;
          promptAction.showToast({
            message: this.storyPostUnavailableText(result),
            duration: 2200
          });
          return;
        }
        promptAction.showActionMenu({
          title: $r('app.string.mp_add_story'),
          buttons: [
            { text: $r('app.string.mp_capture_photo'), color: '#3390EC' },
            { text: $r('app.string.mp_from_gallery'), color: '#3390EC' }
          ]
        }).then((choice): void => {
          this.storyPickerOpen = false;
          if (choice.index === 0) {
            this.storyFromCamera();
          } else if (choice.index === 1) {
            this.storyFromGallery();
          }
        }).catch((): void => {
          this.storyPickerOpen = false;
        });
      }).catch((error: TdError): void => {
        this.storyPickerOpen = false;
        logE(`MyProfilePage.canPostStory failed: ${error.message}`);
        promptAction.showToast({ message: $r('app.string.mp_add_story_failed'), duration: 1800 });
      });
    };
    if (this.storyChatId > 0) {
      continueWithChat(this.storyChatId);
      return;
    }
    const create: TdRequest = { '@type': 'createPrivateChat' };
    create['user_id'] = this.myId;
    create['force'] = false;
    getTdClient().send(create).then((chat: TdObject): void => {
      if (!this.storyPickerOpen) {
        return;
      }
      this.storyChatId = (chat['id'] as number | undefined) ?? this.myId;
      continueWithChat(this.storyChatId);
    }).catch((error: TdError): void => {
      this.storyPickerOpen = false;
      logE(`MyProfilePage.createStoryChat failed: ${error.message}`);
      promptAction.showToast({ message: $r('app.string.mp_add_story_failed'), duration: 1800 });
    });
  }

  private async storyFromCamera(): Promise<void> {
    try {
      const profile: cameraPicker.PickerProfile = {
        cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK
      };
      const result = await cameraPicker.pick(getContext(this) as common.Context,
        [cameraPicker.PickerMediaType.PHOTO], profile);
      if (result.resultCode === 0 && result.resultUri !== '') {
        const path = this.copyUriToCache(result.resultUri);
        if (path !== '') {
          this.confirmStoryPrivacy(path);
        }
      }
    } catch (error) {
      logE(`MyProfilePage.storyFromCamera failed: ${error}`);
      promptAction.showToast({ message: $r('app.string.mp_camera_failed'), duration: 1800 });
    }
  }

  private storyFromGallery(): void {
    const picker = new photoAccessHelper.PhotoViewPicker();
    const options = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = 1;
    picker.select(options).then((result: photoAccessHelper.PhotoSelectResult): void => {
      if (result.photoUris.length === 0) {
        return;
      }
      const path = this.copyUriToCache(result.photoUris[0]);
      if (path !== '') {
        this.confirmStoryPrivacy(path);
      }
    }).catch((error: Object): void => {
      logE(`MyProfilePage.storyFromGallery failed: ${JSON.stringify(error)}`);
      promptAction.showToast({ message: $r('app.string.mp_gallery_failed'), duration: 1800 });
    });
  }

  private confirmStoryPrivacy(sourcePath: string): void {
    if (this.storyPosting || this.storyPickerOpen) {
      return;
    }
    this.storyPickerOpen = true;
    promptAction.showActionMenu({
      title: $r('app.string.mp_story_privacy'),
      buttons: [
        { text: $r('app.string.privacy_everybody'), color: '#3390EC' },
        { text: $r('app.string.privacy_contacts'), color: '#3390EC' },
        { text: $r('app.string.mp_close_friends'), color: '#3390EC' }
      ]
    }).then((choice): void => {
      this.storyPickerOpen = false;
      if (choice.index === 0) {
        this.postPhotoStory(sourcePath, 'storyPrivacySettingsEveryone');
      } else if (choice.index === 1) {
        this.postPhotoStory(sourcePath, 'storyPrivacySettingsContacts');
      } else if (choice.index === 2) {
        this.postPhotoStory(sourcePath, 'storyPrivacySettingsCloseFriends');
      }
    }).catch((): void => {
      this.storyPickerOpen = false;
    });
  }

  private async prepareStoryPhoto(path: string): Promise<string> {
    try {
      const source = image.createImageSource(path);
      const info = await source.getImageInfo();
      const width = info.size.width;
      const height = info.size.height;
      if (width <= 0 || height <= 0) {
        source.release();
        return '';
      }
      const storyRatio = 9 / 16;
      let cropWidth = width;
      let cropHeight = height;
      let cropX = 0;
      let cropY = 0;
      if (width / height > storyRatio) {
        cropWidth = Math.max(1, Math.round(height * storyRatio));
        cropX = Math.max(0, Math.floor((width - cropWidth) / 2));
      } else {
        cropHeight = Math.max(1, Math.round(width / storyRatio));
        cropY = Math.max(0, Math.floor((height - cropHeight) / 2));
      }
      const pixelMap = await source.createPixelMap({
        desiredRegion: {
          x: cropX,
          y: cropY,
          size: { width: cropWidth, height: cropHeight }
        },
        desiredSize: { width: 1080, height: 1920 }
      });
      const packer = image.createImagePacker();
      const buffer = await packer.packing(pixelMap, { format: 'image/jpeg', quality: 92 });
      const destination =
        `${(getContext(this) as common.UIAbilityContext).cacheDir}/story_${Date.now()}.jpg`;
      const file = fs.openSync(destination, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
      fs.writeSync(file.fd, buffer);
      fs.closeSync(file);
      packer.release();
      pixelMap.release();
      source.release();
      return destination;
    } catch (error) {
      logE(`MyProfilePage.prepareStoryPhoto failed: ${error}`);
      return '';
    }
  }

  private async postPhotoStory(sourcePath: string, privacyType: string): Promise<void> {
    if (this.storyPosting || this.storyChatId <= 0) {
      return;
    }
    const sequence = ++this.storyUploadSequence;
    this.storyPosting = true;
    const path = await this.prepareStoryPhoto(sourcePath);
    if (sequence !== this.storyUploadSequence) {
      return;
    }
    if (path === '') {
      this.storyPosting = false;
      promptAction.showToast({ message: $r('app.string.mp_photo_process_failed'), duration: 1800 });
      return;
    }
    const inputFile: TdObject = { '@type': 'inputFileLocal' };
    inputFile['path'] = path;
    const content: TdObject = { '@type': 'inputStoryContentPhoto' };
    content['photo'] = inputFile;
    content['added_sticker_file_ids'] = [];
    const caption: TdObject = { '@type': 'formattedText' };
    caption['text'] = '';
    caption['entities'] = [];
    const request: TdRequest = { '@type': 'postStory' };
    request['chat_id'] = this.storyChatId;
    request['content'] = content;
    request['caption'] = caption;
    const privacy: TdObject = { '@type': privacyType };
    if (privacyType === 'storyPrivacySettingsEveryone' ||
      privacyType === 'storyPrivacySettingsContacts') {
      privacy['except_user_ids'] = [];
    }
    request['privacy_settings'] = privacy;
    request['album_ids'] = [];
    request['active_period'] = 24 * 60 * 60;
    request['is_posted_to_chat_page'] = true;
    request['protect_content'] = false;
    getTdClient().send(request).then((): void => {
      if (sequence !== this.storyUploadSequence) {
        return;
      }
      this.storyPosting = false;
      promptAction.showToast({ message: $r('app.string.mp_story_posted'), duration: 1500 });
      this.store?.reloadStories();
    }).catch((error: TdError): void => {
      if (sequence !== this.storyUploadSequence) {
        return;
      }
      this.storyPosting = false;
      logE(`MyProfilePage.postStory failed: ${error.message}`);
      promptAction.showToast({ message: $r('app.string.mp_story_post_failed'), duration: 2000 });
    });
  }

  private retryPostState(key: string): void {
    this.pressedPostStateAction = '';
    if (key === 'profile') {
      this.retryProfile();
      return;
    }
    const s = this.store;
    if (s === null) {
      this.retryProfile();
      return;
    }
    if (key === 'archive') {
      s.loadArchivedStories(true);
    } else {
      s.reloadStories();
    }
  }

  @Styles
  topActionNormalStyle() {
    .backgroundColor(CARD_BG)
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  topActionPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.72)
    .scale({ x: 0.92, y: 0.92 })
  }


  @Builder
  actionButton(symbol: string, label: string, key: string, accent: string, onTap: () => void) {
    Column({ space: 5 }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle({ width: 36, height: 36 })
          .fill(key === 'settings' ? '#147D69D9' : '#143478F6');
        if (this.quickActionBusy(key)) {
          LoadingProgress()
            .width(21)
            .height(21)
            .color(accent)
            .transition(TransitionEffect.OPACITY
              .combine(TransitionEffect.scale({ x: 0.7, y: 0.7 }))
              .animation({
                duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 140),
                curve: Curve.EaseOut
              }));
        } else {
          SymbolGlyph($r(symbol))
            .fontSize(20)
            .fontColor([accent])
            .scale({
              x: this.pressedQuickAction === key ? 0.84 : 1,
              y: this.pressedQuickAction === key ? 0.84 : 1
            })
            .animation({
              duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110),
              curve: Curve.EaseOut
            });
        }
      }
      .width(36)
      .height(36);
      Text(this.quickActionLabel(key, label))
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(accent);
    }
    .layoutWeight(1)
    .height(76)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.pressedQuickAction === key
      ? $r('app.color.surface_alt') : CARD_BG)
    .borderRadius(CARD_RADIUS)
    .border({ width: 0.5, color: $r('app.color.divider') })
    .shadow({
      radius: this.pressedQuickAction === key ? 1 : 5,
      color: this.pressedQuickAction === key ? '#0A000000' : '#14000000',
      offsetX: 0,
      offsetY: this.pressedQuickAction === key ? 0 : 2
    })
    .scale({
      x: this.pressedQuickAction === key ? 0.96 : 1,
      y: this.pressedQuickAction === key ? 0.96 : 1
    })
    .opacity(this.quickActionEnabled(key) || this.quickActionBusy(key) ? 1 : 0.46)
    .animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 120),
      curve: Curve.EaseOut
    })
    .enabled(this.quickActionEnabled(key))
    .accessibilityText(this.quickActionBusy(key)
      ? this.quickActionLabel(key, label) : label)
    .onTouch((event: TouchEvent): void => {
      if (event.type === TouchType.Down && this.quickActionEnabled(key)) {
        this.pressedQuickAction = key;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        if (this.pressedQuickAction === key) {
          this.pressedQuickAction = '';
        }
      }
    })
    .onClick((): void => {
      this.pressedQuickAction = '';
      if (this.quickActionEnabled(key)) {
        onTap();
      }
    });
  }

  @Builder
  infoRow(key: string) {
    Row({ space: 12 }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle({ width: 38, height: 38 })
          .fill(this.infoTint(key));
        SymbolGlyph($r(this.infoIcon(key)))
          .fontSize(18)
          .fontColor([this.infoColor(key)])
          .scale({
            x: this.pressedInfoKey === key ? 0.86 : 1,
            y: this.pressedInfoKey === key ? 0.86 : 1
          })
          .animation({
            duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110),
            curve: Curve.EaseOut
          });
      }
      .width(38)
      .height(38);
      Column({ space: 3 }) {
        Text(this.infoValue(key))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(`${this.infoTitle(key)} · ${this.infoHint(key)}`)
          .fontSize(12)
          .fontColor(COLOR_TEXT_SECONDARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);
      Stack({ alignContent: Alignment.Center }) {
        if (this.copyingInfoKey === key) {
          LoadingProgress()
            .width(18)
            .height(18)
            .color(COLOR_PRIMARY);
        } else if (this.copiedInfoKey === key) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(17)
            .fontColor(['#34C759'])
            .transition(TransitionEffect.OPACITY
              .combine(TransitionEffect.scale({ x: 0.7, y: 0.7 }))
              .animation({
                duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 150),
                curve: Curve.EaseOut
              }));
        } else {
          SymbolGlyph($r('sys.symbol.plus_square_on_square'))
            .fontSize(17)
            .fontColor([COLOR_TEXT_SECONDARY]);
        }
      }
      .width(34)
      .height(34)
      .borderRadius(17)
      .backgroundColor($r('app.color.surface_alt'));
    }
    .width('100%')
    .height(66)
    .padding({ left: 12, right: 10 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.pressedInfoKey === key
      ? $r('app.color.surface_alt') : Color.Transparent)
    .scale({
      x: this.pressedInfoKey === key ? 0.986 : 1,
      y: this.pressedInfoKey === key ? 0.98 : 1
    })
    .animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110),
      curve: Curve.EaseOut
    })
    .enabled(this.copyingInfoKey === '' && !this.openingEditor && !this.switchingToSettings)
    .accessibilityText(str('mp_info_a11y', this.infoTitle(key), this.infoValue(key)))
    .onTouch((event: TouchEvent): void => {
      if (event.type === TouchType.Down && this.copyingInfoKey === '') {
        this.pressedInfoKey = key;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        if (this.pressedInfoKey === key) {
          this.pressedInfoKey = '';
        }
      }
    })
    .onClick((): void => {
      this.pressedInfoKey = '';
      this.copyInfo(key);
    })
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: 5 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 170),
        curve: Curve.EaseOut
      }));
  }

  @Builder
  header() {
    // 二维码和 ⋮ 原来是浮在头像块上方的一行，现在搬进了标题栏（见
    // titleBarContent）——它们本来就是"页面级动作"，放在标题栏才是它们该在的
    // 地方，头像块也因此能一直顶到最上面。
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Stack({ alignContent: Alignment.Center }) {
          if (this.profileLoading) {
            Circle({ width: 100, height: 100 })
              .fill($r('app.color.surface_alt'));
            LoadingProgress()
              .width(28)
              .height(28)
              .color(COLOR_PRIMARY);
          } else {
            AvatarView({
              avatarPath: this.avatarPath, initials: this.initials,
              colorSeed: this.myId, avatarSize: 100,
              animPath: this.avatarAnimPath
            });
          }
          if (this.photoUploading) {
            Circle({ width: 100, height: 100 })
              .fill('#66000000');
            LoadingProgress()
              .width(30)
              .height(30)
              .color(Color.White);
          }
        }
        .width(108)
        .height(108)
        .padding(4)
        .backgroundColor(CARD_BG)
        .borderRadius(54)
        .shadow({
          radius: this.avatarPressed ? 5 : 12,
          color: this.avatarPressed ? '#1C000000' : '#28000000',
          offsetX: 0,
          offsetY: this.avatarPressed ? 1 : 4
        });

        if (!this.profileLoading && !this.photoUploading) {
          Row() {
            SymbolGlyph(this.profileError !== ''
              ? $r('sys.symbol.exclamationmark_circle')
              : $r('sys.symbol.camera'))
              .fontSize(this.profileError !== '' ? 16 : 15)
              .fontColor([Color.White]);
          }
          .width(31)
          .height(31)
          .borderRadius(15.5)
          .backgroundColor(this.profileError !== '' ? '#E64646' : COLOR_PRIMARY)
          .border({ width: 2.5, color: PAGE_BG })
          .justifyContent(FlexAlign.Center)
          .hitTestBehavior(HitTestMode.None)
          .transition(TransitionEffect.OPACITY
            .combine(TransitionEffect.scale({ x: 0.7, y: 0.7 }))
            .animation({
              duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
              curve: Curve.EaseOut
            }));
        }
      }
      .width(112)
      .height(112)
      .scale({
        x: this.avatarPressed ? 0.95 : 1,
        y: this.avatarPressed ? 0.95 : 1
      })
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 120),
        curve: Curve.EaseOut
      })
      .enabled(!this.profileLoading && !this.photoUploading && !this.photoMenuOpen &&
        !this.openingEditor && !this.switchingToSettings)
      .accessibilityText(this.profileError !== ''
        ? $r('app.string.mp_load_failed_tap')
        : $r('app.string.mp_photo_a11y'))
      .onTouch((event: TouchEvent): void => {
        if (event.type === TouchType.Down) {
          this.avatarPressed = true;
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.avatarPressed = false;
        }
      })
      .onClick((): void => {
        this.avatarPressed = false;
        if (this.profileError !== '') {
          this.retryProfile();
        } else {
          this.setPhotoMenu();
        }
      });

      Row({ space: 5 }) {
        Text(this.profileLoading
          ? $r('app.string.mp_loading')
          : (this.profileError !== '' ? $r('app.string.tab_profile') : (this.name !== '' ? this.name : $r('app.string.settings_telegram_account'))))
          .fontSize(20).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .flexShrink(1);
        if (!this.profileLoading && this.profileError === '' && this.statusEmojiPath !== '') {
          this.statusEmoji();
        }
      }
      .alignItems(VerticalAlign.Center)
      .constraintSize({ maxWidth: '86%' });

      Row({ space: 6 }) {
        if (this.profileLoading) {
          LoadingProgress().width(13).height(13).color(COLOR_PRIMARY);
        } else {
          Circle({ width: 7, height: 7 })
            .fill(this.profileError !== ''
              ? '#E64646'
              : (this.displayedStatusText() === str('status_online') ? '#34C759' : COLOR_TEXT_SECONDARY));
        }
        Text(this.profileLoading
          ? $r('app.string.mp_syncing')
          : (this.profileError !== ''
            ? $r('app.string.mp_tap_photo_reload')
            : this.displayedStatusText()))
          .fontSize(13)
          .fontColor(this.profileError !== '' ? '#E64646' : COLOR_TEXT_SECONDARY);
      }
      .height(22)
      .alignItems(VerticalAlign.Center);
    }
    .width('100%')
    .padding({ top: this.topSafe + 8 })
    .opacity(this.headerVisible && this.active ? 1 : 0)
    .translate({ y: this.headerVisible && this.active ? 0 : -8 })
    .animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 220),
      curve: Curve.EaseOut
    });
  }

  @Builder
  actionsRow() {
    Row({ space: 8 }) {
      this.actionButton(
        'sys.symbol.camera', str('mp_set_photo_title'), 'photo', '#3478F6',
        (): void => { this.setPhotoMenu(); }
      );
      this.actionButton(
        'sys.symbol.pencil_line', str('mp_edit_info'), 'edit', '#3478F6',
        (): void => { this.openEditor(); }
      );
      this.actionButton(
        'sys.symbol.gearshape', str('settings_title'), 'settings', '#7D69D9',
        (): void => { this.openSettings(); }
      );
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 14 })
    .opacity(this.active ? 1 : 0)
    .translate({ y: this.active ? 0 : 8 })
    .animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 240),
      curve: Curve.EaseOut
    });
  }

  @Builder
  infoCard() {
    Column({ space: 5 }) {
      Row() {
        Text($r('app.string.mp_account_info'))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_SECONDARY)
          .layoutWeight(1);
        Text(this.profileLoading
          ? $r('app.string.syncing_short')
          : (this.profileError !== '' ? $r('app.string.unavailable') : plural('mp_item_count', this.infoItemCount(), this.infoItemCount())))
          .fontSize(12)
          .fontColor(this.profileError !== '' ? '#E64646' : COLOR_TEXT_SECONDARY);
      }
      .width('100%')
      .height(26)
      .padding({ left: 4, right: 4 });

      Column() {
        if (this.profileLoading) {
          Row({ space: 12 }) {
            Circle({ width: 38, height: 38 }).fill($r('app.color.surface_alt'));
            Column({ space: 8 }) {
              Rect({ width: 132, height: 12, radius: 6 })
                .fill($r('app.color.surface_alt'));
              Rect({ width: 196, height: 9, radius: 4.5 })
                .fill($r('app.color.surface_alt'));
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1);
            LoadingProgress().width(20).height(20).color(COLOR_PRIMARY);
          }
          .width('100%')
          .height(76)
          .padding({ left: 12, right: 14 })
          .alignItems(VerticalAlign.Center);
        } else if (this.profileError !== '') {
          Row({ space: 12 }) {
            Stack({ alignContent: Alignment.Center }) {
              Circle({ width: 38, height: 38 }).fill('#18E64646');
              SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
                .fontSize(19)
                .fontColor(['#E64646']);
            }
            Column({ space: 3 }) {
              Text($r('app.string.mp_account_info_unavailable'))
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(COLOR_TEXT_PRIMARY);
              Text($r('app.string.tap_to_reload'))
                .fontSize(12)
                .fontColor(COLOR_PRIMARY);
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1);
            SymbolGlyph($r('sys.symbol.arrow_clockwise'))
              .fontSize(17)
              .fontColor([COLOR_PRIMARY]);
          }
          .width('100%')
          .height(76)
          .padding({ left: 12, right: 14 })
          .alignItems(VerticalAlign.Center)
          .accessibilityText($r('app.string.mp_account_info_failed'))
          .onClick((): void => { this.retryProfile(); });
        } else if (this.infoItemCount() === 0) {
          Row({ space: 12 }) {
            Stack({ alignContent: Alignment.Center }) {
              Circle({ width: 38, height: 38 }).fill('#143478F6');
              SymbolGlyph($r('sys.symbol.person_fill'))
                .fontSize(18)
                .fontColor([COLOR_PRIMARY]);
            }
            Column({ space: 3 }) {
              Text($r('app.string.mp_account_info_empty'))
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(COLOR_TEXT_PRIMARY);
              Text($r('app.string.mp_account_info_empty_sub'))
                .fontSize(12)
                .fontColor(COLOR_TEXT_SECONDARY);
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1);
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16)
              .fontColor([COLOR_TEXT_SECONDARY]);
          }
          .width('100%')
          .height(76)
          .padding({ left: 12, right: 14 })
          .alignItems(VerticalAlign.Center)
          .accessibilityText($r('app.string.mp_account_info_empty_a11y'))
          .onClick((): void => { this.openEditor(); });
        } else {
          if (this.phone !== '') {
            this.infoRow('phone');
          }
          if (this.usernames.length > 0) {
            if (this.phone !== '') {
              Divider()
                .color($r('app.color.divider'))
                .strokeWidth(0.7)
                .margin({ left: 62, right: 10 });
            }
            this.infoRow('username');
          }
          if (this.birthday !== '') {
            if (this.phone !== '' || this.usernames.length > 0) {
              Divider()
                .color($r('app.color.divider'))
                .strokeWidth(0.7)
                .margin({ left: 62, right: 10 });
            }
            this.infoRow('birthday');
          }
        }
      }
      .width('100%')
      .backgroundColor(CARD_BG)
      .borderRadius(CARD_RADIUS)
      .border({ width: 0.5, color: $r('app.color.divider') })
      .shadow({ radius: 5, color: '#12000000', offsetX: 0, offsetY: 2 })
      .clip(true);
    }
    .margin({ left: 12, right: 12, top: 12 })
    .opacity(this.active ? 1 : 0)
    .translate({ y: this.active ? 0 : 10 })
    .animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 280),
      curve: Curve.EaseOut
    });
  }

  @Builder
  postTabPill(label: string, index: number) {
    Row({ space: 6 }) {
      if (index === 0 && (this.storyPickerOpen || this.storyPosting)) {
        LoadingProgress()
          .width(16)
          .height(16)
          .color(COLOR_PRIMARY);
      } else {
        SymbolGlyph($r(this.postTabIcon(index)))
          .fontSize(16)
          .fontColor([this.postTab === index ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY])
          .scale({
            x: this.pressedPostTab === index ? 0.9 : 1,
            y: this.pressedPostTab === index ? 0.9 : 1
          })
          .animation({
            duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110),
            curve: Curve.EaseOut
          });
      }
      Text(label)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.postTab === index ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY)
        .maxLines(1);
    }
    .layoutWeight(1)
    .height(40)
    .justifyContent(FlexAlign.Center)
    .borderRadius(13)
    .backgroundColor(this.pressedPostTab === index
      ? $r('app.color.selected_pill') : Color.Transparent)
    .scale({
      x: this.pressedPostTab === index ? 0.975 : 1,
      y: this.pressedPostTab === index ? 0.96 : 1
    })
    .animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 120),
      curve: Curve.EaseOut
    })
    .accessibilityText(str('a11y_option_state', label, this.postTab === index ? str('a11y_selected') : ''))
    .onTouch((event: TouchEvent): void => {
      if (event.type === TouchType.Down) {
        this.pressedPostTab = index;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        if (this.pressedPostTab === index) {
          this.pressedPostTab = -1;
        }
      }
    })
    .onClick((): void => {
      if (index === 0 && this.postTab === 0) {
        this.openStoryComposer();
      } else {
        this.selectPostTab(index);
      }
    });
  }

  @Builder
  postsTabs() {
    Column() {
      Stack({ alignContent: Alignment.Start }) {
        Row()
          .width(this.postIndicatorWidth())
          .height(40)
          .borderRadius(13)
          .backgroundColor(CARD_BG)
          .border({ width: 0.5, color: $r('app.color.divider') })
          .shadow({ radius: 4, color: '#16000000', offsetX: 0, offsetY: 2 })
          .position({ x: 3, y: 3 })
          .translate({
            x: this.postTab === 0 ? 0 : this.postIndicatorWidth()
          })
          .opacity(this.postTabsWidth > 0 ? 1 : 0)
          .animation({
            duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 220),
            curve: Curve.EaseOut
          });

        Row() {
          this.postTabPill(str('mp_stories'), 0);
          this.postTabPill(str('mp_archived_stories'), 1);
        }
        .width('100%')
        .height(46)
        .padding(3)
        .alignItems(VerticalAlign.Center);
      }
      .width('100%')
      .height(46)
      .backgroundColor($r('app.color.surface_alt'))
      .borderRadius(16)
      .border({ width: 0.5, color: $r('app.color.divider') })
      .onAreaChange((_old: Area, area: Area): void => {
        const width = area.width as number;
        if (width > 0 && width !== this.postTabsWidth) {
          this.postTabsWidth = width;
        }
      });
    }
    .width('100%')
    .padding({ left: 12, right: 12 })
    .margin({ top: 16, bottom: 8 })
    .opacity(this.active ? 1 : 0)
    .translate({ y: this.active ? 0 : 8 })
    .animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 300),
      curve: Curve.EaseOut
    });
  }

  @Builder
  postLoadingState(enterX: number) {
    Column({ space: 12 }) {
      Row({ space: 3 }) {
        Rect({ height: 128, radius: 10 })
          .fill($r('app.color.surface_alt'))
          .layoutWeight(1);
        Rect({ height: 128, radius: 10 })
          .fill($r('app.color.surface_alt'))
          .layoutWeight(1);
        Rect({ height: 128, radius: 10 })
          .fill($r('app.color.surface_alt'))
          .layoutWeight(1);
      }
      .width('100%')
      .padding({ left: 2, right: 2 });
      Row({ space: 7 }) {
        LoadingProgress()
          .width(16)
          .height(16)
          .color(COLOR_PRIMARY);
        Text(this.postTab === 0 ? $r('app.string.mp_syncing_stories') : $r('app.string.mp_loading_archived'))
          .fontSize(13)
          .fontColor(COLOR_TEXT_SECONDARY);
      }
      .height(26)
      .alignItems(VerticalAlign.Center);
    }
    .width('100%')
    .padding({ top: 8, bottom: 30 })
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ x: enterX }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
        curve: Curve.EaseOut
      }));
  }

  @Builder
  postErrorState(title: string, detail: string, key: string, enterX: number) {
    Column({ space: 10 }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle({ width: 58, height: 58 })
          .fill('#18E64646');
        SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
          .fontSize(27)
          .fontColor(['#E64646']);
      }
      Text(title)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLOR_TEXT_PRIMARY);
      Text(detail)
        .fontSize(13)
        .fontColor(COLOR_TEXT_SECONDARY)
        .textAlign(TextAlign.Center)
        .constraintSize({ maxWidth: '78%' })
        .maxLines(2);
      Row({ space: 7 }) {
        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(17)
          .fontColor([COLOR_PRIMARY]);
        Text($r('app.string.settings_reload'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_PRIMARY);
      }
      .height(40)
      .padding({ left: 18, right: 18 })
      .borderRadius(20)
      .backgroundColor(this.pressedPostStateAction === key
        ? $r('app.color.selected_pill') : $r('app.color.surface_alt'))
      .scale({
        x: this.pressedPostStateAction === key ? 0.96 : 1,
        y: this.pressedPostStateAction === key ? 0.96 : 1
      })
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110),
        curve: Curve.EaseOut
      })
      .accessibilityText(str('mp_reload_a11y', title))
      .onTouch((event: TouchEvent): void => {
        if (event.type === TouchType.Down) {
          this.pressedPostStateAction = key;
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          if (this.pressedPostStateAction === key) {
            this.pressedPostStateAction = '';
          }
        }
      })
      .onClick((): void => {
        this.retryPostState(key);
      });
    }
    .width('100%')
    .padding({ top: 30, bottom: 38 })
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ x: enterX }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
        curve: Curve.EaseOut
      }));
  }

  @Builder
  emptyPosts(title: string, detail: string, archived: boolean, enterX: number) {
    Column({ space: 12 }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle({ width: 62, height: 62 })
          .fill(archived ? '#167D69D9' : '#163478F6');
        SymbolGlyph(archived
          ? $r('sys.symbol.archivebox')
          : $r('sys.symbol.camera'))
          .fontSize(28)
          .fontColor([archived ? '#7D69D9' : COLOR_PRIMARY]);
      }
      .transition(TransitionEffect.OPACITY
        .combine(TransitionEffect.scale({ x: 0.78, y: 0.78 }))
        .animation({
          duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 220),
          curve: Curve.EaseOut
        }));
      Text(title).fontSize(17).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
      Text(detail)
        .fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
        .textAlign(TextAlign.Center).constraintSize({ maxWidth: '80%' });
      if (!archived) {
        Row({ space: 7 }) {
          if (this.storyPickerOpen || this.storyPosting) {
            LoadingProgress().width(17).height(17).color(COLOR_PRIMARY);
          } else {
            SymbolGlyph($r('sys.symbol.plus'))
              .fontSize(17)
              .fontColor([COLOR_PRIMARY]);
          }
          Text(this.storyPosting ? $r('app.string.mp_posting') : $r('app.string.mp_add_story'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLOR_PRIMARY);
        }
        .height(40)
        .padding({ left: 18, right: 18 })
        .borderRadius(20)
        .backgroundColor($r('app.color.selected_pill'))
        .accessibilityText($r('app.string.mp_add_story'))
        .onClick((): void => {
          this.openStoryComposer();
        });
      }
    }
    .width('100%')
    .padding({ top: 30, bottom: 38 })
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ x: enterX }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
        curve: Curve.EaseOut
      }));
  }

  @Builder
  storyGrid(items: StoryItem[], enterX: number) {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(items, (item: StoryItem) => {
        Stack({ alignContent: Alignment.BottomStart }) {
          if (item.thumbPath !== '') {
            Image(item.thumbPath.startsWith('/') ? `file://${item.thumbPath}` : item.thumbPath).draggable(false)
              .width(this.storyCell())
              .height(this.storyCell() * 1.33)
              .objectFit(ImageFit.Cover)
              .transition(TransitionEffect.OPACITY.animation({
                duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 160),
                curve: Curve.EaseOut
              }));
          } else {
            Stack({ alignContent: Alignment.Center }) {
              Column()
                .width(this.storyCell())
                .height(this.storyCell() * 1.33)
                .backgroundColor($r('app.color.surface_alt'));
              SymbolGlyph(item.isVideo
                ? $r('sys.symbol.video')
                : $r('sys.symbol.camera'))
                .fontSize(23)
                .fontColor([COLOR_TEXT_SECONDARY])
                .opacity(0.55);
            }
          }
          if (item.isVideo) {
            Text(`▶ ${this.formatStoryDuration(item.duration)}`)
              .fontSize(11)
              .fontColor(Color.White)
              .backgroundColor('#80000000')
              .borderRadius(5)
              .padding({ left: 5, right: 5, top: 2, bottom: 2 })
              .margin({ left: 6, bottom: 6 });
          }
        }
        .width(this.storyCell())
        .height(this.storyCell() * 1.33)
        .margin({ right: 1, bottom: 1 })
        .clip(true);
      }, (item: StoryItem): string => `my_story_${this.postTab}_${item.id}_${item.thumbPath}`);
    }
    .width('100%')
    .padding({ top: 2, bottom: 28 })
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ x: enterX }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 190),
        curve: Curve.EaseOut
      }));
  }

  @Builder
  postsContent() {
    Stack() {
      if (this.profileLoading) {
        this.postLoadingState(this.postTab === 0 ? -12 : 12);
      } else if (this.profileError !== '') {
        this.postErrorState(
          str('mp_load_failed'),
          this.profileError,
          'profile',
          this.postTab === 0 ? -12 : 12
        );
      } else if (this.postTab === 0) {
        if (this.storiesLoading) {
          this.postLoadingState(-12);
        } else if (this.storiesError !== '') {
          this.postErrorState(str('mp_stories_failed'), this.storiesError, 'stories', -12);
        } else if (this.stories.length === 0) {
          this.emptyPosts(
            str('mp_no_stories'),
            str('mp_no_stories_sub'),
            false,
            -12
          );
        } else {
          this.storyGrid(this.stories, -12);
        }
      } else {
        if (this.archivedStoriesError !== '') {
          this.postErrorState(str('mp_archived_failed'), this.archivedStoriesError, 'archive', 12);
        } else if (this.archivedStoriesLoading || !this.archivedStoriesLoaded) {
          this.postLoadingState(12);
        } else if (this.archivedStories.length === 0) {
          this.emptyPosts(
            str('mp_no_archived'),
            str('mp_no_archived_sub'),
            true,
            12
          );
        } else {
          this.storyGrid(this.archivedStories, 12);
        }
      }
    }
    .width('100%')
    .constraintSize({ minHeight: 210 });
  }

  @Builder
  postsSection() {
    Column() {
      this.postsTabs();
      this.postsContent();
    }
    .width('100%')
    .priorityGesture(
      PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 12 })
        .onActionEnd((event: GestureEvent): void => {
          this.handlePostPan(event.offsetX);
        })
    );
  }

  // Premium emoji status beside the name (animated custom emoji).
  @Builder
  statusEmoji() {
    if (this.statusEmojiFormat === 'tgs') {
      TgsStickerView({
        tgsPath: this.statusEmojiPath, boxWidth: 24, boxHeight: 24, powerCategory: 'emojiStatus'
      });
    } else if (this.statusEmojiFormat === 'webm') {
      WebmStickerView({
        webmPath: this.statusEmojiPath, boxWidth: 24, boxHeight: 24, powerCategory: 'emojiStatus'
      });
    } else {
      Image(`file://${this.statusEmojiPath}`).draggable(false).width(24).height(24).objectFit(ImageFit.Contain);
    }
  }

  // 标题栏内容：大标题 + 右上角二维码与 ⋮。
  //
  // ⋮ 走的是 promptAction.showActionMenu（系统动作面板），不是 bindMenu，
  // 所以不需要联系人页那种锚点，action 里直接调即可。
  private titleBarContent(): TitleBarContentOptions {
    const qrIcon: HdsNavigationIconOptions = {
      icon: $r('sys.symbol.qrcode'),
      label: str('mp_show_profile_qr'),
      action: (): void => { this.openQr(); }
    };
    const moreIcon: HdsNavigationIconOptions = {
      icon: $r('sys.symbol.more'),
      label: str('mp_more_actions'),
      action: (): void => { this.showTopMenu(); }
    };
    return {
      title: { mainTitle: $r('app.string.tab_profile') },
      menu: {
        value: [
          { content: qrIcon } as HdsNavigationMenuItemOptions,
          { content: moreIcon } as HdsNavigationMenuItemOptions
        ]
      }
    };
  }

  build() {
    HdsNavigation() {
      Scroll(this.profileScroller) {
        Column() {
          this.header();
          this.actionsRow();
          this.infoCard();
          this.postsSection();
        }
        .width('100%')
        .padding({ bottom: this.bottomSafe + 88 });
      }
      .width('100%')
      .align(Alignment.Top)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .scrollBar(BarState.Off)
      // 不裁剪，头像块才能穿到标题栏底下——渐变模糊模糊的正是这部分。
      .clip(false);
    }
    .titleBar({
      // 两个都要，各管一头：
      //
      //   avoidLayoutSafeArea     标题栏**自己**避让系统安全区
      //   enableComponentSafeArea 标题栏成为**内容区**的安全区，内容避让它
      //
      // 官方示例里只有后者，因为那是个普通非全屏窗口。**本应用整体是全屏沉浸
      // 布局**（EntryAbility 调了 setWindowLayoutFullScreen(true)），页面的布局区
      // 本来就覆盖状态栏——这也是全应用每个页面都要手动 padding(topSafe) 的原因。
      // 所以这里必须自己避让，少了它标题栏就顶进状态栏（真机两次实测）。
      //
      // 但**不要**再在 HdsNavigation 根上加 expandSafeArea：那会把标题栏往状态栏
      // 里推，和这一行正好对着干，两者抵消之后渐变模糊的合成也跟着废掉。状态栏
      // 那条的底色由 HdsNavigation 自己的 backgroundColor 铺——全屏布局下它本来
      // 就盖到那儿。
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: true,
      style: titleBarStyle(PAGE_BG),
      content: this.titleBarContent()
    })
    // 一级页签，没有返回键。
    .hideBackButton(true)
    // 强制单栏：HdsNavigation 在宽屏（平板/横屏）会自动进分栏模式，我们只拿
    // 它当标题栏容器、不用 NavDestination——分栏的结果是整页内容挤进左列、
    // 右边一片空白（平板用户报"没法用了"）。
    .mode(NavigationMode.Stack)
    .titleMode(HdsNavigationTitleMode.FREE)
    .bindToScrollable([this.profileScroller])
    .width('100%').height('100%')
    .backgroundColor(PAGE_BG);
  }
}


// Bottom sheet holding the sticker picker for the emoji-avatar option.
@CustomDialog
struct StickerAvatarDialog {
  // 材质档位（厚度/光感）改变时重绘。overlayMaterial 是 util，订阅不了
  // AppStorage，只能由调用方订阅，同 LANGUAGE_EPOCH 的做法。
  @StorageProp(MATERIAL_EPOCH) private materialEpoch: number = 0;
  controller?: CustomDialogController;
  onPick: (s: StickerItem) => void = (): void => {};

  build() {
    Column() {
      // Avatar builder mode: custom-emoji library + trending packs (official-style).
      StickerPicker({
        stickerType: 'custom_emoji',
        includeTrending: true,
        onPick: (s: StickerItem): void => { this.onPick(s); }
      });
    }
    .width('100%').height(400)
    .backgroundColor(overlayGlassFill('dialog', $r('app.color.surface')))
    .borderRadius({ topLeft: 16, topRight: 16 })
    .clip(true)
    .backdropBlur(overlayBackdropBlur('dialog'))
    .attributeModifier(materialModifier('dialog'));
  }
}
