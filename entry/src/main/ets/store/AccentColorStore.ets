import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest } from '../tdkit/TdTypes';
import { accentPreviewOf, builtinAccentColor } from '../util/accentPresentation';

export interface AccentPalettes {
  nameColors: TdObject[];
  nameIds: number[];
  profileColors: TdObject[];
  profileIds: number[];
}

type AccentListener = (palettes: AccentPalettes) => void;

// Accent palettes are server-defined and pushed once per connection via
// updateAccentColors / updateProfileAccentColors — same pattern as chat
// themes: cache the pushes, expose setters that reference palette ids.
export class AccentColorStore {
  private client: TdClient;
  private nameColors: TdObject[] = [];
  private nameIds: number[] = [];
  private profileColors: TdObject[] = [];
  private profileIds: number[] = [];
  private listeners: AccentListener[] = [];

  constructor(client: TdClient) {
    this.client = client;
    client.onUpdate('updateAccentColors', (update: TdObject): void => {
      this.nameColors = ((update['colors'] as TdObject[] | undefined) ?? []).slice();
      this.nameIds = ((update['available_accent_color_ids'] as number[] | undefined) ?? []).slice();
      this.emit();
    });
    client.onUpdate('updateProfileAccentColors', (update: TdObject): void => {
      this.profileColors = ((update['colors'] as TdObject[] | undefined) ?? []).slice();
      this.profileIds =
        ((update['available_accent_color_ids'] as number[] | undefined) ?? []).slice();
      this.emit();
    });
  }

  private snapshot(): AccentPalettes {
    return {
      nameColors: this.nameColors.slice(),
      nameIds: this.nameIds.slice(),
      profileColors: this.profileColors.slice(),
      profileIds: this.profileIds.slice()
    };
  }

  private emit(): void {
    const value = this.snapshot();
    for (const listener of this.listeners) { listener(value); }
  }

  palettes(): AccentPalettes {
    return this.snapshot();
  }

  // Display color for a user's name accent id: server palette entry first,
  // built-in single colors (ids 0–6) as fallback, '' when unknown.
  nameColorHex(accentColorId: number, forDark: boolean): string {
    if (accentColorId < 0) { return ''; }
    const raw = this.nameColors.find((entry: TdObject): boolean =>
      ((entry['id'] as number | undefined) ?? -1) === accentColorId
    );
    if (raw !== undefined) {
      const preview = accentPreviewOf(raw, forDark);
      if (preview !== null && preview.colors.length > 0) { return preview.colors[0]; }
    }
    return accentColorId <= 6 ? builtinAccentColor(accentColorId, forDark) : '';
  }

  subscribe(listener: AccentListener): () => void {
    this.listeners = [...this.listeners, listener];
    listener(this.snapshot());
    return (): void => {
      this.listeners = this.listeners.filter(
        (current: AccentListener): boolean => current !== listener
      );
    };
  }

  async setNameAccentColor(accentColorId: number): Promise<void> {
    const request: TdRequest = { '@type': 'setAccentColor' };
    request['accent_color_id'] = accentColorId;
    request['background_custom_emoji_id'] = '0';
    await this.client.send(request, 15000);
  }

  async setProfileAccentColor(accentColorId: number): Promise<void> {
    const request: TdRequest = { '@type': 'setProfileAccentColor' };
    request['profile_accent_color_id'] = accentColorId;
    request['profile_background_custom_emoji_id'] = '0';
    await this.client.send(request, 15000);
  }

  // Current selection lives on the own-user object.
  async currentSelection(): Promise<[number, number]> {
    const me = await this.client.send({ '@type': 'getMe' } as TdRequest);
    return [
      (me['accent_color_id'] as number | undefined) ?? -1,
      (me['profile_accent_color_id'] as number | undefined) ?? -1
    ];
  }
}
