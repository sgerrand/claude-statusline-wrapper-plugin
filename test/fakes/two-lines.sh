#!/usr/bin/env bash
# Fake source: emits two lines. Used to verify the wrapper truncates
# multi-line output to the first line.
printf 'first\nsecond\n'
