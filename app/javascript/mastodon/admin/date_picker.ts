// 날짜 칸(input[type=date])을 어디든 누르면 바로 달력이 뜬다 (브라우저 달력). 관리 화면 공통.
export const setupDateInputs = () => {
  document.addEventListener('click', (event) => {
    const input = (event.target as HTMLElement | null)?.closest('input[type="date"]');
    if (!(input instanceof HTMLInputElement) || input.disabled || input.readOnly) return;

    try {
      input.showPicker();
    } catch {
      // showPicker 를 못 쓰는 브라우저는 칸 안의 달력 아이콘을 쓴다
    }
  });
};
