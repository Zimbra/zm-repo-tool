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
   $ENV{ANSI_COLORS_DISABLED} = 1 if ( !-t STDOUT );
   $GLOBAL_PATH_TO_SCRIPT_FILE = Cwd::abs_path(__FILE__);
   $GLOBAL_PATH_TO_SCRIPT_DIR  = dirname($GLOBAL_PATH_TO_SCRIPT_FILE);
   $GLOBAL_PATH_TO_TOP         = dirname($GLOBAL_PATH_TO_SCRIPT_DIR);
   $CWD                        = getcwd();
}

sub LoadConfiguration($)
{
   my $args = shift;

   my $cfg_name     = $args->{name};
   my $cmd_hash     = $args->{hash_src};
   my $default_sub  = $args->{default_sub};
   my $validate_sub = $args->{validate_sub};

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
      if ( $CFG{CFG_DIR} )
      {
         my $file = "$CFG{CFG_DIR}/config.pl";
         my $hash = LoadProperties($file)
           if ( -f $file );

         if ( $hash && exists $hash->{$cfg_name} )
         {
            $val = $hash->{$cfg_name};
            $src = "config"
         }
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
         $val = &$default_sub(
            map {
               if ($_)
               {
                  my $o = $_;

                  $o = lc($o);
                  $o =~ s/_/-/g;
                  $o =~ s/^/--/;
                  "$o (or cfg: $_)";
               }
              } $cfg_name,
            $val
         );
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
            $CFG{$cfg_name}{$k} = ${$val}{$k};

            printf( " %-25s: %-17s : %s\n", $cfg_name, $cmd_hash ? $src : "detected", "{" . $k . " => " . ${$val}{$k} . "}" );
         }
      }
      elsif ( ref($val) eq "ARRAY" )
      {
         $CFG{$cfg_name} = $val;

         printf( " %-25s: %-17s : %s\n", $cfg_name, $cmd_hash ? $src : "detected", "[" . join( ", ", @{ $CFG{$cfg_name} } ) . "]" );
      }
      else
      {
         $CFG{$cfg_name} = $val;

         printf( " %-25s: %-17s : %s\n", $cfg_name, $cmd_hash ? $src : "detected", $val );
      }
   }
}


sub Die($;$)
{
   my $msg  = shift;
   my $info = shift || "";
   my $err  = "$!";

   print "\n";
   print "\n";
   print "=========================================================================================================\n";
   print color('red') . "FAILURE MSG" . color('reset') . " : $msg\n";
   print color('red') . "SYSTEM ERR " . color('reset') . " : $err\n"  if ($err);
   print color('red') . "EXTRA INFO " . color('reset') . " : $info\n" if ($info);
   print "\n";
   print "=========================================================================================================\n";
   print color('red');
   print "--Stack Trace--\n";
   my $i = 1;

   while ( ( my @call_details = ( caller( $i++ ) ) ) )
   {
      print $call_details[1] . ":" . $call_details[2] . " called from " . $call_details[3] . "\n";
   }
   print color('reset');
   print "\n";
   print "=========================================================================================================\n";

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
   my $cmd_args = shift;

   {
      my @cmd_opts =
        map { $_->{opt} =~ y/A-Z_/a-z-/; $_; }    # convert the opt named to lowercase to make command line options
        map { { opt => $_->{name}, opt_s => $_->{type} } }    # create a new hash with keys opt, opt_s
        grep { $_->{type} }                                   # get only names which have a valid type
        @$cmd_args;

      my $help_func = sub {
         print "Usage: $0 <options>\n";
         print "Supported options: \n";
         print "   --" . "$_->{opt}$_->{opt_s}\n" foreach (@cmd_opts);
         exit(0);
      };

      if ( !GetOptions( $cmd_hash, ( map { $_->{opt} . $_->{opt_s} } @cmd_opts ), help => $help_func ) )
      {
         print Die("wrong commandline options, use --help");
      }
   }

   print "=========================================================================================================\n";
   LoadConfiguration($_) foreach (@$cmd_args);
   print "=========================================================================================================\n";
}

sub EvalFile($;$)
{
   my $fname = shift;

   my $file = "$GLOBAL_PATH_TO_SCRIPT_DIR/$fname";

   Die( "Error in '$file'", "$@" )
     if ( !-f $file );

   my @ENTRIES;

   eval `cat '$file'`;
   Die( "Error in '$file'", "$@" )
     if ($@);

   return \@ENTRIES;
}

###########################################################################################################################

use File::Path qw/make_path/;

sub LoadRepoCfg()
{
   my @agg_repos = ();

   push( @agg_repos, @{ EvalFile("config.repo") } );

   return \@agg_repos;
}


