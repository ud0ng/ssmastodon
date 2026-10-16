// 컨텐츠 툿: 시스템 계정이 쓴 툿, 시스템 계정을 멘션한 툿(명령어). 웹에서는 홈·타임라인·프로필·알림에서 숨기고 컨텐츠 메뉴(방)에서만 본다.
// (앱은 그대로 보인다 — 기록용)
import { systemAccountId, systemAcct } from 'mastodon/initial_state';

interface StatusLike {
  account?: { acct?: string } | null;
  mentions?: { acct?: string }[] | null;
  in_reply_to_account_id?: string | null;
  reblog?: StatusLike | null;
}

export const isGameStatus = (status: StatusLike | null | undefined): boolean => {
  if (!status || !systemAcct) return false;
  if (status.reblog) return isGameStatus(status.reblog);
  if (status.account?.acct === systemAcct) return true;
  // 시스템에게 한 답글 (그냥 하는 말: 멘션이 없어도 컨텐츠 대화)
  if (systemAccountId && status.in_reply_to_account_id === systemAccountId) return true;
  return (status.mentions ?? []).some((mention) => mention.acct === systemAcct);
};

