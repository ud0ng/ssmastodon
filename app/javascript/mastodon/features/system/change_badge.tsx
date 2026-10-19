// 재화·인벤토리·소속 점수에 새로 들어온 것이 있을 때 다는 붉은 점 (wallet_changes 가 판단)
export const ChangeBadge: React.FC<{ show: boolean }> = ({ show }) => (show ? <span className='change-badge' aria-hidden /> : null);
