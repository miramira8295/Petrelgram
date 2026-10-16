import { i18n } from '@kit.LocalizationKit';
import { ContactItem } from '../store/ContactsStore';
import { ContactNameKey, contactNameKey, compareContactNames } from '../util/contactAlphabet';

interface CachedContactName { source: string; key: ContactNameKey; }
export interface ContactLetterPosition { letter: string; index: number; }

// Native transliteration is done once per changed name, never once per comparison/status update.
export class ContactAlphabetIndex {
  private names: Map<number, CachedContactName> = new Map();
  private headers: Map<number, string> = new Map();
  private latin: i18n.Transliterator | null = null;
  private ascii: i18n.Transliterator | null = null;
  positions: ContactLetterPosition[] = [];

  constructor() {
    try {
      this.latin = i18n.Transliterator.getInstance('Any-Latn');
      this.ascii = i18n.Transliterator.getInstance('Latin-ASCII');
    } catch (_) { /* Unsupported locale data falls back to the original name. */ }
  }

  private key(contact: ContactItem): ContactNameKey {
    const source = contact.sortName ?? contact.name;
    const cached = this.names.get(contact.id);
    if (cached !== undefined && cached.source === source) { return cached.key; }
    const key = contactNameKey(source, (name: string): string => {
      const latin = this.latin !== null ? this.latin.transform(name) : name;
      return this.ascii !== null ? this.ascii.transform(latin) : latin;
    });
    this.names.set(contact.id, { source: source, key: key });
    return key;
  }

  sort(contacts: ContactItem[]): ContactItem[] {
    const present = new Set<number>();
    contacts.forEach((contact: ContactItem): void => { present.add(contact.id); this.key(contact); });
    this.names.forEach((_value: CachedContactName, id: number): void => {
      if (!present.has(id)) { this.names.delete(id); }
    });
    const result = contacts.slice().sort((a: ContactItem, b: ContactItem): number =>
      compareContactNames(this.key(a), this.key(b), a.id, b.id));
    this.headers.clear();
    const positions: ContactLetterPosition[] = [];
    let previous = '';
    result.forEach((contact: ContactItem, index: number): void => {
      const letter = this.key(contact).letter;
      if (letter !== previous) {
        previous = letter; this.headers.set(contact.id, letter);
        positions.push({ letter: letter, index: index });
      }
    });
    this.positions = positions;
    return result;
  }

  heading(id: number): string { return this.headers.get(id) ?? ''; }
  clear(): void { this.names.clear(); this.headers.clear(); this.positions = []; }
}
