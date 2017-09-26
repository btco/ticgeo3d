#!/bin/bash

set -e
trap "echo '*** ERROR.'; exit 1" ERR

L=fps80.tic
STAT_CMD="stat -c %Y"

if [ -d /sdcard ]; then
  echo "Auto-detected platform: Android."
  R=/sdcard/Android/data/com.nesbox.tic/files/TIC-80/fps80.tic
  echo "TIC-80 file: $R"
elif [ -d /Library ]; then
  echo "Auto-detected platform: MacOSX."
  R="$HOME/Library/Application Support/com.nesbox.tic/TIC-80/fps80.tic"
  STAT_CMD="stat -f %m"
elif [ -d /c/Users ]; then
  echo "Auto-detected platform: Windows"
  R=/c/Users/bruno/AppData/Roaming/com.nesbox.tic/TIC-80/fps80.tic
fi

echo "Local (repo) file:"
echo "  $L"
echo "TIC-80 file:"
echo "  $R"

lt=$($STAT_CMD "$L")
rt=$($STAT_CMD "$R")

if diff -q "$L" "$R"; then
  echo "Already in sync (contents same)."
  exit 0
fi

if [ $lt -gt $rt ]; then
  echo "Local is newer than remote."
  echo -n "Copy LOCAL to REMOTE (y/N)? "
  src="$L"
  dest="$R"
elif [ $lt -lt $rt ]; then
  echo "Remote is newer than local."
  echo -n "Copy REMOTE to LOCAL (y/N)? "
  src="$R"
  dest="$L"
else
  echo "Already in sync (timestamps same)."
  exit 0
fi

read ans
if [ "$ans" = "y" ]; then
  cp -vf "$src" "$dest"
  echo "Copied."
else
  echo "*** Aborted!"
fi

