// 컨텐츠 문구 안 [명령어]를 배지로 보여 준다 — 룰 설명·시스템 메시지·방 말풍선.
// 색은 디자인 탭의 [대괄호] 색(--ct-bracket)을 따른다. 대괄호는 떼고 보여 준다.
import { Fragment } from 'react';

export const CommandText: React.FC<{ text: string }> = ({ text }) => (
  <>
    {text.split(/(\[[^\]\n]+\])/).map((part, index) =>
      part.startsWith('[') && part.endsWith(']') ? (
        <kbd key={index} className='command-badge'>{part.slice(1, -1)}</kbd>
      ) : (
        <Fragment key={index}>{part}</Fragment>
      ),
    )}
  </>
);
