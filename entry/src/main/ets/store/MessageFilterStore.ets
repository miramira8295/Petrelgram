import {
  CompiledChatFilter, FilterMatchField, FilterMatchMode, MessageFilterConfig, MessageFilterRule,
  compileFilterForChat, emptyMessageFilterConfig, normalizeUsernamePattern,
  parseMessageFilterConfig, serializeMessageFilterConfig
} from '../util/messageFilter';
import { KEY_MESSAGE_FILTERS, setString } from './AppSettings';

// 全局 + 按会话消息拦截规则仓：
// 规则变更时清空按 chatId 缓存并递增 ruleVersion，通知所有已打开的 MessageStore 重投影。
export const MESSAGE_FILTER_EPOCH: string = 'messageFilterEpoch';

class MessageFilterStore {
  private loaded: boolean = false;
  private lastRaw: string = '';
  private config: MessageFilterConfig = emptyMessageFilterConfig();
  private compiledCache: Map<number, CompiledChatFilter | null> = new Map<number, CompiledChatFilter | null>();
  private version: number = 0;
  private listeners: Array<() => void> = [];

  private ensureLoaded(): void {
    const raw: string = AppStorage.get<string>(KEY_MESSAGE_FILTERS) ?? '';
    if (this.loaded && raw === this.lastRaw) {
      return;
    }
    this.loaded = true;
    this.lastRaw = raw;
    this.compiledCache.clear();
    this.config = parseMessageFilterConfig(raw);
  }

  private commit(): void {
    this.version++;
    this.compiledCache.clear();
    const serialized: string = serializeMessageFilterConfig(this.config);
    this.lastRaw = serialized;
    setString(KEY_MESSAGE_FILTERS, serialized);
    AppStorage.setOrCreate(MESSAGE_FILTER_EPOCH, this.version);
    for (const fn of this.listeners) {
      fn();
    }
  }

  subscribe(listener: () => void): () => void {
    this.ensureLoaded();
    this.listeners = [...this.listeners, listener];
    return (): void => {
      this.listeners = this.listeners.filter((fn: () => void): boolean => fn !== listener);
    };
  }

  getVersion(): number {
    this.ensureLoaded();
    return this.version;
  }

  getConfig(): MessageFilterConfig {
    this.ensureLoaded();
    return {
      enabled: this.config.enabled,
      disabledGlobalChatIds: [...this.config.disabledGlobalChatIds],
      rules: this.config.rules.map((r: MessageFilterRule): MessageFilterRule => {
        const copy: MessageFilterRule = {
          id: r.id,
          enabled: r.enabled,
          chatId: r.chatId,
          field: r.field,
          mode: r.mode,
          pattern: r.pattern
        };
        if (r.userId !== undefined) { copy.userId = r.userId; }
        if (r.note !== undefined) { copy.note = r.note; }
        return copy;
      })
    };
  }

  isEnabled(): boolean {
    this.ensureLoaded();
    return this.config.enabled;
  }

  setEnabled(enabled: boolean): void {
    this.ensureLoaded();
    if (this.config.enabled === enabled) {
      return;
    }
    this.config.enabled = enabled;
    this.commit();
  }

  isGlobalDisabledForChat(chatId: number): boolean {
    this.ensureLoaded();
    return this.config.disabledGlobalChatIds.indexOf(chatId) >= 0;
  }

  setGlobalDisabledForChat(chatId: number, disabled: boolean): void {
    this.ensureLoaded();
    if (chatId === 0) { return; }
    const idx: number = this.config.disabledGlobalChatIds.indexOf(chatId);
    if (disabled && idx < 0) {
      this.config.disabledGlobalChatIds = [...this.config.disabledGlobalChatIds, chatId];
      this.commit();
    } else if (!disabled && idx >= 0) {
      this.config.disabledGlobalChatIds =
        this.config.disabledGlobalChatIds.filter((id: number): boolean => id !== chatId);
      this.commit();
    }
  }

  compiledForChat(chatId: number): CompiledChatFilter | null {
    this.ensureLoaded();
    if (!this.config.enabled || chatId === 0) {
      return null;
    }
    if (this.compiledCache.has(chatId)) {
      return this.compiledCache.get(chatId) ?? null;
    }
    const compiled: CompiledChatFilter | null = compileFilterForChat(this.config, chatId);
    this.compiledCache.set(chatId, compiled);
    return compiled;
  }

  rulesForScope(chatId: number): MessageFilterRule[] {
    this.ensureLoaded();
    return this.config.rules.filter((r: MessageFilterRule): boolean => r.chatId === chatId);
  }

