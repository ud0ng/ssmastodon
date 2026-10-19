// 남은 시간 실시간 카운트다운 (분):(초) — 컨텐츠 카드·진행 중인 컨텐츠·방 목록. 시간이 지나면 00:00.
import { useEffect, useState } from 'react';

const pad = (value: number) => String(value).padStart(2, '0');

export const formatRemaining = (until: string, now: number) => {
  const seconds = Math.max(0, Math.floor((new Date(until).getTime() - now) / 1000));
  return `${pad(Math.floor(seconds / 60))}:${pad(seconds % 60)}`;
};

export const Countdown: React.FC<{ until: string; className?: string }> = ({ until, className }) => {
  const [now, setNow] = useState(() => Date.now());

  useEffect(() => {
    const timer = window.setInterval(() => {
      setNow(Date.now());
    }, 1000);
    return () => {
      window.clearInterval(timer);
    };
  }, []);

  const urgent = new Date(until).getTime() - now < 60_000;

  return (
    <time dateTime={until} className={[className, 'countdown', urgent && 'countdown--urgent'].filter(Boolean).join(' ')}>
      {formatRemaining(until, now)}
    </time>
  );
};

// 효과 남은 시간 (시:분:초, 한 시간이 안 남으면 분:초). 아주 먼 날이면(영구) '영구'
const PERMANENT_MS = 50 * 365 * 86_400_000;

export const Remaining: React.FC<{ until: string; className?: string }> = ({ until, className }) => {
  const [now, setNow] = useState(() => Date.now());

  useEffect(() => {
    const timer = window.setInterval(() => {
      setNow(Date.now());
    }, 1000);
    return () => {
      window.clearInterval(timer);
    };
  }, []);

  const left = new Date(until).getTime() - now;
  if (left > PERMANENT_MS) return <span className={className}>영구</span>;

  const seconds = Math.max(0, Math.floor(left / 1000));
  const hours = Math.floor(seconds / 3600);
  const text = hours > 0 ? `${hours}:${pad(Math.floor((seconds % 3600) / 60))}:${pad(seconds % 60)}` : formatRemaining(until, now);

  return <time dateTime={until} className={[className, 'countdown', left < 60_000 && 'countdown--urgent'].filter(Boolean).join(' ')}>{text}</time>;
};
