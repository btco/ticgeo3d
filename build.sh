#!/bin/bash
cat meta.lua >out.lua
echo >>out.lua
echo "--GENERATED CODE. DO NOT EDIT." >>out.lua
echo "--Edit the source .lua files instead." >>out.lua
echo >>out.lua
for i in s3 globs ents level rend util game minimap; do
  echo "Including $i.lua..."
  cat $i.lua | grep -Ev '^ *--' | grep -Ev '^ *$' >>out.lua
done
ls -lh out.lua
echo "out.lua generated."

