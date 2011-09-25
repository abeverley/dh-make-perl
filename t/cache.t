#!/usr/bin/perl -w

#
# Test we don't get this error when failing to read wnpp cache file:
# "Can't use an undefined value as a HASH reference at /usr/share/perl5/Debian/WNPP/Query.pm line 75."
#
# Bug reported by jawnsy on IRC.
#

use strict;
use warnings;

use Test::More tests => 1;

use FindBin qw($Bin);
use File::Path ();

sub dist_ok($) {
    my $dist_dir = shift;
    my $dist = "$Bin/dists/$dist_dir";

    # Create an unreadable cache file.
    -e "$Bin/contents/wnpp.cache" and ( unlink "$Bin/contents/wnpp.cache"
        or die "unlink($Bin/contents/wnpp.cache): $!" );
    system('touch', "$Bin/contents/wnpp.cache");

    system( "$Bin/../dh-make-perl", "--no-verbose",
            "--home-dir", "$Bin/contents",
            "--apt-contents-dir", "$Bin/contents",
            "--data-dir", "$Bin/../share",
            $ENV{NO_NETWORK} ? '--no-network' : (),
            "--vcs", "none",
            "--sources-list",
            "$Bin/contents/sources.list", "--email", "joemaint\@test.local",
            $dist );

    is( $?, 0, "$dist_dir: system returned 0" );

    # clean after the test
    File::Path::rmtree("$dist/debian");

    unlink "$Bin/contents/Contents.cache" or die "unlink($Bin/contents.cache): $!";
    -e "$Bin/contents/wnpp.cache" and ( unlink "$Bin/contents/wnpp.cache"
        or die "unlink($Bin/contents/wnpp.cache): $!" );
}

$ENV{PERL5LIB} = "lib";
$ENV{DEBFULLNAME} = "Joe Maintainer";

dist_ok('Strange-0.1');
