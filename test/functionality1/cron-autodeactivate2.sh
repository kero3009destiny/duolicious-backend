#!/usr/bin/env bash

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
cd "$script_dir"

source ../util/setup.sh

set -ex

################################################################################
#
# duo_chat=# select * from last;
#      server     | username |  seconds   | state
# ----------------+----------+------------+-------
#  duolicious.app | 2        | 1693678400 |
# (1 row)
#
################################################################################
#
# duo_chat=# select * from limit;
# luser |    lserver     | remote_bare_jid  | ... |    timestamp     | muted_until | unread_count 
# ------+----------------+------------------+-----+------------------+-------------+--------------
# 10    | duolicious.app | 2@duolicious.app | ... | 1693028207630107 |           0 |            0
# (1 row)
#
################################################################################


db_now () {
  local units=${1:-as-seconds}
  local interval=${2:-'0 minutes'}
  local conversion_factor

  if [[ "$units" = 'as-seconds' ]]; then
    conversion_factor=1
  elif [[ "$units" = 'as-microseconds' ]]; then
    conversion_factor=1000000
  else
    return 1
  fi

  q "select (extract(epoch from now() + interval '${interval}') * ${conversion_factor})::bigint"
}

do_test () {
  q "delete from person"
  q "delete from duo_session"
  q "delete from last" duo_chat
  q "delete from inbox" duo_chat

  delete_emails

  ../util/create-user.sh will-be-deactivated 0 0

  ../util/create-user.sh will-remain-active1 0 0
  ../util/create-user.sh will-remain-active2 0 0
  ../util/create-user.sh will-remain-active3 0 0

  q "
  update person set
    email = REPLACE(email, '@example.com', '@duolicious.app');
  "

  q "
  update person set
    -- In case one of the other cron modules deactivated the accounts
    activated = true,

    -- There's a mechanism which prevents accounts from being re-deactivated
    -- immediately after signing in again. This overrides that mechanism.
    sign_in_time = now() - interval '20 minutes'
  "

  local user1uuid=$(get_uuid 'will-be-deactivated@duolicious.app')
  local user2uuid=$(get_uuid 'will-remain-active1@duolicious.app')
  local user3uuid=$(get_uuid 'will-remain-active2@duolicious.app')
  local user4uuid=$(get_uuid 'will-remain-active3@duolicious.app')

  local  days_ago_0=$(db_now as-seconds)
  local  days_ago_1=$(db_now as-seconds '- 11   days')
  local  days_ago_2=$(db_now as-seconds '- 21   days')
  local  days_ago_3=$(db_now as-seconds '- 31   days')

  q "
  insert into last (server, username, seconds, state)
  values
    ('duolicious.app', '$user4uuid', $days_ago_0, ''),
    ('duolicious.app', '$user3uuid', $days_ago_1, ''),
    ('duolicious.app', '$user2uuid', $days_ago_2, ''),
    ('duolicious.app', '$user1uuid', $days_ago_3, '')
  ON CONFLICT (server, username) DO UPDATE SET
    server   = EXCLUDED.server,
    username = EXCLUDED.username,
    seconds  = EXCLUDED.seconds,
    state    = EXCLUDED.state
  " duo_chat

  sleep 2

  [[ "$(q "select 1 from person where activated = false and email like 'will-be-deactivated%' ")" = "1" ]]
  [[ "$(q "select 1 from person where activated = true  and email like 'will-remain-active1%' ")" = "1" ]]
  [[ "$(q "select 1 from person where activated = true  and email like 'will-remain-active2%' ")" = "1" ]]
  [[ "$(q "select 1 from person where activated = true  and email like 'will-remain-active3%' ")" = "1" ]]
  [[ "$(q "select count(*) from duo_session ")" = "3" ]]

  diff \
    <(get_emails) \
    ../../test/fixtures/cron-autodeactivate2-email
}

do_test
