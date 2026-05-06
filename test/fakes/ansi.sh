#!/usr/bin/env bash
# Fake source: emits an ANSI-colored token. Used to verify the wrapper
# preserves escape sequences end-to-end.
printf '\033[31mRED\033[0m'
