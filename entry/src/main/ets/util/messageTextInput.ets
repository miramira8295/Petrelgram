import { MessageEntry } from '../store/MessageEntry';
import { TdObject } from '../tdkit/TdTypes';

export type MessageTextMode = 'body' | 'caption' | 'translation';

export interface MessageTextInput {
  text: string;
  entities: TdObject[];
  maxWidth: number;
  mode: MessageTextMode;
}

export const TRANSLATION_TEXT_INPUT: MessageTextInput = {
  text: '', entities: [], maxWidth: 0, mode: 'translation'
};

// One immutable input per text owner. Live state and callbacks stay separate.
export class MessageTextInputCache {
  private previous: MessageTextInput | undefined = undefined;

  prepare(text: string, entities: TdObject[], maxWidth: number,
    mode: MessageTextMode): MessageTextInput {
    const previous = this.previous;
    if (previous !== undefined && previous.text === text && previous.entities === entities &&
      previous.maxWidth === maxWidth && previous.mode === mode) {
      return previous;
    }
    const next: MessageTextInput = { text, entities, maxWidth, mode };
    this.previous = next;
    return next;
  }
}

// Only these page fields affect text layout. Selection, playback, and other
// media state must not replace the text input merely because data changed.
export interface MessageTextLayout {
  // Actual row width after page-local chrome such as the multi-select gutter.
  // Media, albums and both bubble renderers derive every cap from this value.
  contentWidth: number;
  isGroup: boolean;
  isChannel: boolean;
}

export interface MessageTextPresentation {
  msg: MessageEntry;
  input: MessageTextInput;
  showSenderName: boolean;
  layout: MessageTextLayout;
}

// One bounded snapshot per text owner. Keep observed context and callbacks
// outside it: their live changes retain their existing subscription boundaries.
export class MessageTextPresentationCache {
  private inputCache: MessageTextInputCache = new MessageTextInputCache();
  private previous: MessageTextPresentation | undefined = undefined;

  prepare(msg: MessageEntry, showSenderName: boolean, layout: MessageTextLayout,
    text: string, entities: TdObject[], maxWidth: number, mode: MessageTextMode): MessageTextPresentation {
    const input = this.inputCache.prepare(text, entities, maxWidth, mode);
    const previous = this.previous;
    if (previous !== undefined && previous.msg === msg && previous.input === input &&
      previous.showSenderName === showSenderName && previous.layout.contentWidth === layout.contentWidth &&
      previous.layout.isGroup === layout.isGroup && previous.layout.isChannel === layout.isChannel) {
      return previous;
    }
    const next: MessageTextPresentation = {
      msg, input, showSenderName,
      layout: { contentWidth: layout.contentWidth, isGroup: layout.isGroup, isChannel: layout.isChannel }
    };
    this.previous = next;
    return next;
  }
}
