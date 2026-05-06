#!/usr/bin/env bash
# Reports whether stdin contained any bytes. Used to verify passStdin
# routing.
n=$(wc -c)
n=${n//[[:space:]]/}
if (( n > 0 )); then
  echo got
else
  echo none
fi
