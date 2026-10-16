// 컨텐츠 문구 안 [명령어]를 디자인 탭 테마색([대괄호] 색, dialogue--bracket)으로 칠한다 — 룰 설명·시스템 메시지.
// badge: 컨텐츠 세부 화면 룰처럼 명령어를 테마색 배지로 (대괄호는 떼고 보여 준다)
import { Fragment } from 'react';

export const CommandText: React.FC<{ text: string; badge?: boolean }> = ({ text, badge }) => (
  <>
    {text.split(/(\[[^\]\n]+\])/).map((part, index) =>
      part.startsWith('[') && part.endsWith(']') ? (
        badge ? (
          <kbd key={index} className='command-badge'>{part.slice(1, -1)}</kbd>
        ) : (
          <span key={index} className='dialogue dialogue--bracket command-text'>{part}</span>
        )
      ) : (
        <Fragment key={index}>{part}</Fragment>
      ),
    )}
  </>
);
