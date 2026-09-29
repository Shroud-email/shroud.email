#!/bin/sh
set -ex

/home/elixir/app/bin/shroud eval "Shroud.Release.migrate"
/home/elixir/app/bin/shroud eval "Shroud.Release.create_admin_user"
/home/elixir/app/bin/shroud "$@"
