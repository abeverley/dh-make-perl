#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More tests => 3;

BEGIN {
    use_ok('Debian::Rules');
};

my $r = Debian::Rules->new(
    { lines => [ "#!/usr/bin/make -f\n", "%:\n", "\tdh \$\@\n" ] } );

is( @{ $r->lines  }, 3,  'lines initialized properly' );
ok( $r->is_dh7tiny, "Detects simple dh7tiny-style rules" );
