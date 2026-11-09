import { str } from './strings';

export interface FolderIconOption {
  name: string;
  label: string;
  emoji: string;
  symbol: Resource;
}

// Telegram folder icons are predefined server-side names; every client renders
// its own local artwork for them. Tintable system symbols keep the look flat
// and consistent with the rest of the UI (color emoji can't be tinted).
//
// A function, not a const array: labels come from str(), which resolves at call
// time. A module-level array would be built when this module is first imported
// — possibly before the string source is installed — and would then keep the
// old language forever after a language switch.
export function folderIconOptions(): FolderIconOption[] {
  return [
  { name: 'Custom', label: str('folder_icon_custom'), emoji: '📁', symbol: $r('sys.symbol.folder') },
  { name: 'Unread', label: str('folder_icon_unread'), emoji: '📨', symbol: $r('sys.symbol.envelope') },
  { name: 'Unmuted', label: str('folder_icon_unmuted'), emoji: '🔔', symbol: $r('sys.symbol.bell') },
  { name: 'Private', label: str('folder_icon_private'), emoji: '👤', symbol: $r('sys.symbol.person') },
  { name: 'Groups', label: str('folder_icon_groups'), emoji: '👥', symbol: $r('sys.symbol.person_2') },
  { name: 'Channels', label: str('folder_icon_channels'), emoji: '📢', symbol: $r('sys.symbol.speaker_wave_2') },
  { name: 'Bots', label: str('folder_icon_bots'), emoji: '🤖', symbol: $r('sys.symbol.robot') },
  { name: 'Favorite', label: str('folder_icon_favorite'), emoji: '⭐', symbol: $r('sys.symbol.star') },
  { name: 'Work', label: str('folder_icon_work'), emoji: '💼', symbol: $r('sys.symbol.briefcase') },
  { name: 'Study', label: str('folder_icon_study'), emoji: '📚', symbol: $r('sys.symbol.school') },
  { name: 'Home', label: str('folder_icon_home'), emoji: '🏠', symbol: $r('sys.symbol.house') },
  { name: 'Travel', label: str('folder_icon_travel'), emoji: '✈️', symbol: $r('sys.symbol.airplane') },
  { name: 'Game', label: str('folder_icon_game'), emoji: '🎮', symbol: $r('sys.symbol.gamecontroller') },
  { name: 'Sport', label: str('folder_icon_sport'), emoji: '⚽', symbol: $r('sys.symbol.figure_run') },
  { name: 'Trade', label: str('folder_icon_trade'), emoji: '📈', symbol: $r('sys.symbol.arrow_up_right') },
  { name: 'Money', label: str('folder_icon_money'), emoji: '💰', symbol: $r('sys.symbol.wallet') },
  { name: 'Love', label: str('folder_icon_love'), emoji: '❤️', symbol: $r('sys.symbol.heart') },
  { name: 'Party', label: str('folder_icon_party'), emoji: '🎉', symbol: $r('sys.symbol.gift') },
  { name: 'Book', label: str('folder_icon_book'), emoji: '📖', symbol: $r('sys.symbol.book') },
  { name: 'Palette', label: str('folder_icon_palette'), emoji: '🎨', symbol: $r('sys.symbol.paintpalette') },
  // td_api.tl 的 chatFolderIcon 一共定义了 30 个名字。少映射一个，用到它的
  // 文件夹就会掉进兜底的通用文件夹图标 —— 表现是列表里一片一模一样的方框。
  { name: 'All', label: str('folder_icon_all'), emoji: '💬', symbol: $r('sys.symbol.message') },
  { name: 'Setup', label: str('folder_icon_setup'), emoji: '⚙️', symbol: $r('sys.symbol.gearshape') },
  { name: 'Cat', label: str('folder_icon_cat'), emoji: '🐱', symbol: $r('sys.symbol.pawprint') },
  { name: 'Crown', label: str('folder_icon_crown'), emoji: '👑', symbol: $r('sys.symbol.crown') },
  { name: 'Flower', label: str('folder_icon_flower'), emoji: '🌹', symbol: $r('sys.symbol.flower') },
  { name: 'Mask', label: str('folder_icon_mask'), emoji: '🎭', symbol: $r('sys.symbol.face') },
  { name: 'Light', label: str('folder_icon_light'), emoji: '💡', symbol: $r('sys.symbol.lightbulb') },
  { name: 'Like', label: str('folder_icon_like'), emoji: '👍', symbol: $r('sys.symbol.hand_thumbsup') },
  { name: 'Note', label: str('folder_icon_note'), emoji: '📝', symbol: $r('sys.symbol.doc_text') },
    { name: 'Airplane', label: str('folder_icon_airplane'), emoji: '✈️', symbol: $r('sys.symbol.airplane') }
  ];
}

export const FOLDER_COLORS: string[] = [
  '#5B8FF9', '#61CDBB', '#F6BD16', '#E8684A', '#9270CA', '#6DC8EC', '#FF7A9A'
];

function optionOf(name: string): FolderIconOption | undefined {
  return folderIconOptions().find((item: FolderIconOption): boolean => item.name === name);
}

export function folderEmoji(name: string): string {
  return optionOf(name)?.emoji ?? '📁';
}

export function folderSymbol(name: string): Resource {
  return optionOf(name)?.symbol ?? $r('sys.symbol.folder');
}

export function folderColor(colorId: number): string {
  return colorId >= 0 && colorId < FOLDER_COLORS.length ? FOLDER_COLORS[colorId] : '#5B8FF9';
}
