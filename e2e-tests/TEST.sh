#!/bin/bash

init_test_env_as_root()
{
   if ! id "$RUN_USER" 1>/dev/null 2>/dev/null
   then
      ( set +e; useradd -m "$RUN_USER" -G $(id -un); exit 0; )
      ( set +e; usermod "$RUN_USER" -aG sudo,wheel; exit 0; )
   fi

   rm -rf "$WORK_DIR"
   mkdir -p "$WORK_DIR"
   chown -R "$RUN_USER" "$WORK_DIR"
}

launch_sandboxed_test()
{
   eval "export HOME=~$(id -un)" # set HOME correctly when running under sudo

   LOG=/tmp/repo-test-$(date +%s).log
   echo "See $LOG for details"

   exec 9>&1
   exec 1>$LOG 2>&1
   set -x

   CNT=1

   ECHO_TEST()
   {
      NAME=$1; shift;

      echo "####################################################################################" >&9
      echo "RUNNING TEST $CNT: $NAME ... " >&9

      ((++CNT))
   }

   S=0
   T=0
   F=0

   assert()
   {
      local STR="$1"; shift;

      if [ $# -eq 0 ]
      then
         echo " - ERROR: $STR (INVALID ARGS)" >&9
         echo "####################################################################################" >&9
         exit 1
      fi

      if ( set +e; diff -w <("$@" | sort) <(cat - | sort); exit $?; )
      then
         echo " - PASS: $STR" >&9
         ((++S))
      else
         echo " - FAIL: $STR" >&9
         ((++F))
      fi

      ((++T))
   }

   ############################################################
   ECHO_TEST "INIT"

   init_KEY()
   {
      local key_name="$1"; shift;
      local key_pass="$1"; shift;
      local key="$(gpg --list-keys "$key_name Tester" | grep sub | awk '{ print $2 }' | awk -F/ '{ print $2 }')"

      if [ -z "$key" ]
      then
         gpg --with-colons --fingerprint --list-secret-keys "$key_name Tester" \
            | awk -F: '/^fpr/ { print $10 }' \
            | xargs gpg --batch --yes --delete-secret-and-public-key

         gpg --batch --gen-key <<EOM
%echo Generating a basic OpenPGP key
Key-Type: RSA
Key-Length: 2048
Subkey-Type: RSA
Subkey-Length: 2048
Name-Real: $key_name Tester
Name-Comment: passphrase is $key_pass
Name-Email: $key_name.tester@repo.com
Expire-Date: 0
Passphrase: $key_pass
%commit
%echo done
EOM
         key="$(gpg --list-keys "$key_name Tester" | grep sub | awk '{ print $2 }' | awk -F/ '{ print $2 }')"
      fi

      eval "${key_name}_KEY='$key'"
      eval "${key_name}_PASS='$key_pass'"
   }

   init_KEY APT abcd1234
   init_KEY YUM efgh1234

   cat > "$WORK_DIR"/config.repo <<EOM
@ENTRIES = (
   {
      os_name   => "UBUNTU14",
      desc      => "A Repository for UBUNTU14",
      distro    => "trusty",
      type      => "APT",
      component => "mycomp",
      sign_key  => "$APT_KEY",
      key_pass  => "$APT_PASS",
   },
   {
      os_name   => "UBUNTU16",
      desc      => "A Repository for UBUNTU16",
      distro    => "xenial",
      type      => "APT",
      component => "mycomp",
      sign_key  => "$APT_KEY",
      key_pass  => "$APT_PASS",
   },
   {
      os_name   => "RHEL7",
      desc      => "A Repository for RHEL7",
      distro    => "rhel7",
      type      => "YUM",
      component => "mycomp",
      sign_key  => "$YUM_KEY",
      key_pass  => "$YUM_PASS",
   },
);
EOM

   mkdir -p "$WORK_DIR/packages"

   rsync -av ./samples.in/ "$WORK_DIR/packages/"

   assert "INIT:YUM" repomanage --new -k0 "$WORK_DIR/var/repositories/rpm/D1/" <<EOM
EOM

   assert "INIT:APT" reprepro -b "$WORK_DIR/var/repositories/apt/D1" -C mycomp ls zmb1-abc-sample <<EOM
EOM


   ############################################################
   ECHO_TEST "YUM"

   ../repo.pl --config "$WORK_DIR/config.repo" --repo-dir "$WORK_DIR/var/repositories" --repo-name D1 --create-distro --operation=add-pkg --package "$WORK_DIR/packages/r7/zmb1-abc-sample-8.7.8+*64.rpm" --no-interactive

   assert "YUM:ADD-FIRST" repomanage --new -k0 "$WORK_DIR/var/repositories/rpm/D1/rhel7" <<EOM
$WORK_DIR/var/repositories/rpm/D1/rhel7/x86_64/zmb1-abc-sample-8.7.8+1498186382-1.r7.x86_64.rpm
EOM

   ../repo.pl --config "$WORK_DIR/config.repo" --repo-dir "$WORK_DIR/var/repositories" --repo-name D1 --create-distro --operation=add-pkg --package "$WORK_DIR/packages/r7/zmb1-abc-sample-8.7.1+*64.rpm" --no-interactive

   assert "YUM:ADD-OLDER" repomanage --new -k0 "$WORK_DIR"/var/repositories/rpm/D1/rhel7 <<EOM
$WORK_DIR/var/repositories/rpm/D1/rhel7/x86_64/zmb1-abc-sample-8.7.1+1498186375-1.r7.x86_64.rpm
$WORK_DIR/var/repositories/rpm/D1/rhel7/x86_64/zmb1-abc-sample-8.7.8+1498186382-1.r7.x86_64.rpm
EOM

   ../repo.pl --config "$WORK_DIR/config.repo" --repo-dir "$WORK_DIR/var/repositories" --repo-name D1 --create-distro --operation=add-pkg --package "$WORK_DIR/packages/r7/zmb1-abc-sample-8.7.5+*64.rpm" --no-interactive

   assert "YUM:ADD-NEWER" repomanage --new -k0 "$WORK_DIR/var/repositories/rpm/D1/rhel7" <<EOM
$WORK_DIR/var/repositories/rpm/D1/rhel7/x86_64/zmb1-abc-sample-8.7.1+1498186375-1.r7.x86_64.rpm
$WORK_DIR/var/repositories/rpm/D1/rhel7/x86_64/zmb1-abc-sample-8.7.5+1498186379-1.r7.x86_64.rpm
$WORK_DIR/var/repositories/rpm/D1/rhel7/x86_64/zmb1-abc-sample-8.7.8+1498186382-1.r7.x86_64.rpm
EOM

   ../repo.pl --config "$WORK_DIR/config.repo" --repo-dir "$WORK_DIR/var/repositories" --repo-name D1 --create-distro --operation=add-pkg --package "$WORK_DIR/packages/r7/zmb1-abc-sample-8.7.3+*64.rpm" --no-interactive

   assert "YUM:ADD-MIDDLE" repomanage --new -k0 "$WORK_DIR/var/repositories/rpm/D1/rhel7" <<EOM
$WORK_DIR/var/repositories/rpm/D1/rhel7/x86_64/zmb1-abc-sample-8.7.1+1498186375-1.r7.x86_64.rpm
$WORK_DIR/var/repositories/rpm/D1/rhel7/x86_64/zmb1-abc-sample-8.7.3+1498186377-1.r7.x86_64.rpm
$WORK_DIR/var/repositories/rpm/D1/rhel7/x86_64/zmb1-abc-sample-8.7.5+1498186379-1.r7.x86_64.rpm
$WORK_DIR/var/repositories/rpm/D1/rhel7/x86_64/zmb1-abc-sample-8.7.8+1498186382-1.r7.x86_64.rpm
EOM

   ../repo.pl --config "$WORK_DIR/config.repo" --repo-dir "$WORK_DIR/var/repositories" --repo-name D1 --create-distro --operation=rm-pkg --package-name "zmb1-abc-sample" --version "oldest" --os RHEL7 --no-interactive

   assert "YUM:RM-OLDEST" repomanage --new -k0 "$WORK_DIR/var/repositories/rpm/D1/rhel7" <<EOM
$WORK_DIR/var/repositories/rpm/D1/rhel7/x86_64/zmb1-abc-sample-8.7.3+1498186377-1.r7.x86_64.rpm
$WORK_DIR/var/repositories/rpm/D1/rhel7/x86_64/zmb1-abc-sample-8.7.5+1498186379-1.r7.x86_64.rpm
$WORK_DIR/var/repositories/rpm/D1/rhel7/x86_64/zmb1-abc-sample-8.7.8+1498186382-1.r7.x86_64.rpm
EOM

   ../repo.pl --config "$WORK_DIR/config.repo" --repo-dir "$WORK_DIR/var/repositories" --repo-name D1 --create-distro --operation=rm-pkg --package-name "zmb1-abc-sample" --version "newest" --os RHEL7 --no-interactive

   assert "YUM:RM-NEWEST" repomanage --new -k0 "$WORK_DIR/var/repositories/rpm/D1/rhel7" <<EOM
$WORK_DIR/var/repositories/rpm/D1/rhel7/x86_64/zmb1-abc-sample-8.7.3+1498186377-1.r7.x86_64.rpm
$WORK_DIR/var/repositories/rpm/D1/rhel7/x86_64/zmb1-abc-sample-8.7.5+1498186379-1.r7.x86_64.rpm
EOM

   ############################################################
   ECHO_TEST "APT"

   ../repo.pl --config "$WORK_DIR/config.repo" --repo-dir "$WORK_DIR/var/repositories" --repo-name D1 --create-distro --operation=add-pkg --package "$WORK_DIR/packages/u16/zmb1-abc-sample_8.7.8+*64.deb" --no-interactive

   assert "APT:ADD-FIRST" reprepro -b "$WORK_DIR/var/repositories/apt/D1" -C mycomp list xenial zmb1-abc-sample <<EOM
xenial|mycomp|amd64: zmb1-abc-sample 8.7.8+1498186382-1.u16
EOM

   ../repo.pl --config "$WORK_DIR/config.repo" --repo-dir "$WORK_DIR/var/repositories" --repo-name D1 --create-distro --operation=add-pkg --package "$WORK_DIR/packages/u16/zmb1-abc-sample_8.7.1+*64.deb" --no-interactive

   assert "APT:ADD-OLDER" reprepro -b "$WORK_DIR/var/repositories/apt/D1" -C mycomp list xenial zmb1-abc-sample <<EOM
xenial|mycomp|amd64: zmb1-abc-sample 8.7.1+1498186375-1.u16
xenial|mycomp|amd64: zmb1-abc-sample 8.7.8+1498186382-1.u16
EOM

   ../repo.pl --config "$WORK_DIR/config.repo" --repo-dir "$WORK_DIR/var/repositories" --repo-name D1 --create-distro --operation=add-pkg --package "$WORK_DIR/packages/u16/zmb1-abc-sample_8.7.5+*64.deb" --no-interactive

   assert "APT:ADD-NEWER" reprepro -b "$WORK_DIR/var/repositories/apt/D1" -C mycomp list xenial zmb1-abc-sample <<EOM
xenial|mycomp|amd64: zmb1-abc-sample 8.7.1+1498186375-1.u16
xenial|mycomp|amd64: zmb1-abc-sample 8.7.5+1498186379-1.u16
xenial|mycomp|amd64: zmb1-abc-sample 8.7.8+1498186382-1.u16
EOM

   ../repo.pl --config "$WORK_DIR/config.repo" --repo-dir "$WORK_DIR/var/repositories" --repo-name D1 --create-distro --operation=add-pkg --package "$WORK_DIR/packages/u16/zmb1-abc-sample_8.7.3+*64.deb" --no-interactive

   assert "APT:ADD-MIDDLE" reprepro -b "$WORK_DIR/var/repositories/apt/D1" -C mycomp list xenial zmb1-abc-sample <<EOM
xenial|mycomp|amd64: zmb1-abc-sample 8.7.1+1498186375-1.u16
xenial|mycomp|amd64: zmb1-abc-sample 8.7.3+1498186377-1.u16
xenial|mycomp|amd64: zmb1-abc-sample 8.7.5+1498186379-1.u16
xenial|mycomp|amd64: zmb1-abc-sample 8.7.8+1498186382-1.u16
EOM

   ../repo.pl --config "$WORK_DIR/config.repo" --repo-dir "$WORK_DIR/var/repositories" --repo-name D1 --create-distro --operation=rm-pkg --package-name "zmb1-abc-sample" --version "oldest" --os UBUNTU16 --no-interactive

   assert "APT:RM-OLDEST" reprepro -b "$WORK_DIR/var/repositories/apt/D1" -C mycomp list xenial zmb1-abc-sample <<EOM
xenial|mycomp|amd64: zmb1-abc-sample 8.7.3+1498186377-1.u16
xenial|mycomp|amd64: zmb1-abc-sample 8.7.5+1498186379-1.u16
xenial|mycomp|amd64: zmb1-abc-sample 8.7.8+1498186382-1.u16
EOM

   ../repo.pl --config "$WORK_DIR/config.repo" --repo-dir "$WORK_DIR/var/repositories" --repo-name D1 --create-distro --operation=rm-pkg --package-name "zmb1-abc-sample" --version "newest" --os UBUNTU16 --no-interactive

   assert "APT:RM-NEWEST" reprepro -b "$WORK_DIR/var/repositories/apt/D1" -C mycomp list xenial zmb1-abc-sample <<EOM
xenial|mycomp|amd64: zmb1-abc-sample 8.7.3+1498186377-1.u16
xenial|mycomp|amd64: zmb1-abc-sample 8.7.5+1498186379-1.u16
EOM

   ############################################################

   echo "########################################## END #####################################" >&9
   echo " - PASS : $S" >&9
   echo " - FAIL : $F" >&9
   echo " - TOTAL: $T" >&9
   echo "########################################## END #####################################" >&9

   if [ "$F" == "0" ]
   then
      exit 0;
   else
      exit 1;
   fi
}

###############################################################

set -e

if [ $(whoami) != "root" ]
then
   echo "REQUIRES ROOT PERMISSIONS"
   exit 1
fi

cd "$(dirname "$0")"

export WORK_DIR=work-tmp
export RUN_USER=repotest

init_test_env_as_root

exec sudo -u "$RUN_USER" /bin/bash - <<EOM
WORK_DIR="${WORK_DIR}"
$(type launch_sandboxed_test | sed -e '1d');
launch_sandboxed_test "$@"
EOM

###############################################################
