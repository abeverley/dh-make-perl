#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More 'no_plan';
use Test::Deep;

use_ok('Debian::Dependencies');

my $dep_string = 'perl, libfoo-perl (>= 5.7), bar (<= 4)';
my $list = Debian::Dependencies->new($dep_string);

ok( ref($list), 'parsed dep list is a reference' );
is( ref($list), 'Debian::Dependencies', 'parsed dep list is an object' );
is( scalar(@$list), 3, 'parsed deps contain 3 elements' );
is_deeply( [ map( ref, @$list ) ], [ ( 'Debian::Dependency' ) x 3 ], 'Depencencies list contains Dependency refs' );
cmp_deeply(
    $list,
    bless(
        [
            bless( { pkg=>'perl' }, 'Debian::Dependency' ),
            bless( { pkg=>'libfoo-perl', rel=>'>=', ver=>'5.7' }, 'Debian::Dependency' ),
            bless( { pkg=>'bar', rel=>'<=', ver=>'4' }, 'Debian::Dependency' ),
        ],
        'Debian::Dependencies',
    ),
    'Dependencies list parsed' );
is( "$list", $dep_string, 'Dependencies stringifies' );
