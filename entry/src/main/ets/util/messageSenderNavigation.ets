import { navigateToProfile, navigateToChatProfile } from './profileNav';
import { navigateToChat, logChatNavFailure } from './chatNav';

// Android ChatActivity.openChat: the current group's anonymous sender opens
// group details; another chat identity opens that chat. Never infer a user from
// an author signature/admin label. TDLib gives only the public sending identity.
export function openMessageSender(senderId: number, senderIsUser: boolean, currentChatId: number): void {
  if (!Number.isSafeInteger(senderId) || senderId === 0) { return; }
  if (senderIsUser) {
    if (senderId > 0) { navigateToProfile({ 'userId': senderId }); }
  } else if (senderId < 0) {
    if (senderId === currentChatId) { navigateToChatProfile({ 'chatId': senderId }); }
    else { navigateToChat({ 'chatId': senderId }, 'content').catch(logChatNavFailure); }
  }
}
