#!/bin/bash

set -e

main() {
  SERVICES=""
  SERVICES="$(get_services | sed 's/_stable$//')"

  docker build tools/compare/ -t dockerfilescompare_compare:latest

  for service in $SERVICES; do
    echo "$service:"
    cleanup "$service"
    prepare "$service"
    if quick_compare "$service"; then
      echo "$service's stable image is identical to the latest image!"
      continue
    fi
    do_export "$service"
    compare "$service"
    tag "$service"
    cleanup "$service"
    echo
  done
}

prepare()
{
  local SERVICE="$1"
  prepare_latest "$SERVICE"
  prepare_stable "$SERVICE"
}

prepare_latest()
{
  local SERVICE="$1"
  pull_latest "$SERVICE"
}

prepare_stable()
{
  local SERVICE="$1"
  pull_stable "$SERVICE"
}

quick_compare()
{
  local SERVICE="$1"
  local IMAGE=""
  local LATEST_SHA=""
  local STABLE_SHA=""
  IMAGE="$(get_image_name "$SERVICE")"
  LATEST_SHA="$(docker inspect "${IMAGE}:latest" | grep Id | awk '{ print $2; }' | tr -d ',' | tr -d '"')"
  STABLE_SHA="$(docker inspect "${IMAGE}:stable" | grep Id | awk '{ print $2; }' | tr -d ',' | tr -d '"')"
  if [[ "$LATEST_SHA" == "$STABLE_SHA" ]]; then
    return 0
  fi
  return 1
}

do_export()
{
  local SERVICE="$1"
  do_export_latest "$SERVICE"
  do_export_stable "$SERVICE"
}

do_export_latest()
{
  local SERVICE="$1"
  create_container_latest "$SERVICE"
  export_latest "$SERVICE"
}

do_export_stable()
{
  local SERVICE="$1"
  create_container_stable "$SERVICE"
  export_stable "$SERVICE"
}

docker_compose_latest()
{
  docker-compose -p dockerfiles_compare -f docker-compose.yml "$@"
}

docker_compose_stable()
{
  docker-compose -p dockerfiles_compare -f docker-compose.stable.yml "$@"
}

get_services()
{
  docker_compose_stable config --services
}

pull_latest()
{
  local SERVICE="$1"
  docker_compose_latest pull "$SERVICE"
}

pull_stable()
{
  local SERVICE="$1"
  docker_compose_stable pull "${SERVICE}_stable"
}

get_image_name()
{
  local SERVICE="$1"
  docker_compose_stable config | grep -v " build:" | grep -v " context:" | grep -A1 "$SERVICE" | grep image: | cut -d":" -f2 | tr -d ' '
}

create_container_latest()
{
  local SERVICE="$1"
  docker_compose_latest run --no-deps "$SERVICE" /bin/true
}

create_container_stable()
{
  local SERVICE="$1"
  docker_compose_stable run --no-deps "${SERVICE}_stable" /bin/true
}

remove_containers()
{
  docker_compose_latest down -v
}

export_latest()
{
  local SERVICE="$1"
  mkdir -p tmp
  docker export "dockerfilescompare_${SERVICE}_run_1" -o "tmp/${SERVICE}_latest.tar"
}

export_stable()
{
  local SERVICE="$1"
  mkdir -p tmp
  docker export "dockerfilescompare_${SERVICE}_stable_run_1" -o "tmp/${SERVICE}_stable.tar"
}

compare()
{
  local SERVICE="$1"
  docker run --rm -v "$(pwd)/tmp:/tmp/archives" dockerfilescompare_compare bash /app/compare.sh "$SERVICE" | less
}

tag()
{
  local SERVICE="$1"
  if ask_for_tag "$SERVICE"; then
    do_tag "$SERVICE"
    push "$SERVICE"
  fi
}

ask_for_tag()
(
  set +e
  local SERVICE="$1"
  echo "Do you wish to tag $SERVICE as :stable?"
  select yn in "Yes" "No"; do
    case $yn in
      Yes ) return 0; break;;
      No ) return 1; break;;
    esac
  done
  return 1
)

do_tag()
{
  local SERVICE="$1"
  local IMAGE
  IMAGE="$(get_image_name "$SERVICE")"
  if [ -z "$IMAGE" ]; then
    return 1
  fi
  docker tag "${IMAGE}:stable" "${IMAGE}:old-stable"
  docker tag "${IMAGE}:latest" "${IMAGE}:stable"
}

push()
{
  local SERVICE="$1"
  if ask_for_push "$SERVICE"; then
    do_push "$SERVICE"
  fi
}

ask_for_push()
(
  set +e
  local SERVICE="$1"
  echo "Do you wish to push :stable for $SERVICE now?"
  select yn in "Yes" "No"; do
    case $yn in
      Yes ) return 0; break;;
      No ) return 1; break;;
    esac
  done
  return 1
)

do_push()
{
  local SERVICE="$1"
  local IMAGE=""
  if [ -z "$SERVICE" ]; then
    return 1
  fi
  IMAGE="$(get_image_name "$SERVICE")"
  docker push "${IMAGE}:old-stable"
  docker push "${IMAGE}:stable"
}

cleanup()
{
  local SERVICE="$1"
  cleanup_latest "$SERVICE"
  cleanup_stable "$SERVICE"
}

cleanup_latest()
{
  local SERVICE="$1"
  remove_containers
  if [ -f "tmp/${SERVICE}_latest.tar" ]; then
    rm "tmp/${SERVICE}_latest.tar"
  fi
}

cleanup_stable()
{
  local SERVICE="$1"
  remove_containers
  if [ -f "tmp/${SERVICE}_stable.tar" ]; then
    rm "tmp/${SERVICE}_stable.tar"
  fi
}

main
