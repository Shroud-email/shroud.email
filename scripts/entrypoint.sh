#!/bin/sh
set -ex

/home/elixir/app/bin/shroud eval "Shroud.Release.migrate"
/home/elixir/app/bin/shroud "$@"
