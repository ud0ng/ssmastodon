import { createSelector } from '@reduxjs/toolkit';
import type { Map as ImmutableMap } from 'immutable';

import { compareId } from 'mastodon/compare_id';
import { botAccountIds, systemAccountId } from 'mastodon/initial_state';
import type { NotificationGroup } from 'mastodon/models/notification_group';
import type { NotificationGap } from 'mastodon/reducers/notification_groups';
import type { RootState } from 'mastodon/store';

import {
  selectSettingsNotificationsExcludedTypes,
  selectSettingsNotificationsQuickFilterActive,
  selectSettingsNotificationsQuickFilterShow,
} from './settings';

type StatusesMap = ImmutableMap<string, ImmutableMap<string, unknown>>;

const isAwaitingReply = (
  group: NotificationGroup,
  statuses: StatusesMap,
): boolean => {
  if (group.type !== 'mention') return false;
  if (group.visibility === 'public' || !group.visibility) return false;
  if (!group.statusId) return false;
  // 시스템 계정(컨텐츠 진행)과 자동봇(상점) 계정의 멘션은 답장할 멘션에 넣지 않는다
  if (systemAccountId && group.sampleAccountIds.includes(systemAccountId)) return false;
  if (group.sampleAccountIds.some((id) => botAccountIds.includes(id))) return false;

  const status = statuses.get(group.statusId);
  if (!status) return true;

  if (status.get('favourited') === true) return false;
  if (status.get('replied') === true) return false;

  return true;
};

// 같은 사람이 같은 대화에서 연달아 보낸 멘션은 마지막 것만 남긴다:
// 더 나중에 온 같은 사람의 멘션이 이 멘션에 이어서(답글 사슬) 달렸거나, 이 멘션과 같은 툿에 단 답이면 앞의 것은 묻힌 것으로 본다.
// (마지막 것에 답하거나 하트를 눌러 없어지면 앞의 것도 함께 없어진다 — 마지막 것이 답 대기 여부를 정한다)
const isSupersededByLaterMention = (
  group: NotificationGroup,
  groups: (NotificationGroup | NotificationGap)[],
  statuses: StatusesMap,
): boolean => {
  if (group.type !== 'mention' || !group.statusId) return false;

  const sender = group.sampleAccountIds[0];
  const parentId = statuses.get(group.statusId)?.get('in_reply_to_id') as
    | string
    | null
    | undefined;

  return groups.some((other) => {
    if (other.type !== 'mention' || !other.statusId) return false;
    if (other.statusId === group.statusId) return false;
    if (other.sampleAccountIds[0] !== sender) return false;
    if (compareId(other.statusId, group.statusId) <= 0) return false;

    let current = statuses.get(other.statusId);

    for (let depth = 0; current && depth < 10; depth += 1) {
      const replyTo = current.get('in_reply_to_id') as string | null | undefined;

      if (!replyTo) return false;
      if (replyTo === group.statusId) return true;
      if (parentId && replyTo === parentId) return true;

      current = statuses.get(replyTo);
    }

    return false;
  });
};

const awaitingReplyGroups = (
  notifications: (NotificationGroup | NotificationGap)[],
  statuses: StatusesMap,
): (NotificationGroup | NotificationGap)[] =>
  notifications.filter(
    (g) =>
      g.type === 'gap' ||
      (isAwaitingReply(g, statuses) &&
        !isSupersededByLaterMention(g, notifications, statuses)),
  );

/**
 * Filters notifications based on the active filter type.
 * Mentions and DMs ignore excludedTypes to always appear in their respective tabs.
 */
const filterNotificationsByAllowedTypes = (
  showFilterBar: boolean,
  allowedType: string,
  excludedTypes: string[],
  notifications: (NotificationGroup | NotificationGap)[],
  statuses: StatusesMap,
): (NotificationGroup | NotificationGap)[] => {
  // Always show all if no filter bar or "all" is selected
  if (!showFilterBar || allowedType === 'all') {
    return notifications.filter(
      (item) => item.type === 'gap' || !excludedTypes.includes(item.type),
    );
  }

  // Mentions tab: show mentions that are NOT direct (ignore excludedTypes)
  if (allowedType === 'noti_mention') {
    return notifications.filter(
      (g) => g.type === 'gap' || (g.type === 'mention' && g.visibility !== 'direct'),
    );
  }

  // DM tab: show mentions that ARE direct (ignore excludedTypes)
  if (allowedType === 'noti_dm') {
    return notifications.filter(
      (g) => g.type === 'gap' || (g.type === 'mention' && g.visibility === 'direct'),
    );
  }

  if (allowedType === 'noti_pending') {
    return awaitingReplyGroups(notifications, statuses);
  }

  // Other types: apply excludedTypes normally
  return notifications.filter(
    (item) => item.type === 'gap' || (allowedType === item.type && !excludedTypes.includes(item.type)),
  );
};

const selectStatusesMap = (state: RootState) =>
  state.statuses as unknown as StatusesMap;

export const selectPendingMentionGroups = createSelector(
  [
    (state: RootState) =>
      state.notificationGroups.groups as (NotificationGroup | NotificationGap)[],
    selectStatusesMap,
  ],
  (notifications, statuses): (NotificationGroup | NotificationGap)[] =>
    awaitingReplyGroups(notifications, statuses),
);

export const selectNotificationGroups = createSelector(
  [
    selectSettingsNotificationsQuickFilterShow,
    selectSettingsNotificationsQuickFilterActive,
    selectSettingsNotificationsExcludedTypes,
    (state: RootState) => state.notificationGroups.groups,
    selectStatusesMap,
  ],
  filterNotificationsByAllowedTypes,
);

const selectPendingNotificationGroups = createSelector(
  [
    selectSettingsNotificationsQuickFilterShow,
    selectSettingsNotificationsQuickFilterActive,
    selectSettingsNotificationsExcludedTypes,
    (state: RootState) => state.notificationGroups.pendingGroups,
    selectStatusesMap,
  ],
  filterNotificationsByAllowedTypes,
);

export const selectUnreadNotificationGroupsCount = createSelector(
  [
    (s: RootState) => s.notificationGroups.lastReadId,
    selectNotificationGroups,
    selectPendingNotificationGroups,
  ],
  (notificationMarker, groups, pendingGroups) => {
    return (
      groups.filter(
        (group) =>
          group.type !== 'gap' &&
          group.page_max_id &&
          compareId(group.page_max_id, notificationMarker) > 0,
      ).length +
      pendingGroups.filter(
        (group) =>
          group.type !== 'gap' &&
          group.page_max_id &&
          compareId(group.page_max_id, notificationMarker) > 0,
      ).length
    );
  },
);

export const selectAnyPendingNotification = createSelector(
  [
    (s: RootState) => s.notificationGroups.readMarkerId,
    selectNotificationGroups,
  ],
  (notificationMarker, groups) => {
    return groups.some(
      (group) =>
        group.type !== 'gap' &&
        group.page_max_id &&
        compareId(group.page_max_id, notificationMarker) > 0,
    );
  },
);

export const selectPendingNotificationGroupsCount = createSelector(
  [selectPendingNotificationGroups],
  (pendingGroups) =>
    pendingGroups.filter((group) => group.type !== 'gap').length,
);