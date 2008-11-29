#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More 'no_plan';

use FindBin qw($Bin);

my $dist = "$Bin/dists/Strange-0.1";

$ENV{DEBFULLNAME} = "Joe Maintainer";
system( "$Bin/../dh-make-perl", "--no-verbose",
        "--home-dir", "$Bin/contents", "--sources-list",
        "$Bin/contents/sources.list", "--email", "joemaint\@test.local",
        $dist );

is( $?, 0, 'system returned 0' );

use File::Find qw(find);
use Text::Diff qw(diff);

find(\&compare, "$dist/debian");

sub compare
{
    return unless -f $File::Find::name;

    my $diff = diff("$dist/wanted-debian/$_", $File::Find::name);

    $diff = ''
        unless grep { /^[-+] / and not /^[-+] -- Joe Maintainer / }
            split( /\n/, $diff );

    is($diff, '', "No differences to the wanted contents of debian/$_");
}

# clean after the test
find( sub{ unlink $File::Find::name }, "$dist/debian" );

rmdir "$dist/debian" or warn "Error removing $dist/debian: $!\n";
