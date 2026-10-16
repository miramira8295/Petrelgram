import { DropRecordFields, normalizeDropRecord } from '../util/dropRecord';
import { logI } from '../util/log';
import { unifiedDataChannel as udc, uniformTypeDescriptor as utd } from '@kit.ArkData';
import { fileIo as fs } from '@kit.CoreFileKit';
import { SharedItem, SharedPayload, itemOf, splitPayload, ancestorCandidates } from '../util/sharedContent';
import { fileNameFromUri } from '../util/mediaPick';

export const CHAT_DROP_TYPES: string[] = ['general.plain-text', 'general.hyperlink', 'general.html',
  'general.image', 'general.video', 'general.audio', 'general.file', 'general.file-uri'];

function ancestor(type: string): string {
  try {
    const descriptor = utd.getTypeDescriptor(type);
    for (const candidate of ancestorCandidates()) {
      if (descriptor.belongsTo(candidate)) { return candidate; }
    }
    if (descriptor.belongsTo('general.file')) { return 'general.file'; }
  } catch (_) { /* Unknown types are rejected below. */ }
  return '';
}

export async function decodeDrop(data: udc.UnifiedData, directory: string,
  active: () => boolean): Promise<SharedPayload> {
  const records = data.getRecords();
  if (records.length === 0 || records.length > 20) { throw new Error('invalid drop count'); }
  const items: SharedItem[] = [];
  const seenFiles = new Set<string>();
  for (let i = 0; i < records.length; i++) {
    if (!active()) { throw new Error('drop cancelled'); }
    const record = records[i];
    const types = record.getTypes();
    const type = types.includes('general.file-uri') ? 'general.file-uri' : record.getType();
    const parent = ancestor(type);
    let fields: DropRecordFields;
    if (type === 'general.file-uri') {
      fields = record.getEntry(type) as DropRecordFields;
    } else {
      const value = record.getValue();
      if (value !== null && typeof value === 'object') {
        fields = value as DropRecordFields;
      } else if (typeof value === 'string' && type === 'general.plain-text') {
        fields = { textContent: value };
      } else {
        fields = {};
      }
      // Older UDMF records expose the actual payload through subclass getters.
      if (type === 'general.plain-text') { fields.textContent = fields.textContent || (record as udc.PlainText).textContent; }
      else if (type === 'general.hyperlink') { fields.url = fields.url || (record as udc.Hyperlink).url; }
      else if (type === 'general.html') { fields.plainContent = fields.plainContent || (record as udc.HTML).plainContent; }
      else if (parent === 'general.image') { fields.imageUri = fields.imageUri || (record as udc.Image).imageUri; }
      else if (parent === 'general.video') { fields.videoUri = fields.videoUri || (record as udc.Video).videoUri; }
      else if (parent === 'general.audio') { fields.audioUri = fields.audioUri || (record as udc.Audio).audioUri; }
      else if (parent === 'general.file') { fields.uri = fields.uri || (record as udc.File).uri; }
    }
    if (fields === null || typeof fields !== 'object') { throw new Error('invalid drop entry'); }
    const normalized = normalizeDropRecord(type, parent, fields);
    logI(`[Drop] record=${i} type=${type} uri=${(normalized.uri ?? '') !== ''} text=${(normalized.content ?? '') !== ''}`);
    const item = itemOf(normalized, ancestor(normalized.utd));
    if (item === null) { throw new Error('empty drop record'); }
    if (item.uri === '') { items.push(item); continue; }
    // A duplicate URI after system copying could mean a same-name overwrite. Never silently send it twice.
    if (seenFiles.has(item.uri)) { throw new Error('duplicate drop file'); }
    seenFiles.add(item.uri);
    const name = fileNameFromUri(item.uri).replace(/[\/\\]/g, '_');
    if (name === '' || name === '.' || name === '..') { throw new Error('invalid drop filename'); }
    const targetDir = `${directory}/item_${i}`;
    await fs.mkdir(targetDir);
    const path = `${targetDir}/${name}`;
    const source = await fs.open(item.uri, fs.OpenMode.READ_ONLY);
    try {
      const stat = await fs.stat(source.fd);
      if (!stat.isFile()) { throw new Error('not a regular file'); }
      await fs.copyFile(source.fd, path);
    } finally { await fs.close(source); }
    items.push({ kind: item.kind, uri: path, text: '', title: name, sourceUri: '' });
  }
  if (!active()) { throw new Error('drop cancelled'); }
  return splitPayload(items);
}
