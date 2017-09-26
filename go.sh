#!/bin/bash
echo "--GENERATED CODE. DO NOT EDIT" >out.lua
for i in s3 globs ents level rend util game; do
  echo "Including $i.lua..."
  cat $i.lua | grep -Ev '^ *--' | grep -Ev '^ *$' >>out.lua
done
ls -lh out.lua
echo "out.lua generated."

