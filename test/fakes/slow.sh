#!/usr/bin/env bash
# Fake source: sleeps long enough to exceed any sane statusline timeout.
sleep 5
echo "should-have-been-killed"
