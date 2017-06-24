#!/usr/bin/perl
use strict;

use Getopt::Long;
use Sys::Hostname;

my $host = "repo.zimbra.com";
my $repo = "/var/repositories";

print "\n";
print "============================================================================\n";
print "WARNING: You are synchronizing package repositories to S3\n";
print "     repository : $repo\n";
print "     this host  : @{[hostname]}\n";
print "     S3 host    : ${host}\n";
print "============================================================================\n";
print "Type 'yes' to confirm: ";

chomp( my $in = <STDIN> );

if ( $in eq "yes" )
{
   chdir($repo);

   my @rpm_excludes = ();
   my @apt_excludes = map { ( "--exclude", $_ ) } map { s,^apt/,, =~ $_; s,[/]*$,/*, =~ $_; $_; } glob("apt/*/conf/");

   my @rpm_sync = ( "aws", "s3", "sync", "rpm", "s3://$host/rpm", "--acl", "public-read", @rpm_excludes, "--delete", "--cache-control='max-age=3600'" );
   my @apt_sync = ( "aws", "s3", "sync", "apt", "s3://$host/apt", "--acl", "public-read", @apt_excludes, "--delete", "--cache-control='max-age=3600'" );

   print "Syncing to S3...\n";

   system(@apt_sync);
   system(@rpm_sync);

   print "============================================================================\n";
}
else
{
   print "Baling out.\n";
   print "============================================================================\n";
   exit 1;
}
