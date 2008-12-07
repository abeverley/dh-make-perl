#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More tests => 18;

use FindBin qw($Bin);

require_ok "$Bin/../dh-make-perl";        # Load our code for testing.

my $plain = eval{ Dep->new('perl') };
ok( !$@, 'simple Dep constructed' );
is( $plain->pkg, 'perl', 'name parsed correctly' );
is( $plain->rel, undef, "plain dependency has no relation" );
is( $plain->ver, undef, "plain dependency has no version" );

my $ver   = eval { Dep->new('libfoo', '5.6') };
ok( !$@, 'versioned Dep constructed' );
is( $ver->pkg, 'libfoo', 'versioned name parsed' );
is( $ver->ver, '5.6', 'oversion parsed' );
is( $ver->rel, '>=', '>= relation parsed' );

$ver = eval { Dep->new('libfoo (>= 5.6)') };
ok( !$@, 'versioned Dep parsed' );
is( $ver->pkg, 'libfoo', 'package of ver dep' );
is( $ver->rel, '>=', 'relation of ver dep' );
is( $ver->ver, '5.6', 'version of ver dep' );
is( "$ver", 'libfoo (>= 5.6)', 'Versioned Dep stringified' );

my $loe = eval { Dep->new('libbar (<= 1.2)') };
ok( !$@, '<= dependency parsed' );
is( $loe->rel, '<=', '<= dependency detected' );

my $se = eval { Dep->new('libfoo-perl (==1.2)') };
ok( !$@, '== dependency parsed' );
is( $se->rel, '==', '== dependency detected' );

