// 컨텐츠 문구 꾸미기 — 룰 설명·시스템 메시지·방 말풍선.
//   [명령어] → 배지 (색은 디자인 탭의 [대괄호] 색 --ct-bracket, 대괄호는 떼고 보여 준다)
//             [P …] 는 완벽(초록), [T …] 는 조금 노력(주황) 배지 (마법약 결과)
//   (대사)   → 툿과 같은 커뮤니티 테마 (소괄호) 글자색·크기 (dialogue--paren)
//   noEmoji: 서버가 쓴 문구(시스템 메시지·룰) 안의 이모티콘은 지운다 (아이콘만 쓴다). 캐릭터가 입력한 말은 그대로 둔다.
//            단 HP 하트(❤ 🖤 💔)는 하트 아이콘으로 바꿔 보여 준다.
//   people 을 주면 문구 안의 캐릭터 이름을 아바타 | 굵은 이름으로 (시스템 메시지의 '다음 차례: ○○' 등)
import { Fragment } from 'react';

import { GameIcon, stripEmoji } from 'mastodon/components/game_icons';

const PATTERN = /(\[[^\]\n]+\]|\([^)\n]+\)|（[^）\n]+）)/;
const HEARTS = /(❤️?|🖤|💔)/u;

const HEART_ICON: Record<string, string> = { '❤': 'heart-fill', '🖤': 'heart', '💔': 'heart-broken' };

export interface TextPerson {
  name: string;
  avatar?: string;
  color?: string;
}

const escape = (value: string) => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

const withPeople = (text: string, people: TextPerson[], keyPrefix: string): React.ReactNode => {
  const named = people.filter((person) => person.name.trim() !== '');
  if (named.length === 0) return text;

  const byName = new Map(named.map((person) => [person.name, person]));
  const names = [...byName.keys()].sort((a, b) => b.length - a.length).map(escape);
  return text.split(new RegExp(`(${names.join('|')})`)).map((part, index) => {
    const person = byName.get(part);
    if (!person) return <Fragment key={`${keyPrefix}-${index}`}>{part}</Fragment>;
    return (
      <span key={`${keyPrefix}-${index}`} className='command-person' style={{ '--house-color': person.color || 'transparent' } as React.CSSProperties}>
        {person.avatar && <img src={person.avatar} alt='' />}
        <strong>{person.name}</strong>
      </span>
    );
  });
};

const badgeClass = (label: string) => {
  if (/^P(\s|$)/.test(label)) return 'command-badge command-badge--perfect';
  if (/^T(\s|$)/.test(label)) return 'command-badge command-badge--try';
  return 'command-badge';
};

const Plain: React.FC<{ text: string; people: TextPerson[]; keyPrefix: string }> = ({ text, people, keyPrefix }) => (
  <>
    {text.split(PATTERN).map((part, index) => {
      if (part.startsWith('[') && part.endsWith(']')) {
        const label = part.slice(1, -1);
        return <kbd key={index} className={badgeClass(label)}>{label}</kbd>;
      }
      if ((part.startsWith('(') && part.endsWith(')')) || (part.startsWith('（') && part.endsWith('）'))) {
        return <span key={index} className='dialogue dialogue--paren'>{part}</span>;
      }
      return <Fragment key={index}>{withPeople(part, people, `${keyPrefix}${index}`)}</Fragment>;
    })}
  </>
);

export const CommandText: React.FC<{ text: string; people?: TextPerson[]; noEmoji?: boolean }> = ({ text, people = [], noEmoji = false }) => {
  if (!noEmoji) return <Plain text={text} people={people} keyPrefix='t' />;

  return (
    <>
      {text.split(HEARTS).map((segment, index) => {
        const heart = HEART_ICON[segment.replace('\uFE0F', '')];
        if (heart) return <GameIcon key={index} name={heart} className='command-heart' />;
        return <Plain key={index} text={stripEmoji(segment)} people={people} keyPrefix={`s${index}`} />;
      })}
    </>
  );
};

// [명령어]만 있는 말 (말풍선 없이 배지만 보여 준다)
export const isCommandOnly = (text: string) => /\[[^\]\n]+\]/.test(text) && text.replace(/\[[^\]\n]+\]/g, '').trim() === '';