sub main()
{
   my %cmd_hash;

   &ProcessArgs(
      \%cmd_hash,

      [
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
            name         => "REPO_DIR",
            type         => "=s",
            hash_src     => \%cmd_hash,
            validate_sub => undef,
            default_sub  => sub { return "/var/repositories"; },
         },
         {
            name         => "SCAN_DIR",
            type         => "=s",
            hash_src     => \%cmd_hash,
            validate_sub => undef,
            default_sub  => sub { return $CWD; },
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
         },
         {
            name         => "INTERACTIVE",
            type         => "!",
            hash_src     => \%cmd_hash,
            validate_sub => undef,
            default_sub  => sub { return 1; },
         },

         #      {
         #         name         => "CREATE_DISTRO_NAME",
         #         type         => "=s",
         #         hash_src     => \%cmd_hash,
         #         validate_sub => undef,
         #         default_sub  => sub { return undef; },
         #      },
         #      {
         #         name         => "SCAN_OS",
         #         type         => "=s",
         #         hash_src     => \%cmd_hash,
         #         validate_sub => undef,
         #         default_sub  => sub { return "all"; },
         #      },
         #      {
         #         name         => "SCAN_OS_CLASS",
         #         type         => "=s",
         #         hash_src     => \%cmd_hash,
         #         validate_sub => undef,
         #         default_sub  => sub { return "all"; },
         #      },
         #      {
         #         name         => "SCAN_PKG_NAME",
         #         type         => "=s",
         #         hash_src     => \%cmd_hash,
         #         validate_sub => undef,
         #         default_sub  => sub { return Die("@_ not unspecfied"); },
         #      },
      ]
   );

   if ( $CFG{INTERACTIVE} )
   {
      print "Press enter to proceed";
      read STDIN, $_, 1;
   }

   my %os2info = @{ LoadRepoCfg() };

   if ( $CFG{CREATE_DISTRO} )
   {
      foreach my $os_code ( sort keys %os2info )
      {
         my $osinfo = $os2info{$os_code};

         init_deb_repo( $os_code, $osinfo )
           if ( $osinfo->{class} =~ m/ubuntu/ );

         init_rpm_repo( $os_code, $osinfo )
           if ( $osinfo->{class} =~ m/rhel/ );
      }
   }
}


sub init_deb_repo
{
   my $os_code = shift;
   my $osinfo  = shift;

   my $dist_codename = $osinfo->{dist_codename};
   my $os_name       = $osinfo->{os_name};
   my $limit         = $osinfo->{limit};
   my $sign_key      = $osinfo->{sign_key};

   print "APT repository - OS_CODE: $os_code, REPO_NAME: $CFG{REPO_NAME}, DISTRO: $dist_codename - ";

   make_path("$CFG{REPO_DIR}/apt/$CFG{REPO_NAME}/conf") or die "mkdir failed: $!"
     if ( !-d "$CFG{REPO_DIR}/apt/$CFG{REPO_NAME}/conf" );

   if (
      0
      || !-f "$CFG{REPO_DIR}/apt/$CFG{REPO_NAME}/conf/distributions"
      || system( "grep", "-q", "-w", "-e", $dist_codename, "$CFG{REPO_DIR}/apt/$CFG{REPO_NAME}/conf/distributions" ) != 0
     )
   {
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
Origin: Zimbra Collaboration Suite $CFG{REPO_NAME} Repository for $os_name
Label: Zimbra Collaboration Suite $CFG{REPO_NAME} Repository for $os_name
Codename: $dist_codename
Components: zimbra
Architectures: amd64 source
SignWith: $sign_key
Limit: $limit
EOM
        ;

      print "INITIALIZED\n";
   }
   else
   {
      print "ALREADY EXISTS\n";
   }
}


sub init_rpm_repo
{
   my $os_code = shift;
   my $osinfo  = shift;

   my $dist_codename = $osinfo->{dist_codename};

   print "RPM repository - OS_CODE: $os_code, REPO_NAME: $CFG{REPO_NAME}, DISTRO: $dist_codename - ";

   if (
      0
      || !-d "$CFG{REPO_DIR}/rpm/$CFG{REPO_NAME}/$dist_codename/SRPMS"
      || !-d "$CFG{REPO_DIR}/rpm/$CFG{REPO_NAME}/$dist_codename/x86_64"
     )
   {
      make_path("$CFG{REPO_DIR}/rpm/$CFG{REPO_NAME}/$dist_codename/SRPMS") or die "mkdir failed: $!"
        if ( !-d "$CFG{REPO_DIR}/rpm/$CFG{REPO_NAME}/$dist_codename/SRPMS" );
      make_path("$CFG{REPO_DIR}/rpm/$CFG{REPO_NAME}/$dist_codename/x86_64") or die "mkdir failed: $!"
        if ( !-d "$CFG{REPO_DIR}/rpm/$CFG{REPO_NAME}/$dist_codename/x86_64" );

      print "INITIALIZED\n";
   }
   else
   {
      print "ALREADY EXISTS\n";
   }
}


main();