  activeRuleCountForChat(chatId: number): number {
    this.ensureLoaded();
    if (!this.config.enabled) { return 0; }
    const globalOff: boolean = this.isGlobalDisabledForChat(chatId);
    let count: number = 0;
    for (const r of this.config.rules) {
      if (!r.enabled) { continue; }
      if (r.chatId === chatId || (r.chatId === 0 && !globalOff)) {
        count++;
      }
    }
    return count;
  }

  customChatIds(): number[] {
    this.ensureLoaded();
    const ids: Set<number> = new Set<number>();
    for (const id of this.config.disabledGlobalChatIds) {
      if (id !== 0) { ids.add(id); }
    }
    for (const r of this.config.rules) {
      if (r.chatId !== 0) { ids.add(r.chatId); }
    }
    return Array.from(ids.values());
  }

  addRule(
    chatId: number, field: FilterMatchField, mode: FilterMatchMode,
    pattern: string, userId: number = 0, note: string = ''
  ): boolean {
    this.ensureLoaded();
    const cleanedPattern: string = field === 'user' ? normalizeUsernamePattern(pattern) : pattern.trim();
    if (cleanedPattern === '' && !(field === 'user' && userId > 0)) {
      return false;
    }
    // 去重：同作用域、同字段、同匹配模式/目标不重复添加。
    for (const existing of this.config.rules) {
      if (existing.chatId === chatId && existing.field === field && existing.mode === mode &&
        existing.pattern.toLowerCase() === cleanedPattern.toLowerCase() &&
        (existing.userId ?? 0) === userId) {
        if (!existing.enabled) {
          existing.enabled = true;
          this.commit();
        }
        return true;
      }
    }
    const rule: MessageFilterRule = {
      id: `${Date.now()}_${Math.floor(Math.random() * 100000)}`,
      enabled: true,
      chatId,
      field,
      mode: field === 'user' ? 'exact' : mode,
      pattern: cleanedPattern
    };
    if (userId > 0) { rule.userId = userId; }
    if (note.trim() !== '') { rule.note = note.trim(); }
    this.config.rules = [rule, ...this.config.rules];
    this.commit();
    return true;
  }

  // 长按头像快捷拦截此人在本群的发言：同时记 userId 与当前 username，防止改名绕过。
  quickBlockUserInChat(chatId: number, userId: number, username: string, displayName: string): boolean {
    if (chatId === 0 || (userId <= 0 && username.trim() === '' && displayName.trim() === '')) {
      return false;
    }
    if (userId > 0 || username.trim() !== '') {
      return this.addRule(chatId, 'user', 'exact', username, userId, displayName);
    }
    return this.addRule(chatId, 'nickname', 'exact', displayName, 0, '');
  }

  toggleRule(id: string, enabled: boolean): void {
    this.ensureLoaded();
    for (const r of this.config.rules) {
      if (r.id === id) {
        if (r.enabled !== enabled) {
          r.enabled = enabled;
          this.commit();
        }
        return;
      }
    }
  }

  removeRule(id: string): void {
    this.ensureLoaded();
    const next: MessageFilterRule[] =
      this.config.rules.filter((r: MessageFilterRule): boolean => r.id !== id);
    if (next.length !== this.config.rules.length) {
      this.config.rules = next;
      this.commit();
    }
  }

  // 将某条本会话专属规则提升为全局规则（对所有未跳过全局规则的群组与频道生效）。
  promoteRuleToGlobal(id: string): boolean {
    this.ensureLoaded();
    const target: MessageFilterRule | undefined =
      this.config.rules.find((r: MessageFilterRule): boolean => r.id === id);
    if (target === undefined || target.chatId === 0) {
      return false;
    }
    const existingGlobal: MessageFilterRule | undefined = this.config.rules.find(
      (r: MessageFilterRule): boolean =>
        r.chatId === 0 && r.field === target.field && r.mode === target.mode &&
        r.pattern.toLowerCase() === target.pattern.toLowerCase() &&
        (r.userId ?? 0) === (target.userId ?? 0)
    );
    if (existingGlobal !== undefined) {
      existingGlobal.enabled = true;
      this.config.rules = this.config.rules.filter((r: MessageFilterRule): boolean => r.id !== id);
    } else {
      target.chatId = 0;
      target.enabled = true;
    }
    this.commit();
    return true;
  }
}

const instance: MessageFilterStore = new MessageFilterStore();

export function getMessageFilterStore(): MessageFilterStore {
  return instance;
}
