#!/bin/bash

set -x

for i in /var/repositories/apt/*
do
   [ -d "$i" ] &&
   (
      cd "$i"

      sed -i -e '/Codename:/a\Update: localreadd\nLimit: 30' -e '/localreadd/d' -e '/Limit/d' conf/distributions

      cat > conf/updates <<EOM
Name: localreadd
Suite: *
Method: copy:$i/dists-bak
VerifyRelease: blindtrust
EOM

      if [ ! -d dists-bak ]
      then
         rm -f dists-bak.1
         mkdir -p dists-bak.1
         rsync -a dists dists-bak.1
         mv dists-bak.1 dists-bak
      fi

      rm -rf db
      reprepro update          # --- Supply password as many times as prompted. # cat /root/.gpg-p
   )
done
