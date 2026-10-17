// 도둑 지도 전용 잉크 그림 (양피지 위에 펜으로 그린 느낌). 24×24 칸 안에서 그린 것을 SVG 안 어디든 size 로 크기를 맞춰 놓는다.
import type { ReactNode } from 'react';

export type MapGlyphName = 'foot' | 'stairs' | 'secret' | 'target' | 'visited' | 'eye';

const SHAPES: Record<MapGlyphName, ReactNode> = {
  // 발자국: 발바닥과 뒤꿈치가 엇갈린 두 짝
  foot: (
    <>
      <ellipse cx='8' cy='7' rx='2.8' ry='4.4' transform='rotate(-14 8 7)' />
      <ellipse cx='8.6' cy='14.2' rx='2' ry='2.3' />
      <ellipse cx='16.4' cy='11' rx='2.8' ry='4.4' transform='rotate(14 16.4 11)' />
      <ellipse cx='15.8' cy='18.4' rx='2' ry='2.3' />
    </>
  ),
  // 계단: 오르는 층계
  stairs: <path d='M3 20.5h5.5v-5h5.5v-5h5.5V5.5H21' fill='none' strokeWidth='2.4' strokeLinecap='round' strokeLinejoin='round' />,
  // 비밀 통로: 열쇠 구멍
  secret: (
    <>
      <circle cx='12' cy='8.6' r='4.2' />
      <path d='M9.6 12.4h4.8L16 21H8z' />
    </>
  ),
  // 목표 장소: 네 갈래 별
  target: <path d='M12 1.8l2.7 7.5 7.5 2.7-7.5 2.7L12 22.2 9.3 14.7 1.8 12l7.5-2.7z' />,
  // 다녀온 곳: 도장 찍은 표시
  visited: (
    <>
      <circle cx='12' cy='12' r='9' fill='none' strokeWidth='2' />
      <path d='M7.4 12.6l3.3 3.3 6-6.8' fill='none' strokeWidth='2.4' strokeLinecap='round' strokeLinejoin='round' />
    </>
  ),
  // 호메눔 레벨리오: 눈
  eye: (
    <>
      <path d='M1.8 12S6 5.2 12 5.2 22.2 12 22.2 12 18 18.8 12 18.8 1.8 12 1.8 12z' fill='none' strokeWidth='2' strokeLinejoin='round' />
      <circle cx='12' cy='12' r='3.2' />
    </>
  ),
};

export const MapGlyph: React.FC<{ name: MapGlyphName; x: number; y: number; size?: number; className?: string }> = ({ name, x, y, size = 18, className }) => (
  <g className={['map-glyph', `map-glyph--${name}`, className].filter(Boolean).join(' ')} transform={`translate(${x} ${y}) scale(${size / 24})`} pointerEvents='none'>
    {SHAPES[name]}
  </g>
);
