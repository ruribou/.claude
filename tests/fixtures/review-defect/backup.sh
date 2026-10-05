#!/bin/sh
# 指定したファイルのバックアップを作る
src="$1"

eval "cp $src $src.bak"
echo "backup created: $src.bak"
