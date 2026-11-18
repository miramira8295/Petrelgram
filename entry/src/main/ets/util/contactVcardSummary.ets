export interface ContactVcardSummary {
  phones: string[];
  lines: string[];
}

function vcardDisplayValue(value: string): string {
  return value.replace(/\\[nN]/g, '\n').replace(/\\([,;\\])/g, '$1').trim();
}

// A single physical-line pass, followed by one pass over unfolded fields.
// PHOTO payloads and unrelated fields never enter the displayed summary.
export function contactVcardSummary(vcard: string, fallbackPhone: string): ContactVcardSummary {
  const fields: string[] = [];
  let fragments: string[] = [];
  let quoted: boolean = false;
  for (const physical of vcard.split(/\r\n|\n|\r/)) {
    if (quoted) {
      const continues = physical.endsWith('=');
      fragments.push(continues ? physical.slice(0, -1) : physical);
      quoted = continues;
    } else if ((physical.startsWith(' ') || physical.startsWith('\t')) && fragments.length > 0) {
      fragments.push(physical.slice(1));
    } else {
      if (fragments.length > 0) { fields.push(fragments.join('')); }
      const separator = physical.indexOf(':');
      quoted = separator >= 0 && physical.slice(0, separator).toUpperCase().includes('ENCODING=QUOTED-PRINTABLE') && physical.endsWith('=');
      fragments = [quoted ? physical.slice(0, -1) : physical];
    }
  }
  if (fragments.length > 0) { fields.push(fragments.join('')); }
  const phones: string[] = [], lines: string[] = [];
  const seen = new Set<string>();
  for (const field of fields) {
    const separator = field.indexOf(':');
    if (separator < 0) { continue; }
    const header = field.slice(0, separator).toUpperCase();
    const property = header.split(';', 1)[0];
    const kind = property.slice(property.lastIndexOf('.') + 1);
    if (kind !== 'TEL' && kind !== 'EMAIL' && kind !== 'ORG') { continue; }
    if (header.includes('ENCODING=B') || header.includes('ENCODING=BASE64')) { continue; }
    let raw = field.slice(separator + 1);
    if (header.includes('ENCODING=QUOTED-PRINTABLE')) {
      try { raw = decodeURIComponent(raw.replace(/%/g, '%25').replace(/=([0-9A-Fa-f]{2})/g, '%$1')); }
      catch (_) { /* Keep malformed/unsupported legacy charset text readable. */ }
    }
    const value = vcardDisplayValue(kind === 'TEL' ? raw.replace(/^tel:/i, '') : kind === 'ORG' ? raw.replace(/;/g, ' ') : raw);
    if (value === '' || seen.has(value)) { continue; }
    seen.add(value); lines.push(value);
    if (kind === 'TEL') { phones.push(value); }
  }
  const phone = fallbackPhone.trim();
  if (phone !== '' && !seen.has(phone)) { phones.unshift(phone); lines.unshift(phone); }
  return { phones, lines };
}
