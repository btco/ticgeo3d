#!/bin/bash

if uname | grep -iq darwin; then
  TIC='/Applications/tic.app/Contents/MacOS/tic'
else
  TIC='C:\Users\bruno\Desktop\tic-80\tic.exe'
fi

if ! [ -f "$TIC" ]; then
  echo "** not found: $TIC."
  exit 1
fi

echo "Creating export cartridge."
cp -vf fps80.tic fps80-export.tic

echo "We will now launch TIC with the injected code."
echo "Save the cartridge as 'fps80-export'."
echo "Press ENTER."
read foo

echo "Injecting output code into cart."
"$TIC" fps80-export.tic -code out.lua 

