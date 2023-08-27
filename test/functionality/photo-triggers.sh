#!/usr/bin/env bash

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
cd "$script_dir"

source ../util/setup.sh

set -xe

img1=$(rand_image)

trap "rm $img1" EXIT

echo Create a user who added a photo during onboarding
q "delete from duo_session"
q "delete from person"
q "delete from onboardee"
q "delete from photo_graveyard"
../util/create-user.sh user1 0 1

[[ "$(q "select count(*) from photo")" == "1" ]]
[[ "$(q "select count(*) from person where has_profile_picture_id = 1")" == "1" ]]
[[ "$(q "select count(*) from onboardee_photo")" == "0" ]]
[[ "$(q "select count(*) from photo_graveyard")" == "0" ]]

response=$(jc POST /request-otp -d '{ "email": "user1@example.com" }')
SESSION_TOKEN=$(echo "$response" | jq -r '.session_token')
jc POST /check-otp -d '{ "otp": "000000" }'

echo Change the first photo
c PATCH /profile-info \
  --header "Content-Type: multipart/form-data" \
  -F "1.jpg=@${img1}"

[[ "$(q "select count(*) from photo")" == "1" ]]
[[ "$(q "select count(*) from person where has_profile_picture_id = 1")" == "1" ]]
[[ "$(q "select count(*) from onboardee_photo")" == "0" ]]
[[ "$(q "select count(*) from photo_graveyard")" == "1" ]]

echo Delete the first photo
jc DELETE /profile-info -d '{ "files": [1] }'

[[ "$(q "select count(*) from photo")" == "0" ]]
[[ "$(q "select count(*) from person where has_profile_picture_id = 1")" == "0" ]]
[[ "$(q "select count(*) from onboardee_photo")" == "0" ]]
[[ "$(q "select count(*) from photo_graveyard")" == "2" ]]

echo Create a user who added a photo after onboarding
q "delete from duo_session"
q "delete from person"
q "delete from onboardee"
q "delete from photo_graveyard"
../util/create-user.sh user1 0 0

response=$(jc POST /request-otp -d '{ "email": "user1@example.com" }')
SESSION_TOKEN=$(echo "$response" | jq -r '.session_token')
jc POST /check-otp -d '{ "otp": "000000" }'

[[ "$(q "select count(*) from photo")" == "0" ]]
[[ "$(q "select count(*) from person where has_profile_picture_id = 1")" == "0" ]]
[[ "$(q "select count(*) from onboardee_photo")" == "0" ]]
[[ "$(q "select count(*) from photo_graveyard")" == "0" ]]

echo Add a photo
c PATCH /profile-info \
  --header "Content-Type: multipart/form-data" \
  -F "1.jpg=@${img1}"

[[ "$(q "select count(*) from photo")" == "1" ]]
[[ "$(q "select count(*) from person where has_profile_picture_id = 1")" == "1" ]]
[[ "$(q "select count(*) from onboardee_photo")" == "0" ]]
[[ "$(q "select count(*) from photo_graveyard")" == "0" ]]
