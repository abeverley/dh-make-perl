#!perl -T

use Test::More tests => 1;

use DhMakePerl;

use FindBin qw($Bin);
use Parse::DebianChangelog;

plan skip_all => "'no 'debian/changelog' found"
    unless -f "$Bin/../debian/changelog";

my $cl = Parse::DebianChangelog->init->parse( { infile => "$Bin/../debian/changelog" } );

my $pkg_ver = $cl->data( { count => 1   } )->[0]->{Version};
$pkg_ver =~ s/~.+//;        # ignore !foo suffix
$pkg_ver =~ s/-[^-]+$//;    # ignore debian revision
is( $pkg_ver, $DhMakePerl::VERSION, 'Debian package version matches module version' );
