// 이벤트 무대(웹게임) 효과음 공용 도구: 파일 없이 Web Audio 로 소리를 만든다. 소리 끄기 상태는 무대마다 localStorage 키로 따로 기억한다.
//   const { soundOn, tone, noise } = createStageAudio('ssm:gg-sound');
//   tone(주파수, 시작(초), 길이(초), { type, volume, to })  — 음
//   noise(시작, 길이, 음량, 필터 주파수, 필터 종류)         — 바람·긁는 소리
// 무대 안에서 `const sfx = { 이름: (at = 0) => { tone(...); } }` 처럼 효과음을 조립해 쓴다 (army_stage.tsx · greengotts_stage.tsx 참고).

export const createStageAudio = (storageKey: string) => {
  const soundOn = () => {
    try { return window.localStorage.getItem(storageKey) !== 'off'; } catch { return true; }
  };
  let context: AudioContext | null = null;
  const audio = () => {
    if (!soundOn()) return null;
    try {
      context ??= new AudioContext();
      if (context.state === 'suspended') void context.resume();
      return context;
    } catch {
      return null;
    }
  };

  const tone = (freq: number, at: number, length: number, options: { type?: OscillatorType; volume?: number; to?: number } = {}) => {
    const ctx = audio();
    if (!ctx) return;
    const start = ctx.currentTime + at;
    const oscillator = ctx.createOscillator();
    const gain = ctx.createGain();
    oscillator.type = options.type ?? 'sine';
    oscillator.frequency.setValueAtTime(freq, start);
    if (options.to) oscillator.frequency.exponentialRampToValueAtTime(options.to, start + length);
    gain.gain.setValueAtTime(0.0001, start);
    gain.gain.exponentialRampToValueAtTime(options.volume ?? 0.2, start + 0.02);
    gain.gain.exponentialRampToValueAtTime(0.0001, start + length);
    oscillator.connect(gain);
    gain.connect(ctx.destination);
    oscillator.start(start);
    oscillator.stop(start + length + 0.05);
  };

  const noise = (at: number, length: number, volume: number, frequency: number, type: BiquadFilterType = 'highpass') => {
    const ctx = audio();
    if (!ctx) return;
    const start = ctx.currentTime + at;
    const buffer = ctx.createBuffer(1, Math.ceil(ctx.sampleRate * length), ctx.sampleRate);
    const data = buffer.getChannelData(0);
    for (let index = 0; index < data.length; index += 1) data[index] = ((Math.random() * 2) - 1) * Math.sin((index / data.length) * Math.PI);
    const source = ctx.createBufferSource();
    source.buffer = buffer;
    const filter = ctx.createBiquadFilter();
    filter.type = type;
    filter.frequency.value = frequency;
    const gain = ctx.createGain();
    gain.gain.value = volume;
    source.connect(filter);
    filter.connect(gain);
    gain.connect(ctx.destination);
    source.start(start);
  };

  return { soundOn, tone, noise };
};
