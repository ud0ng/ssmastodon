// 컨텐츠 문구 꾸미기 — 룰 설명·시스템 메시지·방 말풍선.
//   [명령어] → 배지 (색은 디자인 탭의 [대괄호] 색 --ct-bracket, 대괄호는 떼고 보여 준다)
//   (대사)   → 툿과 같은 커뮤니티 테마 (소괄호) 글자색·크기 (dialogue--paren)
//   서버 문구 안의 이모티콘은 지운다 (아이콘만 쓴다)
//   people 을 주면 문구 안의 캐릭터 이름을 아바타 | 굵은 이름으로 (시스템 메시지의 '다음 차례: ○○' 등)
import { Fragment } from 'react';

import { stripEmoji } from 'mastodon/components/game_icons';

const PATTERN = /(\[[^\]\n]+\]|\([^)\n]+\)|（[^）\n]+）)/;

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

export const CommandText: React.FC<{ text: string; people?: TextPerson[] }> = ({ text, people = [] }) => (
  <>
    {stripEmoji(text).split(PATTERN).map((part, index) => {
      if (part.startsWith('[') && part.endsWith(']')) {
        return <kbd key={index} className='command-badge'>{part.slice(1, -1)}</kbd>;
      }
      if ((part.startsWith('(') && part.endsWith(')')) || (part.startsWith('（') && part.endsWith('）'))) {
        return <span key={index} className='dialogue dialogue--paren'>{part}</span>;
      }
      return <Fragment key={index}>{withPeople(part, people, String(index))}</Fragment>;
    })}
  </>
);

// [명령어]만 있는 말 (말풍선 없이 배지만 보여 준다)
export const isCommandOnly = (text: string) => /\[[^\]\n]+\]/.test(text) && text.replace(/\[[^\]\n]+\]/g, '').trim() === '';
