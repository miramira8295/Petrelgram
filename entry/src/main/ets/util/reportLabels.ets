// Only display text is localized. Server option IDs remain opaque bytes and
// must never be inferred from a translated label, list position or substring.
const REASON_KEYS: Map<string, string> = new Map<string, string>([
  ['spam', 'rf_reason_spam'], ['fake account', 'rf_reason_fake'],
  ['violence', 'rf_reason_violence'], ['child abuse', 'rf_reason_child_abuse'],
  ['pornography', 'rf_reason_pornography'], ['copyright', 'rf_reason_copyright'],
  ['illegal drugs', 'rf_reason_drugs'], ['personal details', 'rf_reason_personal'],
  ['personal data', 'rf_reason_personal'], ['other', 'rf_reason_other'], ["i don't like it", 'rf_reason_dislike'],
  ['illegal goods and services', 'rf_reason_goods_services'],
  ['illegal adult content', 'rf_reason_adult'], ['terrorism', 'rf_reason_terrorism'],
  ['scam or spam', 'rf_reason_scam_spam'], ['illegal goods', 'rf_reason_goods']
]);

export function reportDisplayText(text: string, translate: (key: string) => string,
  title: boolean = false): string {
  const normalized: string = text.trim().toLowerCase();
  if (title && (normalized === '' || normalized === 'choose a reason' ||
    normalized === 'select a reason' || normalized === 'report reason' ||
    normalized === 'why are you reporting this?' ||
    normalized === 'why are you reporting this message?' ||
    normalized === 'why are you reporting this content?')) {
    return translate('cpp_report_reason');
  }
  if (title && normalized === 'report') { return translate('mb_report'); }
  const key: string | undefined = REASON_KEYS.get(normalized);
  // Unknown/new server text remains visible; don't mislabel a report category.
  return key === undefined ? text : translate(key);
}
