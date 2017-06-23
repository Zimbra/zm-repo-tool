#!/bin/bash

set -e

if [ ! -d "../../zm-pkg-tool" ]
then
   git clone git@github.com:Zimbra/zm-pkg-tool.git
fi

make_sample()
{
   local VER="$1"; shift;
   local OUT="$1"; shift;

   # zmb1-abc-sample
   rm -rf build
   mkdir -p build/stage/zmb1-abc-sample/opt/rr/
   cat > build/stage/zmb1-abc-sample/opt/rr/sample.sh <<EOM
echo "abc-sample-ver: ${VER}-1"
EOM

   chmod +x build/stage/zmb1-abc-sample/opt/rr/sample.sh

   ../../zm-pkg-tool/pkg-build.pl --out-type=$OUT --pkg-installs='/opt/rr/' --pkg-name=zmb1-abc-sample --pkg-summary="its zmb-abc-sample $VER" --pkg-version="$VER" --pkg-release=1

   mkdir -p pkgs
   cp -v -a build/dist/* pkgs/
}

for i in $(seq 0 9)
do
   make_sample "8.7.$i+$((1498186374+i*1+0))" binary
done
