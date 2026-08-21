import { TdClient } from '../tdkit/TdClient';
import { TdError, TdObject } from '../tdkit/TdTypes';
import {
  ArchiveChatSettings, NewChatPrivacySettings, PrivacyValue,
  getAccountTtlDays, getArchiveSettings, getAutoDeleteSeconds, getBlockedCount,
  getBoolOption, getConnectedWebsiteCount, getNewChatPrivacy, getPasswordState,
  getPrivacy, getReadDatePrivacy, getSessionCount, parsePrivacyRules
} from './PrivacyApi';
import { str } from '../util/strings';
import { logW } from '../util/log';

export type PrivacyLoadState = 'loading' | 'ready' | 'error';

type Listener = () => void;

export const OPT_DISABLE_TOP_CHATS: string = 'disable_top_chats';
export const OPT_CAN_ARCHIVE_UNKNOWN: string = 'can_archive_and_mute_new_chats_from_unknown_users';
export const OPT_CAN_SET_NEW_CHAT_PRIVACY: string = 'can_set_new_chat_privacy_settings';
export const OPT_CAN_IGNORE_SENSITIVE: string = 'can_ignore_sensitive_content_restrictions';
export const OPT_IGNORE_SENSITIVE: string = 'ignore_sensitive_content_restrictions';
export const OPT_IS_PREMIUM: string = 'is_premium';

export class PrivacyStore {
  private client: TdClient;
  private settings: string[];
  private listeners: Listener[] = [];
  private unsubs: Array<() => void> = [];
  private sequence: number = 0;
  private active: boolean = false;

  loadState: PrivacyLoadState = 'loading';
  refreshing: boolean = false;
  syncError: string = '';
  rules: Map<string, PrivacyValue> = new Map();
  passwordState: TdObject | null = null;
  autoDeleteSeconds: number = -1;
  blockedCount: number = -1;
  sessionCount: number = -1;
  websiteCount: number = -1;
  accountTtlDays: number = -1;
  archiveSettings: ArchiveChatSettings | null = null;
  readDate: boolean | null = null;
  newChatPrivacy: NewChatPrivacySettings | null = null;
  suggestFrequent: boolean | null = null;
  canArchiveUnknown: boolean = false;
  canSetNewChatPrivacy: boolean = false;
  canIgnoreSensitive: boolean = false;
  ignoreSensitive: boolean | null = null;
  isPremium: boolean = false;

  constructor(client: TdClient, settings: string[]) {
    this.client = client;
    this.settings = settings.slice();
  }

  subscribe(listener: Listener): () => void {
    this.listeners = [...this.listeners, listener];
    listener();
    return (): void => {
      this.listeners = this.listeners.filter((item: Listener): boolean => item !== listener);
    };
  }

  private notify(): void {
    for (const listener of this.listeners) { listener(); }
  }

  open(): void {
    if (this.active) { return; }
    this.active = true;
    this.unsubs.push(this.client.onUpdate('updateUserPrivacySettingRules', (update: TdObject): void => {
      const setting = update['setting'] as TdObject | undefined;
      const type = setting !== undefined ? ((setting['@type'] as string | undefined) ?? '') : '';
      if (type === '' || this.settings.indexOf(type) < 0) { return; }
      const rulesObject = update['rules'] as TdObject | undefined;
      const rules = rulesObject !== undefined
        ? ((rulesObject['rules'] as TdObject[] | undefined) ?? []) : [];
      const next = new Map(this.rules);
      next.set(type, parsePrivacyRules(rules));
      this.rules = next;
      this.notify();
    }));
    this.unsubs.push(this.client.onUpdate('updateOption', (update: TdObject): void => {
      const name = (update['name'] as string | undefined) ?? '';
      const valueObject = update['value'] as TdObject | undefined;
      const value = valueObject !== undefined
        ? ((valueObject['value'] as boolean | undefined) ?? false) : false;
      if (name === OPT_DISABLE_TOP_CHATS) { this.suggestFrequent = !value; }
      else if (name === OPT_CAN_ARCHIVE_UNKNOWN) { this.canArchiveUnknown = value; }
      else if (name === OPT_CAN_SET_NEW_CHAT_PRIVACY) { this.canSetNewChatPrivacy = value; }
      else if (name === OPT_CAN_IGNORE_SENSITIVE) { this.canIgnoreSensitive = value; }
      else if (name === OPT_IGNORE_SENSITIVE) { this.ignoreSensitive = value; }
      else if (name === OPT_IS_PREMIUM) { this.isPremium = value; }
      else { return; }
      this.notify();
    }));
    this.load(false);
  }

