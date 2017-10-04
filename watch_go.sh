#!/bin/bash

oldsum=""
said=
while true; do
 lua_files=`/bin/ls -1 *.lua | grep -v out.lua`
 cursum=`cat $lua_files | md5`
 if [ "$cursum" != "$oldsum" ]; then
  echo "Generating..."
  bash go.sh
  oldsum="$cursum"
  said=
 else
  [ -z "$said" ] && echo "Waiting for changes in lua files..."
  said=y
 fi
 sleep 2
done

