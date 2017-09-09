#!/bin/bash

set -ve
L=geo3d.tic
R=/sdcard/Android/data/com.nesbox.tic/files/TIC-80/geo3d.tic

lt=$(stat -c %Y $L)
rt=$(stat -c %Y $R)

echo "Local  $lt"
echo "Remote $rt"

if [ $lt -gt $rt ]; then
  echo "Local is newer than remote."
  echo -n "Copy LOCAL to REMOTE (y/N)? "
  src=$L
  dest=$R
elif [ $lt -lt $rt ]; then
  echo "Remote is newer than local."
  echo -n "Copy REMOTE to LOCAL (y/N)? "
  src=$R
  dest=$L
else
  echo "Already in sync."
  exit 0
fi

read ans
if [ "$ans" = "y" ]; then
  cp -vf $src $dest
  echo "Copied."
else
  echo "*** Aborted!"
fi

