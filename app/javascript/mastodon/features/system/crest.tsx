// 소속(기숙사·진영)과 소속 문장: 소속 색 방패에 이름 첫 글자 (이모지 대신). 컨텐츠·성적 화면이 같이 쓴다.
export interface House {
  id: string;
  name: string;
  emoji: string;
  color: string;
  total: number;
}

export const Crest: React.FC<{ house?: House; large?: boolean }> = ({ house, large }) => (
  <span
    className={large ? 'system-crest system-crest--large' : 'system-crest'}
    style={{ '--house-color': house?.color || '#6b5b3e' } as React.CSSProperties}
    title={house?.name}
    aria-hidden
  >
    <span className='system-crest__inner'>{house ? Array.from(house.name)[0] : '?'}</span>
  </span>
);
