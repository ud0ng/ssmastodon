// 커뮤니티 테마 배경 파티클 (서버 설정 > 디자인 > 배경 파티클): 배경 이미지 위에 작은 점이 천천히 떨어진다 (눈송이처럼).
// particles.js 의 '아래로 떨어지기' 설정을 따라 만든 가벼운 캔버스 (라이브러리 없이).
//   색은 테마가 주는 --ct-particles (낮/밤 따로, ThemeHelper#community_theme_tags). 비어 있으면 그리지 않는다.
//   캔버스는 z-index -1 로 배경(body) 위, 모든 화면 아래에 깔고 마우스를 막지 않는다.
//   움직임 줄이기를 켠 사람에게는 그리지 않는다.

// particles.js 값: 600 × 1000px² 마다 280개, 반지름 0~1.2, 불투명도 0~0.8, 속도 1
const PER_AREA = 280 / (600 * 1000);
const MAX_COUNT = 1200;
const MAX_RADIUS = 1.2;
const MAX_OPACITY = 0.8;
const SPEED = 1;
const COLOR_CHECK_MS = 2000;
// 천천히 떨어지는 점이라 초당 30번만 그려도 똑같아 보인다 (배터리·CPU 절반). 속도는 60번 기준이라 지난 시간만큼 움직인다
const FRAME_MS = 1000 / 30;

interface Particle {
  x: number;
  y: number;
  r: number;
  a: number;
  vx: number;
  vy: number;
}

const readColor = () => getComputedStyle(document.body).getPropertyValue('--ct-particles').trim();

const spawn = (width: number, height: number, top = false): Particle => ({
  x: Math.random() * width,
  y: top ? -MAX_RADIUS * 2 : Math.random() * height,
  r: Math.random() * MAX_RADIUS + 0.1,
  a: Math.random() * MAX_OPACITY + 0.05,
  // 아래로 떨어지되 조금씩 흔들리게 (particles.js 의 straight: false)
  vx: (Math.random() - 0.5) * SPEED * 0.6,
  vy: SPEED * (0.4 + Math.random() * 0.6),
});

export const startCommunityParticles = () => {
  if (!document.body.classList.contains('community-theme') || document.body.classList.contains('admin')) return;
  if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;

  const canvas = document.createElement('canvas');
  canvas.className = 'community-particles';
  canvas.setAttribute('aria-hidden', 'true');
  const context = canvas.getContext('2d');
  if (!context) return;
  document.body.prepend(canvas);

  let particles: Particle[] = [];
  let color = '';
  let width = 0;
  let height = 0;
  let frame = 0;
  let last = 0;

  const resize = () => {
    const ratio = Math.min(window.devicePixelRatio || 1, 2);
    width = window.innerWidth;
    height = window.innerHeight;
    canvas.width = Math.round(width * ratio);
    canvas.height = Math.round(height * ratio);
    context.setTransform(ratio, 0, 0, ratio, 0, 0);
    const count = Math.min(Math.round(width * height * PER_AREA), MAX_COUNT);
    particles = particles.slice(0, count);
    while (particles.length < count) particles.push(spawn(width, height));
  };

  const draw = (now: number) => {
    frame = window.requestAnimationFrame(draw);
    // 화면 주기(60Hz 면 16.7ms)가 조금씩 흔들려도 두 번에 한 번은 그리게 여유를 둔다
    if (now - last < FRAME_MS - 4) return;
    // 탭을 다시 열었을 때처럼 오래 비었으면 한 칸만 움직인다
    const step = last ? Math.min((now - last) / (1000 / 60), 4) : 1;
    last = now;

    context.clearRect(0, 0, width, height);
    context.fillStyle = color;
    for (const particle of particles) {
      particle.x += particle.vx * step;
      particle.y += particle.vy * step;
      // 화면 밖으로 나가면 위에서 다시 (out_mode: out)
      if (particle.y - particle.r > height) Object.assign(particle, spawn(width, height, true));
      if (particle.x < -particle.r) particle.x = width + particle.r;
      else if (particle.x > width + particle.r) particle.x = -particle.r;

      context.globalAlpha = particle.a;
      context.beginPath();
      context.arc(particle.x, particle.y, particle.r, 0, Math.PI * 2);
      context.fill();
    }
    context.globalAlpha = 1;
  };

  const stop = () => {
    window.cancelAnimationFrame(frame);
    frame = 0;
    last = 0;
    context.clearRect(0, 0, width, height);
  };

  // 낮/밤을 바꾸거나 설정이 꺼지면 색이 바뀐다: 가끔 다시 읽어 켜고 끈다
  const sync = () => {
    color = readColor();
    if (!color) stop();
    else if (!frame && !document.hidden) frame = window.requestAnimationFrame(draw);
  };

  window.addEventListener('resize', resize);
  // 탭을 보고 있지 않으면 멈춘다
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) stop();
    else sync();
  });
  window.setInterval(sync, COLOR_CHECK_MS);

  resize();
  sync();
};
