import { Link } from 'react-router-dom';

import { domain, version } from 'mastodon/initial_state';

export const LinkFooter: React.FC<{
  multiColumn: boolean;
}> = ({ multiColumn }) => (
  <div className='link-footer'>
    <p>
      <strong>{domain}</strong>{' '}
      <Link
        to='/privacy-policy'
        target={multiColumn ? '_blank' : undefined}
        rel='privacy-policy'
      >
        개인정보처리방침
      </Link>{' '}
      <a href='https://github.com/ud0ng/ssmastodon' target='_blank' rel='noopener' className='version'>v{version}</a>
    </p>
  </div>
);
