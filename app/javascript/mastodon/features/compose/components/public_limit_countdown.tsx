// 퍼블툿 제한에 걸렸을 때 보여 주는 안내: 남은 시간을 1초마다 세어 준다 (서버 설정 > 운영 > 글쓰기)
import { useEffect, useState } from 'react';

import { FormattedMessage } from 'react-intl';

const pad = (value: number) => String(value).padStart(2, '0');

export const formatRemaining = (seconds: number) => {
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const secs = seconds % 60;
  return hours > 0 ? `${hours}:${pad(minutes)}:${pad(secs)}` : `${pad(minutes)}:${pad(secs)}`;
};

export const PublicLimitCountdown: React.FC<{
  message: string;
  retryAfter: number;
}> = ({ message, retryAfter }) => {
  // 받은 시각 기준으로 센다 (창을 열어 둔 채 시간이 흘러도 맞게)
  const [endsAt] = useState(() => Date.now() + (retryAfter * 1000));
  const [left, setLeft] = useState(retryAfter);

  useEffect(() => {
    const timer = window.setInterval(() => {
      setLeft(Math.max(0, Math.ceil((endsAt - Date.now()) / 1000)));
    }, 1000);

    return () => {
      window.clearInterval(timer);
    };
  }, [endsAt]);

  return (
    <div className='public-limit'>
      <p>{message}</p>
      <p className='public-limit__timer' role='timer'>
        {left > 0 ? (
          <FormattedMessage
            id='compose.public_limit.remaining'
            defaultMessage='Time left: {time}'
            values={{ time: <strong>{formatRemaining(left)}</strong> }}
          />
        ) : (
          <FormattedMessage
            id='compose.public_limit.ready'
            defaultMessage='You can post again now.'
          />
        )}
      </p>
    </div>
  );
};
