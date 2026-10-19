import React from 'react';

import type { List } from 'immutable';

import { GameFx, useAccountFx } from 'mastodon/components/game_fx';
import type { Account } from 'mastodon/models/account';

import { autoPlayGif } from '../initial_state';

import { Skeleton } from './skeleton';

interface Props {
  account?: Account;
  others?: List<Account>;
  localDomain?: string;

  afterName?: React.ReactNode;
}

// title: 아이템으로 붙은 칭호 (아래 DisplayName 이 효과 목록에서 찾아 넘긴다)
class DisplayNameInner extends React.PureComponent<Props & { title?: string }> {
  handleMouseEnter: React.ReactEventHandler<HTMLSpanElement> = ({
    currentTarget,
  }) => {
    if (autoPlayGif) {
      return;
    }

    const emojis =
      currentTarget.querySelectorAll<HTMLImageElement>('img.custom-emoji');

    emojis.forEach((emoji) => {
      const originalSrc = emoji.getAttribute('data-original');
      if (originalSrc != null) emoji.src = originalSrc;
    });
  };

  handleMouseLeave: React.ReactEventHandler<HTMLSpanElement> = ({
    currentTarget,
  }) => {
    if (autoPlayGif) {
      return;
    }

    const emojis =
      currentTarget.querySelectorAll<HTMLImageElement>('img.custom-emoji');

    emojis.forEach((emoji) => {
      const staticSrc = emoji.getAttribute('data-static');
      if (staticSrc != null) emoji.src = staticSrc;
    });
  };

  render() {
    const { others, localDomain, afterName, title } = this.props;

    let displayName: React.ReactNode,
      suffix: React.ReactNode,
      account: Account | undefined;

    if (others && others.size > 0) {
      account = others.first();
    } else if (this.props.account) {
      account = this.props.account;
    }

    if (others && others.size > 1) {
      displayName = others
        .take(2)
        .map((a) => (
          <bdi key={a.get('id')}>
            <strong
              className='display-name__html'
              dangerouslySetInnerHTML={{ __html: a.get('display_name_html') }}
            />
          </bdi>
        ))
        .reduce((prev, cur) => [prev, ', ', cur]);

      if (others.size - 2 > 0) {
        suffix = `+${others.size - 2}`;
      }
    } else if (account) {
      let acct = account.get('acct');

      if (!acct.includes('@') && localDomain) {
        acct = `${acct}@${localDomain}`;
      }

      displayName = (
        <bdi>
          <strong
            className='display-name__html'
            dangerouslySetInnerHTML={{
              __html: account.get('display_name_html'),
            }}
          />
        </bdi>
      );
      suffix = <span className='display-name__account'>@{acct}</span>;
    } else {
      displayName = (
        <bdi>
          <strong className='display-name__html'>
            <Skeleton width='10ch' />
          </strong>
        </bdi>
      );
      suffix = (
        <span className='display-name__account'>
          <Skeleton width='7ch' />
        </span>
      );
    }

    return (
      <span
        className={title ? `display-name game-fx-title game-fx-title--${title}` : 'display-name'}
        onMouseEnter={this.handleMouseEnter}
        onMouseLeave={this.handleMouseLeave}
      >
        {afterName ? (
          <span className='display-name__with-badge'>
            {displayName}
            {afterName}
          </span>
        ) : (
          displayName
        )}{' '}
        {suffix}
        {title && <GameFx slot='title' preset={title} />}
      </span>
    );
  }
}

// 한 사람 이름이면 칭호(효과 목록, components/game_fx)를 붙인다
export const DisplayName: React.FC<Props> = (props) => {
  const single = !(props.others && props.others.size > 1);
  const accountId = props.others && props.others.size > 0 ? props.others.first()?.get('id') : props.account?.get('id');
  const { title } = useAccountFx(single ? accountId : undefined);

  return <DisplayNameInner {...props} title={title} />;
};
