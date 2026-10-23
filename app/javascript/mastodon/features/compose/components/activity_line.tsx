// 글쓰기 패널: 어제 + 오늘 툿 수·글자 수 한 줄 (재화 칸, 소속 점수 카드). 서버는 일일 활동 스냅샷의 이틀 치만 읽는다.
import { FormattedMessage } from 'react-intl';

import type { DayActivity } from 'mastodon/features/system/use_wallet';

export const ActivityLine: React.FC<{ activity?: DayActivity }> = ({ activity }) => {
  if (!activity) return null;

  return (
    <span className='activity-line'>
      <span>
        <FormattedMessage id='activity.yesterday' defaultMessage='Yesterday {posts} toots · {chars} chars' values={{ posts: activity.yesterday.posts.toLocaleString(), chars: activity.yesterday.chars.toLocaleString() }} />
      </span>
      <span>
        <FormattedMessage id='activity.today' defaultMessage='Today {posts} toots · {chars} chars' values={{ posts: activity.today.posts.toLocaleString(), chars: activity.today.chars.toLocaleString() }} />
      </span>
    </span>
  );
};
