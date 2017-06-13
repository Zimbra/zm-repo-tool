# zm-repo-tool

# Prerequisites:

   1. Build reprepro with multi-version support
   1. sudo apt-get install gnupg gnupg2 gnupg-agent pinentry-tty createrepo yum-utils
   2. sudo apt-get remove reprepro
   3. sudo dpkg -i ./reprepro_*_amd64.deb

# Building reprepro with multi-version support
   1. Go to an appropriate UBUNTU development box (OS should be same as the final deployment box)
   2. sudo apt install libdb-dev libbz2-dev liblzma-dev libarchive-dev shunit2 db-util libgpgme11-dev dpkg-dev debhelper dh-autoreconf dh-make build-essential zlib1g-dev realpath
   3. git clone https://github.com/profitbricks/reprepro.git
   5. cd reprepro
   6. dpkg-buildpackage -d -b -uc -us
   7. scp ../reprepro_*.deb root@destination:
   8. You may require to patch some files manually if they are not working

      git diff tests/shunit2-helper-functions.sh
      ---------------------------------------------
      diff --git a/tests/shunit2-helper-functions.sh b/tests/shunit2-helper-functions.sh
      index 8f664b8..f24026f 100644
      --- a/tests/shunit2-helper-functions.sh
      +++ b/tests/shunit2-helper-functions.sh
      @@ -15,7 +15,7 @@
      REPO="${0%/*}/testrepo"
      PKGS="${0%/*}/testpkgs"
      ARCH=${ARCH:-$(dpkg-architecture -qDEB_HOST_ARCH)}
      -REPREPRO=$(realpath -m "${0%/*}/.." --relative-base=.)/reprepro
      +REPREPRO=$(CDPATH= cd "${0%/*}/.." && pwd)/reprepro
      VERBOSE_ARGS="${VERBOSE_ARGS-}"

      call() {

      ---------------------------------------------


# Example:
   /path/../zm-repo-tool/repo.pl \
      ... \
      ...

# Test:
   TBD
