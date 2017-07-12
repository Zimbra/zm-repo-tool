#!/usr/bin/perl

use strict;
use warnings;

use Config;
use Cwd;
use Data::Dumper;
use File::Basename;
use File::Copy;
use File::Find;
use Getopt::Long;
use IPC::Cmd qw/run can_run/;
use Term::ANSIColor;

###########################################################################################################################

my $GLOBAL_PATH_TO_SCRIPT_FILE;
my $GLOBAL_PATH_TO_SCRIPT_DIR;
my $GLOBAL_PATH_TO_TOP;
my $CWD;

my %CFG = ();

BEGIN
{
   $ENV{HOME}                  = glob("~$ENV{LOGNAME}");
   $ENV{ANSI_COLORS_DISABLED}  = 1 if ( !-t STDOUT );
   $GLOBAL_PATH_TO_SCRIPT_FILE = Cwd::abs_path(__FILE__);
   $GLOBAL_PATH_TO_SCRIPT_DIR  = dirname($GLOBAL_PATH_TO_SCRIPT_FILE);
   $GLOBAL_PATH_TO_TOP         = dirname($GLOBAL_PATH_TO_SCRIPT_DIR);
   $CWD                        = getcwd();
}

sub LoadConfiguration($;$)
{
   my $args                    = shift;
   my $cfg_file_indirect_param = shift;

   my $cfg_name     = $args->{name};
   my $cmd_hash     = $args->{hash_src};
   my $default_sub  = $args->{default_sub};
   my $validate_sub = $args->{validate_sub};
   my $enabled_sub  = $args->{enabled_sub};
   my $save_sub     = $args->{save_sub} || sub { my $x = shift; return $x; };

   my $cfg_name_desc = (
      sub {
         if ($cfg_name)
         {
            my $o = $cfg_name;

            $o = lc($o);
            $o =~ s/_/-/g;
            $o =~ s/^/--/;
            return "$o (or cfg: $cfg_name)";
         }
        }
   )->();

   my $val;
   my $src;

   if ( !defined $val )
   {
      y/A-Z_/a-z-/ foreach ( my $cmd_name = $cfg_name );

      if ( $cmd_hash && exists $cmd_hash->{$cmd_name} )
      {
         $val = $cmd_hash->{$cmd_name};
         $src = "cmdline";
      }
   }

   if ( !defined $val )
   {
      if ( $cfg_file_indirect_param && $cmd_hash )
      {
         if ( my $cfg_file = $cmd_hash->{$cfg_file_indirect_param} )
         {
            my $hash = LoadProperties($cfg_file)
              if ( -f $cfg_file );

            if ( $hash && exists $hash->{$cfg_name} )
            {
               $val = $hash->{$cfg_name};
               $src = "config (@{[basename($cfg_file)]})";
            }
         }
      }
   }

   if ($enabled_sub)
   {
      if ( !&$enabled_sub($cfg_name_desc) )
      {
         Die("$cfg_name_desc can't be specfied in this context")
           if ( defined $val );

         return;
      }
   }

   my $valid = 1;

   if ( defined $val )
   {
      $valid = &$validate_sub($val)
        if ($validate_sub);
   }

   if ( !defined $val || !$valid )
   {
      if ($default_sub)
      {
         $val = &$default_sub( $cfg_name_desc, $val );
         $src = "default" . ( $valid ? "" : "($src was rejected)" );
      }
   }

   if ( defined $val )
   {
      $valid = &$validate_sub($val)
        if ($validate_sub);

      if ( ref($val) eq "HASH" )
      {
         foreach my $k ( keys %{$val} )
         {
            $CFG{$cfg_name}{$k} = &$save_sub( ${$val}{$k} );

            printf( " %-25s: %-17s : %s\n", $cfg_name, $cmd_hash ? $src : "detected", "{" . $k . " => " . $CFG{$cfg_name}{$k} . "}" );
         }
      }
      elsif ( ref($val) eq "ARRAY" )
      {
         $CFG{$cfg_name} = &$save_sub($val);

         printf( " %-25s: %-17s : %s\n", $cfg_name, $cmd_hash ? $src : "detected", "[" . join( ", ", @{ $CFG{$cfg_name} } ) . "]" );
      }
      else
      {
         $CFG{$cfg_name} = &$save_sub($val);

         printf( " %-25s: %-17s : %s\n", $cfg_name, $cmd_hash ? $src : "detected", $CFG{$cfg_name} );
      }
   }
}


