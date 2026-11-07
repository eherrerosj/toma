#!/bin/sh
set -eu
GH_TOKEN=$(gh auth token --hostname github.com --user eherrerosj)
[ -n "$GH_TOKEN" ] || { echo 'Credentials for eherrerosj are required.' >&2; exit 1; }
export GH_TOKEN
exec gh "$@"
