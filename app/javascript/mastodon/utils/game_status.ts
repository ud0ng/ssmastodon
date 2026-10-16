// 컨텐츠 툿: 시스템 계정이 쓴 툿, 시스템 계정을 멘션한 툿(명령어). 웹에서는 홈·타임라인·알림에서 숨기고 컨텐츠 메뉴(방)에서만 본다.
// (앱은 그대로 보인다 — 기록용)
import { systemAcct } from 'mastodon/initial_state';

interface StatusLike {
  account?: { acct?: string } | null;
  mentions?: { acct?: string }[] | null;
  reblog?: StatusLike | null;
}

export const isGameStatus = (status: StatusLike | null | undefined): boolean => {
  if (!status || !systemAcct) return false;
  if (status.reblog) return isGameStatus(status.reblog);
  if (status.account?.acct === systemAcct) return true;
  return (status.mentions ?? []).some((mention) => mention.acct === systemAcct);
};

// 계정 타임라인(프로필)은 그대로, 나머지 타임라인(홈·리스트·해시태그 등)에서 뺀다
export const hidesGameStatuses = (timelineId: string) => !timelineId.startsWith('account:');