sub Line()
{
   return "=========================================================================================================\n";
}

sub Die($;$)
{
   my $msg  = shift;
   my $info = shift || "";
   my $err  = "$!";

   print "\n";
   print "\n";
   print Line();
   print color('red') . "FAILURE MSG" . color('reset') . " : $msg\n";
   print color('red') . "SYSTEM ERR " . color('reset') . " : $err\n"  if ($err);
   print color('red') . "EXTRA INFO " . color('reset') . " : $info\n" if ($info);
   print "\n";
   print Line();
   print color('red');
   print "--Stack Trace--\n";
   my $i = 1;

   while ( ( my @call_details = ( caller( $i++ ) ) ) )
   {
      print $call_details[1] . ":" . $call_details[2] . " called from " . $call_details[3] . "\n";
   }
   print color('reset');
   print "\n";
   print Line();

   die "END";
}


sub LoadProperties($)
{
   my $f = shift;

   my $x = SlurpFile($f);

   my @cfg_kvs =
     map { $_ =~ s/^\s+|\s+$//g; $_ }    # trim
     map { split( /=/, $_, 2 ) }         # split around =
     map { $_ =~ s/#.*$//g; $_ }         # strip comments
     grep { $_ !~ /^\s*#/ }              # ignore comments
     grep { $_ !~ /^\s*$/ }              # ignore empty lines
     @$x;

   my %ret_hash = ();
   for ( my $e = 0 ; $e < scalar @cfg_kvs ; $e += 2 )
   {
      my $probe_key = $cfg_kvs[$e];
      my $probe_val = $cfg_kvs[ $e + 1 ];

      if ( $probe_key =~ /^%(.*)/ )
      {
         my @val_kv_pair = split( /=/, $probe_val, 2 );

         $ret_hash{$1}{ $val_kv_pair[0] } = $val_kv_pair[1];
      }
      else
      {
         $ret_hash{$probe_key} = $probe_val;
      }
   }

   return \%ret_hash;
}

sub SlurpFile($)
{
   my $f = shift;

   open( FD, "<", "$f" ) || Die( "In open for read", "file='$f'" );

   chomp( my @x = <FD> );
   close(FD);

   return \@x;
}

sub System(@)
{
   my $cmd_str = "@_";

   print color('green') . "#: pwd=@{[Cwd::getcwd()]}" . color('reset') . "\n";
   print color('green') . "#: $cmd_str" . color('reset') . "\n";

   $! = 0;
   my ( $success, $error_message, $full_buf, $stdout_buf, $stderr_buf ) = run( command => \@_, verbose => 1 );

   Die( "cmd='$cmd_str'", $error_message )
     if ( !$success );

   return { msg => $error_message, out => $stdout_buf, err => $stderr_buf };
}

sub ProcessArgs
{
   my $cmd_hash = shift;
   my $grp_sel  = shift;
   my $grp_args = shift;

   s/_/-/g foreach ( my $grp_sel_opt = lc($grp_sel) );

   my $r = ProcessSubArgs( $cmd_hash, $grp_args->{""}, "", $grp_sel_opt );

   foreach my $sub_key ( keys %$grp_args )
   {
      next if ( !$sub_key );

      if ( !$cmd_hash->{$grp_sel_opt} || $sub_key eq $cmd_hash->{$grp_sel_opt} )
      {
         $r += ProcessSubArgs( $cmd_hash, $grp_args->{$sub_key}, $sub_key, $grp_sel_opt );
      }
   }

   exit(0) if ( $r == 0 );
}

sub ProcessSubArgs
{
   my $cmd_hash  = shift;
   my $cmd_args  = shift;
   my $group     = shift;
   my $group_sel = shift;

   my @cmd_opts =
     map { $_->{opt} =~ y/A-Z_/a-z-/; $_; }    # convert the opt named to lowercase to make command line options
     map { { opt => $_->{name}, opt_s => $_->{type} } }    # create a new hash with keys opt, opt_s
     grep { $_->{type} }                                   # get only names which have a valid type
     @$cmd_args;

   my $help_inv  = 0;
   my $help_func = sub {
      if ( $group && $group_sel )
      {
         print "Additional options when --$group_sel=$group: \n"
      }
      else
      {
         print "Usage: $0 <options>\n";
         print "Supported options: \n";
      }
      print "   --" . "$_->{opt}$_->{opt_s}\n" foreach (@cmd_opts);
      $help_inv = 1;
   };

   print Line() if ( !$group );
   my $OP = Getopt::Long::Parser->new;

   $OP->configure( ( ( $group ? () : ("pass_through") ), ("no_ignore_case") ) );

   if ( !$OP->getoptions( $cmd_hash, ( map { $_->{opt} . $_->{opt_s} } @cmd_opts ), help => $help_func ) )
   {
      print Die("wrong commandline options, use --help");
   }

   if ($help_inv)
   {
      push( @ARGV, "--help" );

      return 0;
   }
   else
   {
      LoadConfiguration( $_, "CONFIG" ) foreach (@$cmd_args);
      print Line();

      return 1;
   }
}

sub EvalFile($;$)
{
   my $file = shift;

   Die( "Error in '$file'", "$@" )
     if ( !-f $file );

   my @ENTRIES;

   eval `cat '$file'`;
   Die( "Error in '$file'", "$@" )
     if ($@);

   return \@ENTRIES;
}

sub SanitizePath($)
{
   my $v = shift;

   $v =~ s,/\+,/,g;
   $v =~ s,/$,,g;

   return $v;
}

###########################################################################################################################

use File::Path qw/make_path/;
use Expect;

sub main()
{
   my %cmd_hash;

   my @repo_conf;

   &ProcessArgs(
      \%cmd_hash,
      "OPERATION",
      {
         "" => [
            {
               name         => "CONFIG",
               type         => "=s",
               hash_src     => \%cmd_hash,
               validate_sub => sub {
                  my $v = shift;
                  if ( -T $v )
                  {
                     push( @repo_conf, @{ EvalFile($v) } )
                       if ( @repo_conf == 0 );

                     return 1;
                  }

                  return 0;
               },
               default_sub => sub {
                  return "config.repo";
               },
            },
            {
               name         => "OPERATION",
               type         => "=s",
               hash_src     => \%cmd_hash,
               validate_sub => sub {
                  my $v = shift;
                  return scalar( grep { $v eq $_ } ( "add-pkg", "rm-pkg", "ls-pkg" ) ) > 0;
               },
               default_sub => sub {
                  my $o = shift;
                  Die("$o not unspecfied");
               },
            },
            {
               name         => "REPO_DIR",
               type         => "=s",
               hash_src     => \%cmd_hash,
               validate_sub => undef,
               default_sub  => sub { return "/var/repositories"; },
               save_sub     => sub {
                  return SanitizePath(shift);
               },
            },
            {
               name         => "REPO_NAME",
               type         => "=s",
               hash_src     => \%cmd_hash,
               validate_sub => undef,
               default_sub  => sub {
                  my $o = shift;
                  Die("$o not unspecfied");
               },
               save_sub => sub {
                  return SanitizePath(shift);
               },
            },
            {
               name         => "CREATE_DISTRO",
               type         => "!",
               hash_src     => \%cmd_hash,
               validate_sub => undef,
               default_sub  => sub {
                  return 0;
               },
            },
            {
               name         => "INTERACTIVE",
               type         => "!",
               hash_src     => \%cmd_hash,
               validate_sub => undef,
               default_sub  => sub { return 1; },
            },
         ],
         "add-pkg" => [
            {
               name         => "PACKAGE",
               type         => "=s",
               hash_src     => \%cmd_hash,
               validate_sub => sub {
                  my $v = shift;
                  my @f = glob($v);

                  if ( !( @f != 1 || ( $f[0] !~ m/[.]rpm$/ && $f[0] !~ m/[.]deb$/ ) ) )
                  {
                     $CFG{_PACKAGE_DIR}   = dirname( $f[0] );
                     $CFG{_PACKAGE_FNAME} = basename( $f[0] );

                     $CFG{_PACKAGE_OS} = undef;
                     $CFG{_PACKAGE_OS} = "UBUNTU16"
                       if (
                        $CFG{_PACKAGE_DIR} =~ m/\/u16\//
                        || $CFG{_PACKAGE_FNAME} =~ m/[-]\d[^-]*[.]u16_[a-z0-9]*[.]deb/
                        || $CFG{_PACKAGE_FNAME} =~ m/[-]\d[^-]*[.]16[.]04_[a-z0-9]*[.]deb/
                       );
                     $CFG{_PACKAGE_OS} = "UBUNTU14"
                       if (
                        $CFG{_PACKAGE_DIR} =~ m/\/u14\//
                        || $CFG{_PACKAGE_FNAME} =~ m/[-]\d[^-]*[.]u14_[a-z0-9]*[.]deb/
                        || $CFG{_PACKAGE_FNAME} =~ m/[-]\d[^-]*[.]14[.]04_[a-z0-9]*[.]deb/
                       );
                     $CFG{_PACKAGE_OS} = "UBUNTU12"
                       if (
                        $CFG{_PACKAGE_DIR} =~ m/\/u12\//
                        || $CFG{_PACKAGE_FNAME} =~ m/[-]\d[^-]*[.]u12_[a-z0-9]*[.]deb/
                        || $CFG{_PACKAGE_FNAME} =~ m/[-]\d[^-]*[.]12[.]04_[a-z0-9]*[.]deb/
                       );
                     $CFG{_PACKAGE_OS} = "RHEL7"
                       if (
                        $CFG{_PACKAGE_DIR} =~ m/\/c7\//
                        || $CFG{_PACKAGE_DIR} =~ m/\/r7\//
                        || $CFG{_PACKAGE_DIR} =~ m/\/el7\//
                        || $CFG{_PACKAGE_FNAME} =~ m/[-]\d[^-]*[.]c7[.][a-z_0-9]*[.]rpm/
                        || $CFG{_PACKAGE_FNAME} =~ m/[-]\d[^-]*[.]r7[.][a-z_0-9]*[.]rpm/
                        || $CFG{_PACKAGE_FNAME} =~ m/[-]\d[^-]*[.]el7[.][a-z_0-9]*[.]rpm/
                       );
                     $CFG{_PACKAGE_OS} = "RHEL6"
                       if (
                        $CFG{_PACKAGE_DIR} =~ m/\/c6\//
                        || $CFG{_PACKAGE_DIR} =~ m/\/r6\//
                        || $CFG{_PACKAGE_DIR} =~ m/\/el6\//
                        || $CFG{_PACKAGE_FNAME} =~ m/[-]\d[^-]*[.]c6[.][a-z_0-9]*[.]rpm/
                        || $CFG{_PACKAGE_FNAME} =~ m/[-]\d[^-]*[.]r6[.][a-z_0-9]*[.]rpm/
                        || $CFG{_PACKAGE_FNAME} =~ m/[-]\d[^-]*[.]el6[.][a-z_0-9]*[.]rpm/
                       );

                     return 1;
                  }

                  return 0;
               },
               default_sub => sub {
                  my $o = shift;
                  Die("$o not unspecfied (should expand to a single .deb or .rpm)");
               },
            },
            {
               name         => "OS",
               type         => "=s",
               hash_src     => \%cmd_hash,
               validate_sub => sub {
                  my $v = shift;
                  return grep { lc( $_->{os_name} ) eq lc($v) } @repo_conf;
               },
               default_sub => sub {
                  my $o = shift;

                  return $CFG{_PACKAGE_OS}
                    if ( $CFG{_PACKAGE_OS} );

                  Die("$o not specfied (could not auto detect)");
               },
            },
         ],
         "ls-pkg" => [
            {
               name         => "PACKAGE_NAME",
               type         => "=s",
               hash_src     => \%cmd_hash,
               validate_sub => undef,
               default_sub  => sub {
                  my $o = shift;
                  Die("$o not unspecfied");
               },
            },
            {
               name         => "OS",
               type         => "=s",
               hash_src     => \%cmd_hash,
               validate_sub => sub {
                  my $v = shift;
                  return grep { lc( $_->{os_name} ) eq lc($v) } @repo_conf;
               },
               default_sub => sub {
                  my $o = shift;
                  Die("$o not specfied");
               },
            },
         ],
         "rm-pkg" => [
            {
               name         => "PACKAGE_NAME",
               type         => "=s",
               hash_src     => \%cmd_hash,
               validate_sub => undef,
               default_sub  => sub {
                  my $o = shift;
                  Die("$o not unspecfied");
               },
            },
            {
               name         => "VERSION",
               type         => "=s",
               hash_src     => \%cmd_hash,
               validate_sub => sub {
                  my $v = shift;
                  return scalar( grep { $v eq $_ } ( "newest", "oldest" ) ) > 0;
               },
               default_sub => sub {
                  my $o = shift;
                  Die("$o not unspecfied");
               },
            },
            {
               name         => "OS",
               type         => "=s",
               hash_src     => \%cmd_hash,
               validate_sub => sub {
                  my $v = shift;
                  return grep { lc( $_->{os_name} ) eq lc($v) } @repo_conf;
               },
               default_sub => sub {
                  my $o = shift;
                  Die("$o not specfied");
               },
            },
         ],
      },
   );

   if ( $CFG{INTERACTIVE} )
   {
      print "Press enter to proceed";
      read STDIN, $_, 1;
   }

   system("gpgconf --kill gpg-agent 2>/dev/null");
   system("gpg-agent --daemon --pinentry-program /usr/bin/pinentry-tty 2>/dev/null");

   foreach my $repo ( grep { $CFG{OS} eq $_->{os_name} } @repo_conf )
   {
      print "CHECKING KEY $repo->{sign_key}\n";
      if ( !$repo->{sign_key} || system("gpg --list-keys $repo->{sign_key} >/dev/null") != 0 )
      {
         Die("Key does not exist or unusable");
      }

      handle_apt_repo($repo)
        if ( $repo->{type} eq "APT" );

      handle_yum_repo($repo)
        if ( $repo->{type} eq "YUM" );
   }
}

END
{
   eval {
      local $?;
      system("gpgconf --kill gpg-agent 2>/dev/null");
      print Line();
   }
}

sub handle_apt_repo
{
   my $repo = shift;

   if (
      0
      || !-f "$CFG{REPO_DIR}/apt/$CFG{REPO_NAME}/conf/distributions"
      || system( "grep", "-q", "-w", "-e", $repo->{distro}, "$CFG{REPO_DIR}/apt/$CFG{REPO_NAME}/conf/distributions" ) != 0
     )
   {
      if ( !$CFG{CREATE_DISTRO} )
      {
         Die("REPO MISSING");
      }

      make_path("$CFG{REPO_DIR}/apt/$CFG{REPO_NAME}/conf") or Die("mkdir failed")
        if ( !-d "$CFG{REPO_DIR}/apt/$CFG{REPO_NAME}/conf" );

      if ( !-f "$CFG{REPO_DIR}/apt/$CFG{REPO_NAME}/conf/options" )
      {
         open( FD, ">", "$CFG{REPO_DIR}/apt/$CFG{REPO_NAME}/conf/options" );
         print FD "ask-passphrase\n";
         close(FD);
      }

      open( FD, ">>", "$CFG{REPO_DIR}/apt/$CFG{REPO_NAME}/conf/distributions" );

      print FD "\n"
        if ( -s "$CFG{REPO_DIR}/apt/$CFG{REPO_NAME}/conf/distributions" != 0 );

      print FD <<EOM
Origin: $repo->{desc}
Label: $repo->{desc}
Codename: $repo->{distro}
Components: $repo->{component}
Architectures: amd64 source
SignWith: $repo->{sign_key}
EOM
        ;
      close(FD);

      print "REPO INITIALIZED\n";
   }

   if ( $CFG{OPERATION} eq "ls-pkg" )
   {
      print "\n";
      print "------------------------------------------------------------------------------------------\n";
      print "PACKAGE LISTINGS:\n";
      print "------------------------------------------------------------------------------------------\n";
      {
         if ( -d "$CFG{REPO_DIR}/apt/$CFG{REPO_NAME}/db" && -d "$CFG{REPO_DIR}/apt/$CFG{REPO_NAME}/dists/$repo->{distro}" )
         {
            open( FD, "-|" ) or exec( "reprepro", "-b", "$CFG{REPO_DIR}/apt/$CFG{REPO_NAME}", "-C", $repo->{component}, "list", $repo->{distro}, $CFG{PACKAGE_NAME} );
            chomp( my @f = <FD> );
            close(FD);

            foreach (@f)
            {
               $_ =~ m/.*[|]([^:]*)\s*:\s*([^\s]*)\s*([^\s]*)/;

               my $pkg_arch = $1;
               my $pkg_name = $2;
               my $pkg_ver  = $3;

               print "| $CFG{REPO_NAME} | $repo->{distro} | $repo->{os_name} | $repo->{component} | $pkg_arch | $pkg_name | $pkg_ver |\n";
            }
         }
      }
      print "------------------------------------------------------------------------------------------\n";
      print "\n";
   }
   elsif ( $CFG{OPERATION} eq "rm-pkg" )
   {
      if ( $CFG{VERSION} eq "newest" )
      {
         open( FD, "-|" ) or exec( "reprepro", "-b", "$CFG{REPO_DIR}/apt/$CFG{REPO_NAME}", "-C", $repo->{component}, "list", $repo->{distro}, $CFG{PACKAGE_NAME} );
         chomp( my @f = <FD> );
         close(FD);

         if (@f)
         {
            print "--------------------------\n";
            print "Removing: $f[0]\n";
            print "--------------------------\n";
            print "\n";

            my ( $junk1, $junk2, $v ) = split( / /, $f[0], 3 );
            &repreproCmd( $repo->{key_pass}, "reprepro", "-b", "$CFG{REPO_DIR}/apt/$CFG{REPO_NAME}", "-C", $repo->{component}, "remove", $repo->{distro}, "$CFG{PACKAGE_NAME}=$v" );
         }
      }
      elsif ( $CFG{VERSION} eq "oldest" )
      {
         open( FD, "-|" ) or exec( "reprepro", "-b", "$CFG{REPO_DIR}/apt/$CFG{REPO_NAME}", "-C", $repo->{component}, "list", $repo->{distro}, $CFG{PACKAGE_NAME} );
         chomp( my @f = <FD> );
         close(FD);

         if (@f)
         {
            print "--------------------------\n";
            print "Removing: $f[-1]\n";
            print "--------------------------\n";
            print "\n";

            my ( $junk1, $junk2, $v ) = split( / /, $f[-1], 3 );
            &repreproCmd( $repo->{key_pass}, "reprepro", "-b", "$CFG{REPO_DIR}/apt/$CFG{REPO_NAME}", "-C", $repo->{component}, "remove", $repo->{distro}, "$CFG{PACKAGE_NAME}=$v" );
         }
      }
   }
   elsif ( $CFG{OPERATION} eq "add-pkg" )
   {
      s/$//                       for ( my $deb_file      = $CFG{_PACKAGE_DIR} . "/" . $CFG{_PACKAGE_FNAME} );
      s/[.]deb$/.changes/         for ( my $changes_file  = $deb_file );
      s/_[a-z0-9]*[.]deb$/.dsc/   for ( my $dsc_file      = $deb_file );
      s/_[a-z0-9]*[.]deb$/.tar.*/ for ( my $tar_file_glob = $deb_file );

      Die("PACKAGE '$deb_file' IS MISSING")
        if ( !-f $deb_file );
      Die("PACKAGE '$changes_file' IS MISSING")
        if ( !-f $changes_file );

      print "--------------------------\n";
      print "Signing: $changes_file\n";
      &debsign( $changes_file, $repo->{sign_key}, $repo->{key_pass} );

      print "Adding: $deb_file\n";
      &repreproCmd( $repo->{key_pass}, "reprepro", "-b", "$CFG{REPO_DIR}/apt/$CFG{REPO_NAME}", "-C", $repo->{component}, "includedeb", $repo->{distro}, $deb_file );

      print "Adding: $dsc_file\n" if ( -f $dsc_file );
      &repreproCmd( $repo->{key_pass}, "reprepro", "-b", "$CFG{REPO_DIR}/apt/$CFG{REPO_NAME}", "-C", $repo->{component}, "includedsc", $repo->{distro}, $dsc_file )
        if ( -f $dsc_file );
      print "--------------------------\n";
      print "\n";

      unlink($deb_file);
      unlink($dsc_file)     if ( -f $dsc_file );
      unlink($changes_file) if ( -f $changes_file );
      unlink( glob($tar_file_glob) );
   }
}


sub handle_yum_repo
{
   my $repo = shift;

   if (
      0
      || !-d "$CFG{REPO_DIR}/rpm/$CFG{REPO_NAME}/$repo->{distro}/SRPMS"
      || !-d "$CFG{REPO_DIR}/rpm/$CFG{REPO_NAME}/$repo->{distro}/x86_64"
     )
   {
      if ( !$CFG{CREATE_DISTRO} )
      {
         Die("REPO MISSING");
      }

      make_path("$CFG{REPO_DIR}/rpm/$CFG{REPO_NAME}/$repo->{distro}/SRPMS") or Die("mkdir failed")
        if ( !-d "$CFG{REPO_DIR}/rpm/$CFG{REPO_NAME}/$repo->{distro}/SRPMS" );
      make_path("$CFG{REPO_DIR}/rpm/$CFG{REPO_NAME}/$repo->{distro}/x86_64") or Die("mkdir failed")
        if ( !-d "$CFG{REPO_DIR}/rpm/$CFG{REPO_NAME}/$repo->{distro}/x86_64" );

      print "REPO INITIALIZED\n";
   }

   if ( $CFG{OPERATION} eq "ls-pkg" )
   {
      print "\n";
      print "------------------------------------------------------------------------------------------\n";
      print "PACKAGE LISTINGS:\n";
      print "------------------------------------------------------------------------------------------\n";
      {
         if ( -d "$CFG{REPO_DIR}/rpm/$CFG{REPO_NAME}/$repo->{distro}" )
         {
            open( FD, "-|" ) or exec( "repomanage", "--new", "--keep=0", "$CFG{REPO_DIR}/rpm/$CFG{REPO_NAME}/$repo->{distro}" );
            chomp( my @f = <FD> );
            close(FD);

            foreach ( reverse grep { $_ =~ /\/$CFG{PACKAGE_NAME}-[0-9]/; } @f )
            {
               my @comp = split( /\//, $_ );

               $comp[-1] =~ m/(.*)-([0-9][^-]*-[0-9].*)[.][A-Za-z_0-9]*[.]rpm/;

               my $pkg_name = $1;
               my $pkg_ver  = $2;
               my $pkg_arch = $comp[-2];

               print "| $CFG{REPO_NAME} | $repo->{distro} | $repo->{os_name} | $repo->{component} | $pkg_arch | $pkg_name | $pkg_ver |\n";
            }
         }
      }
      print "------------------------------------------------------------------------------------------\n";
      print "\n";
   }
   elsif ( $CFG{OPERATION} eq "rm-pkg" )
   {
      if ( $CFG{VERSION} eq "newest" )
      {
         open( FD, "-|" ) or exec( "repomanage", "--new", "--keep=1", "$CFG{REPO_DIR}/rpm/$CFG{REPO_NAME}/$repo->{distro}" );
         chomp( my @f = <FD> );
         close(FD);

         my @g = grep { $_ =~ /\/$CFG{PACKAGE_NAME}-[0-9]/; } @f;
         if (@g)
         {
            print "--------------------------\n";
            print "Removing: $g[0]\n";
            print "--------------------------\n";
            print "\n";

            unlink( $g[0] );
            system( "createrepo", "--update", "$CFG{REPO_DIR}/rpm/$CFG{REPO_NAME}/$repo->{distro}" ) and Die("createrepo failed");
         }
      }
      elsif ( $CFG{VERSION} eq "oldest" )
      {
         open( FD, "-|" ) or exec( "repomanage", "--old", "--keep=1", "$CFG{REPO_DIR}/rpm/$CFG{REPO_NAME}/$repo->{distro}" );
         chomp( my @f = <FD> );
         close(FD);

         my @g = grep { $_ =~ /\/$CFG{PACKAGE_NAME}-[0-9]/; } @f;
         if (@g)
         {
            print "--------------------------\n";
            print "Removing: $g[0]\n";
            print "--------------------------\n";
            print "\n";

            unlink( $g[0] );
            system( "createrepo", "--update", "$CFG{REPO_DIR}/rpm/$CFG{REPO_NAME}/$repo->{distro}" ) and Die("createrepo failed");
         }
      }
   }
   elsif ( $CFG{OPERATION} eq "add-pkg" )
   {
      s/[.]src[.]rpm/.rpm/ for ( my $rpm_file  = $CFG{_PACKAGE_DIR} . "/" . $CFG{_PACKAGE_FNAME} );
      s/[.]rpm/.src.rpm/   for ( my $srpm_file = $rpm_file );

      Die("PACKAGE '$rpm_file' IS MISSING")
        if ( !-f $rpm_file );

      print "--------------------------\n";
      print "Signing: $rpm_file\n";
      &rpmSign( $rpm_file, $repo->{sign_key}, $repo->{key_pass} );

      print "Signing: $srpm_file\n" if ( -f $srpm_file );
      &rpmSign( $srpm_file, $repo->{sign_key}, $repo->{key_pass} ) if ( -f $srpm_file );

      print "Adding: $rpm_file\n";
      move( $rpm_file, "$CFG{REPO_DIR}/rpm/$CFG{REPO_NAME}/$repo->{distro}/x86_64/" ) or Die("Could not move $rpm_file");

      print "Adding: $srpm_file\n" if ( -f $srpm_file );
      move( $srpm_file, "$CFG{REPO_DIR}/rpm/$CFG{REPO_NAME}/$repo->{distro}/SRPMS/" ) or Die("Could not move $srpm_file")
        if ( -f $srpm_file );

      system( "createrepo", "--update", "$CFG{REPO_DIR}/rpm/$CFG{REPO_NAME}/$repo->{distro}" ) and Die("createrepo failed");
      print "--------------------------\n";
      print "\n";
   }
}

sub debsign
{
   my $changes_file = shift;
   my $key          = shift;
   my $pass         = shift;

   my $exp = Expect->spawn(
      "debsign",
      "--no-conf"
      , "--re-sign",
      "-k",
      $key,
      $changes_file
     )
     or Die("Cannot spawn debsign");

   my $success = 0;

   $exp->log_stdout(1);

   sleep(1);

   $exp->expect(
      1800,
      [ qr/.*pass\s*phrase:/i, sub { my $fh = shift; print $fh $pass; print $fh "\n"; exp_continue; } ],
      [ qr/Successfully signed/i, sub { $success = 1; exp_continue; } ],
   );

   $exp->soft_close();

   Die("Error in debsign")
     if ( !$success );
}

sub repreproCmd
{
   my $pass = shift;
   my @cmd  = (@_);

   my $exp = Expect->spawn(@cmd) or Die("Cannot spawm reprepro");

   my $success = 1;

   $exp->log_stdout(1);

   sleep(1);

   $exp->expect(
      1800,
      [ qr/.*pass\s*phrase:/i, sub { my $fh = shift; print $fh "$pass\r"; exp_continue; } ],
      [ qr/ERROR/i, sub { $success = 0; exp_continue; } ],
   );

   $exp->soft_close();

   Die("reprepro failed")
     if ( !$success );
}

sub rpmSign
{
   my $package = shift;
   my $key     = shift;
   my $pass    = shift;

   my $exp =
     Expect->spawn(
      "rpmsign",
      "--resign",
      "--define=" . q(%__gpg_sign_cmd %{__gpg} gpg --force-v3-sigs --digest-algo=sha1 --batch --no-verbose --no-armor --passphrase-fd 3 --no-secmem-warning -u "%{_gpg_name}" -sbo %{__signature_filename} %{__plaintext_filename}),
      "--key-id=$key",
      $package
     )
     or Die("Cannot spawn rpmsign");

   $exp->log_stdout(1);

   sleep(1);

   $exp->expect(
      1800,
      [ qr/Enter pass phrase/, sub { my $fh = shift; print $fh $pass; print $fh "\n"; exp_continue; } ]
   );

   $exp->soft_close();
}


main();
