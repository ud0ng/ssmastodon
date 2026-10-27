// 컨텐츠 툿: 시스템 계정이 쓴 툿, 시스템 계정을 멘션하며 컨텐츠 명령어를 쓴 툿. 웹에서는 홈·타임라인·프로필·알림에서 숨기고 컨텐츠 메뉴(방)에서만 본다.
// 기본 명령어([점수]·[도움말]·[내전적]·[사용])와 명령어 없는 단순 멘션은 숨기지 않는다. (앱은 그대로 보인다 — 기록용)
import {
  gameBasicCommands,
  systemAccountId,
  systemAcct,
} from 'mastodon/initial_state';

interface StatusLike {
  account?: { acct?: string } | null;
  mentions?: { acct?: string }[] | null;
  in_reply_to_account_id?: string | null;
  reblog?: StatusLike | null;
  content?: string | null;
  // 시스템 계정이 올렸지만 웹에서도 보여 주는 안내 툿 (호울러·결산 공지·기본 명령어의 답 등)
  game_notice?: boolean;
}

// 툿 글(HTML)의 첫 [명령어] 이름: "[먹기/2]" → "먹기"
const COMMAND = /\[([^[\]\n]{1,60})\]/;

const commandOf = (content: string | null | undefined): string | null => {
  const text = (content ?? '')
    .replace(/<br\s*\/?>|<\/p>/gi, '\n')
    .replace(/<[^>]+>/g, '')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>');
  const match = COMMAND.exec(text);

  return match?.[1]?.split('/')[0]?.trim() || null;
};

export const isGameStatus = (
  status: StatusLike | null | undefined,
): boolean => {
  if (!status || !systemAcct) return false;
  if (status.reblog) return isGameStatus(status.reblog);
  if (status.game_notice) return false;
  if (status.account?.acct === systemAcct) return true;
  // 시스템에게 한 답글 (그냥 하는 말: 멘션이 없어도 컨텐츠 대화)
  if (systemAccountId && status.in_reply_to_account_id === systemAccountId)
    return true;

  const tagsSystem = (status.mentions ?? []).some(
    (mention) => mention.acct === systemAcct,
  );
  if (!tagsSystem) return false;

  // 시스템을 태그했어도 컨텐츠 명령어를 쓴 툿만 컨텐츠다: 기본 명령어와 명령어 없는 멘션은 보인다
  const command = commandOf(status.content);

  return command !== null && !gameBasicCommands.includes(command);
};