  close(): void {
    this.active = false;
    this.sequence++;
    for (const unsubscribe of this.unsubs) { unsubscribe(); }
    this.unsubs = [];
    this.listeners = [];
  }

  refresh(): void {
    if (!this.active || this.refreshing) { return; }
    this.load(true);
  }

  private guarded<T>(
    work: Promise<T>, sequence: number, apply: (value: T) => void, label: string
  ): Promise<boolean> {
    return work.then((value: T): boolean => {
      if (!this.active || sequence !== this.sequence) { return false; }
      apply(value);
      return true;
    }).catch((caught: TdError): boolean => {
      logW(`PrivacyStore.${label} failed: ${caught.message}`);
      return false;
    });
  }

  private load(refresh: boolean): void {
    const sequence = ++this.sequence;
    if (refresh) { this.refreshing = true; }
    else { this.loadState = 'loading'; }
    this.syncError = '';
    this.notify();

    const tasks: Promise<boolean>[] = [];
    tasks.push(this.guarded(getPasswordState(this.client), sequence,
      (value: TdObject): void => { this.passwordState = value; }, 'password'));
    tasks.push(this.guarded(getAutoDeleteSeconds(this.client), sequence,
      (value: number): void => { this.autoDeleteSeconds = value; }, 'autoDelete'));
    tasks.push(this.guarded(getBlockedCount(this.client), sequence,
      (value: number): void => { this.blockedCount = value; }, 'blocked'));
    tasks.push(this.guarded(getSessionCount(this.client), sequence,
      (value: number): void => { this.sessionCount = value; }, 'sessions'));
    tasks.push(this.guarded(getConnectedWebsiteCount(this.client), sequence,
      (value: number): void => { this.websiteCount = value; }, 'websites'));
    tasks.push(this.guarded(getAccountTtlDays(this.client), sequence,
      (value: number): void => { this.accountTtlDays = value; }, 'accountTtl'));
    tasks.push(this.guarded(getArchiveSettings(this.client), sequence,
      (value: ArchiveChatSettings): void => { this.archiveSettings = value; }, 'archive'));
    tasks.push(this.guarded(getReadDatePrivacy(this.client), sequence,
      (value: boolean): void => { this.readDate = value; }, 'readDate'));
    tasks.push(this.guarded(getNewChatPrivacy(this.client), sequence,
      (value: NewChatPrivacySettings): void => { this.newChatPrivacy = value; }, 'newChat'));
    tasks.push(this.guarded(getBoolOption(OPT_DISABLE_TOP_CHATS, this.client), sequence,
      (value: boolean): void => { this.suggestFrequent = !value; }, 'topChats'));
    tasks.push(this.guarded(getBoolOption(OPT_CAN_ARCHIVE_UNKNOWN, this.client), sequence,
      (value: boolean): void => { this.canArchiveUnknown = value; }, 'canArchive'));
    tasks.push(this.guarded(getBoolOption(OPT_CAN_SET_NEW_CHAT_PRIVACY, this.client), sequence,
      (value: boolean): void => { this.canSetNewChatPrivacy = value; }, 'canNewChat'));
    tasks.push(this.guarded(getBoolOption(OPT_CAN_IGNORE_SENSITIVE, this.client), sequence,
      (value: boolean): void => { this.canIgnoreSensitive = value; }, 'canSensitive'));
    tasks.push(this.guarded(getBoolOption(OPT_IGNORE_SENSITIVE, this.client), sequence,
      (value: boolean): void => { this.ignoreSensitive = value; }, 'sensitive'));
    tasks.push(this.guarded(getBoolOption(OPT_IS_PREMIUM, this.client), sequence,
      (value: boolean): void => { this.isPremium = value; }, 'premium'));

    for (const setting of this.settings) {
      tasks.push(this.guarded(getPrivacy(setting, this.client), sequence,
        (value: PrivacyValue): void => {
          const next = new Map(this.rules);
          next.set(setting, value);
          this.rules = next;
        }, `privacy(${setting})`));
    }

    Promise.all(tasks).then((results: boolean[]): void => {
      if (!this.active || sequence !== this.sequence) { return; }
      const successCount = results.filter((value: boolean): boolean => value).length;
      this.refreshing = false;
      if (successCount === 0) {
        this.loadState = 'error';
        this.syncError = str('pst_read_failed');
      } else {
        this.loadState = 'ready';
        if (successCount < results.length) {
          this.syncError = str('pst_partial');
        }
      }
      this.notify();
    });
  }
}
