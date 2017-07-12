# zm-repo-tool

# Prerequisites:

   1. Build reprepro with multi-version support
   1. sudo apt-get install gnupg gnupg2 gnupg-agent createrepo yum-utils libexpect-perl pinentry-tty
   2. sudo apt-get remove reprepro
   3. sudo dpkg -i ./reprepro_*_amd64.deb

# Building reprepro with multi-version support
   1. Go to an appropriate UBUNTU development box (OS should be same as the final deployment box)
   2. sudo apt install libdb-dev libbz2-dev liblzma-dev libarchive-dev shunit2 db-util libgpgme11-dev dpkg-dev debhelper dh-autoreconf dh-make build-essential zlib1g-dev realpath
   3. git clone https://github.com/profitbricks/reprepro.git
   5. cd reprepro
   6. dpkg-buildpackage -d -b -uc -us
   7. scp ../reprepro_*_amd64.deb root@destination:
   8. You may require to patch some files manually if they are not working:
      sed -i -e '/^REPREPRO/s@[(].*[)]@(CDPATH= cd "${0%/*}/.." \&\& pwd)@g' tests/shunit2-helper-functions.sh

# Example:
   /path/../zm-repo-tool/repo.pl \
      --repo-name D1 \
      --create-distro \
      --package ./Z/u16/D1/870/zmb1-abc-svc*.deb \
      --os=UBUNTU16

   /path/../zm-repo-tool/repo.pl \
      --repo-name D1 \
      --create-distro \
      --package ./Z/r7/D1/870/zmb1-abc-svc*.rpm \
      --os=RHEL7

# Test:
   cd e2e-tests && sudo ./TEST.sh
   [![Build Status](https://travis-ci.org/Zimbra/zm-repo-tool.svg)](https://travis-ci.org/Zimbra/zm-repo-tool)

