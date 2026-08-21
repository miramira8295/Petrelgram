import { getTdClient } from '../../tdkit/Globals';
import { TdObject, TdRequest } from '../../tdkit/TdTypes';
import { str } from '../../util/strings';
import { logE } from '../../util/log';

export interface CountryOption {
  iso2: string;
  name: string;
  englishName: string;
  callingCode: string;
  flag: string;
}

function flagForIso(iso2: string): string {
  const upper = iso2.toUpperCase();
  if (upper.length !== 2) { return '🌐'; }
  return String.fromCodePoint(
    127397 + upper.charCodeAt(0),
    127397 + upper.charCodeAt(1)
  );
}

function country(
  iso2: string, name: string, englishName: string, callingCode: string
): CountryOption {
  return { iso2, name, englishName, callingCode, flag: flagForIso(iso2) };
}

// Immediate offline choices while TDLib loads its complete, server-maintained
// country list. The online result replaces this list and includes every code.
// A function, not a const: the names come from str(), which resolves when
// called. A module-level array is built at first import — before the string
// source exists — and would freeze the language.
export function fallbackCountries(): CountryOption[] {
  return [
  country('CN', str('country_cn'), 'China', '86'),
  country('HK', str('country_hk'), 'Hong Kong', '852'),
  country('MO', str('country_mo'), 'Macao', '853'),
  country('TW', str('country_tw'), 'Taiwan', '886'),
  country('SG', str('country_sg'), 'Singapore', '65'),
  country('MY', str('country_my'), 'Malaysia', '60'),
  country('JP', str('country_jp'), 'Japan', '81'),
  country('KR', str('country_kr'), 'South Korea', '82'),
  country('TH', str('country_th'), 'Thailand', '66'),
  country('VN', str('country_vn'), 'Vietnam', '84'),
  country('PH', str('country_ph'), 'Philippines', '63'),
  country('ID', str('country_id'), 'Indonesia', '62'),
  country('IN', str('country_in'), 'India', '91'),
  country('AE', str('country_ae'), 'United Arab Emirates', '971'),
  country('SA', str('country_sa'), 'Saudi Arabia', '966'),
  country('TR', str('country_tr'), 'Türkiye', '90'),
  country('RU', str('country_ru'), 'Russia', '7'),
  country('UA', str('country_ua'), 'Ukraine', '380'),
  country('GB', str('country_gb'), 'United Kingdom', '44'),
  country('FR', str('country_fr'), 'France', '33'),
  country('DE', str('country_de'), 'Germany', '49'),
  country('IT', str('country_it'), 'Italy', '39'),
  country('ES', str('country_es'), 'Spain', '34'),
  country('PT', str('country_pt'), 'Portugal', '351'),
  country('NL', str('country_nl'), 'Netherlands', '31'),
  country('BE', str('country_be'), 'Belgium', '32'),
  country('CH', str('country_ch'), 'Switzerland', '41'),
  country('AT', str('country_at'), 'Austria', '43'),
  country('SE', str('country_se'), 'Sweden', '46'),
  country('NO', str('country_no'), 'Norway', '47'),
  country('FI', str('country_fi'), 'Finland', '358'),
  country('DK', str('country_dk'), 'Denmark', '45'),
  country('PL', str('country_pl'), 'Poland', '48'),
  country('CZ', str('country_cz'), 'Czechia', '420'),
  country('GR', str('country_gr'), 'Greece', '30'),
  country('US', str('country_us'), 'United States', '1'),
  country('CA', str('country_ca'), 'Canada', '1'),
  country('MX', str('country_mx'), 'Mexico', '52'),
  country('BR', str('country_br'), 'Brazil', '55'),
  country('AR', str('country_ar'), 'Argentina', '54'),
  country('CL', str('country_cl'), 'Chile', '56'),
  country('CO', str('country_co'), 'Colombia', '57'),
  country('AU', str('country_au'), 'Australia', '61'),
  country('NZ', str('country_nz'), 'New Zealand', '64'),
  country('ZA', str('country_za'), 'South Africa', '27'),
  country('EG', str('country_eg'), 'Egypt', '20'),
  country('NG', str('country_ng'), 'Nigeria', '234'),
  country('KE', str('country_ke'), 'Kenya', '254'),
  country('IL', str('country_il'), 'Israel', '972'),
  country('PK', str('country_pk'), 'Pakistan', '92'),
  country('BD', str('country_bd'), 'Bangladesh', '880')
  ];
}

function parseCountries(response: TdObject): CountryOption[] {
  const rawCountries = (response['countries'] as TdObject[] | undefined) ?? [];
  const result: CountryOption[] = [];
  const seen: Set<string> = new Set();
  for (const raw of rawCountries) {
    if ((raw['is_hidden'] as boolean | undefined) === true) { continue; }
    const iso2 = (raw['country_code'] as string | undefined) ?? '';
    const name = (raw['name'] as string | undefined) ??
      (raw['default_name'] as string | undefined) ?? '';
    const englishName = (raw['english_name'] as string | undefined) ?? name;
    const callingCodes = (raw['calling_codes'] as string[] | undefined) ?? [];
    for (const callingCode of callingCodes) {
      const key = `${iso2}:${callingCode}`;
      if (callingCode === '' || seen.has(key)) { continue; }
      seen.add(key);
      result.push(country(iso2, name !== '' ? name : englishName, englishName, callingCode));
    }
    // Compatibility with the older Telegram country-list shape used by some
    // TDLib builds, where codes were objects rather than strings.
    const legacyCodes = (raw['country_codes'] as TdObject[] | undefined) ?? [];
    for (const calling of legacyCodes) {
      const callingCode = (calling['calling_code'] as string | undefined) ??
        (calling['country_code'] as string | undefined) ?? '';
      const key = `${iso2}:${callingCode}`;
      if (callingCode === '' || seen.has(key)) { continue; }
      seen.add(key);
      result.push(country(iso2, name !== '' ? name : englishName, englishName, callingCode));
    }
  }
  result.sort((left: CountryOption, right: CountryOption): number =>
    left.name.localeCompare(right.name));
  return result;
}

export async function loadCountries(): Promise<CountryOption[]> {
  try {
    const request: TdRequest = { '@type': 'getCountries' };
    const response = await getTdClient().send(request, 20000);
    const countries = parseCountries(response);
    return countries.length > 0 ? countries : fallbackCountries();
  } catch (caught) {
    const error = caught as Error;
    logE(`CountryData.loadCountries failed: ${error.message}`);
    return fallbackCountries();
  }
}

export function filterCountries(
  countries: CountryOption[], query: string
): CountryOption[] {
  const normalized = query.trim().toLowerCase().replace('+', '');
  if (normalized === '') { return countries; }
  return countries.filter((item: CountryOption): boolean =>
    item.name.toLowerCase().includes(normalized) ||
    item.englishName.toLowerCase().includes(normalized) ||
    item.iso2.toLowerCase().includes(normalized) ||
    item.callingCode.includes(normalized)
  );
}
