#!/usr/bin/env bash

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
cd "$script_dir"

source ../util/setup.sh

printf 0 > ../../test/input/disable-ip-rate-limit
printf 0 > ../../test/input/disable-account-rate-limit

set -xe

  jc POST /request-otp -d '{ "email": "user1@example.com" }'
  jc POST /request-otp -d '{ "email": "user1@example.com" }'
  jc POST /request-otp -d '{ "email": "user1@example.com" }'
! jc POST /request-otp -d '{ "email": "user2@example.com" }'

printf 1 > ../../test/input/disable-ip-rate-limit
printf 1 > ../../test/input/disable-account-rate-limit
q 'delete from person'
../util/create-user.sh user1 0 0
../util/create-user.sh user2 0 0
user2id=$(q "select id from person where name = 'user2'")
assume_role user1
printf 0 > ../../test/input/disable-ip-rate-limit
printf 1 > ../../test/input/disable-account-rate-limit

# Only the global rate limit should apply for regular skips
c POST "/skip/${user2id}"
c POST "/unskip/${user2id}"
c POST "/skip/${user2id}"

# The stricter rate limit should apply for reports
  jc POST "/skip/${user2id}" -d '{ "report_reason": "smells bad" }'
   c POST "/unskip/${user2id}"
! jc POST "/skip/${user2id}" -d '{ "report_reason": "bad hair" }'

# Uncached search should be heavily rate-limited
for x in {1..10}
do
  c GET '/search?n=1&o=0'
done
! c GET '/search?n=1&o=0'

# Cached search shouldn't be heavily rate-limited
c GET '/search?n=1&o=1'
c GET '/search?n=1&o=1'
c GET '/search?n=1&o=1'

# Account-based rate limit should apply even if the IP address changes
printf 1 > ../../test/input/disable-ip-rate-limit
printf 0 > ../../test/input/disable-account-rate-limit
for x in {1..12}
do
  printf "256.256.256.${x}" > ../../test/input/mock-ip-address
  c GET '/search?n=1&o=0'
  c POST "/skip/${user2id}"
done
! c GET '/search?n=1&o=0'
! c POST "/skip/${user2id}"

# The rate limit doesn't apply to other accounts
../util/create-user.sh user3 0 0
c GET '/search?n=1&o=0'
