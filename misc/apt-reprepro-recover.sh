#!/bin/bash

if [ $# -ne 1 ]
then
   echo "$0 <apt-repo-base>" 1>&2
   echo "E.g: $0 /var/repositories/apt"
   exit 1;
fi

eval "export HOME=~$(id -un)" # set HOME correctly when running under sudo

APT_REPO_BASE="$1"; shift;

set -x

if [ ! -d "$APT_REPO_BASE" ]
then
   exit 1;
fi

for i in "$APT_REPO_BASE"/*
do
   [ -d "$i" ] &&
   (
      cd "$i"

      if [ -d dists ] && [ -f conf/distributions ]
      then
         echo "attempting recovery (dists->db) for $i..."

         sed -i -e '/Codename:/a\Update: localreadd' -e '/localreadd/d' -e '/Limit:/d' conf/distributions

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

         if [ ! -d db-bak ]
         then
            mv db db-bak
         fi

         rm -rf db

         reprepro update          # --- Supply password as many times as prompted. # cat /root/.gpg-p
      else
         echo "skipping recovery (dists->db) for $i..."
      fi
   )
done
