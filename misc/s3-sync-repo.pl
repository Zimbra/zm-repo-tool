#!/usr/bin/perl
use strict;
use Getopt::Long;

my $host = "repo.zimbra.com"

print "Do you want to S3-synchronize the package repository of this machine to S3 $host [yes/no]? ";
my $in = <STDIN>;

if ( $in eq "yes" )
{
   print "Updating S3 with new repository data.\n";

   chdir("/var/repositories");
   qx(aws s3 sync apt s3://$host/apt --acl public-read --exclude "87/conf/*" --exclude "90/conf/*" --delete --cache-control="max-age=3600");
   qx(aws s3 sync rpm s3://$host/rpm --acl public-read --delete --cache-control="max-age=3600");
}
else
{
   print "Baling out.\n";
   exit 1;
}
