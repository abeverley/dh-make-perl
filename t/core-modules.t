#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More tests => 7;

use Debian::AptContents;

my $apt = 'Debian::AptContents';

is( $apt->find_core_perl_dependency('Module::CoreList'), 'perl (>= 5.10.0)',
    'Module::CoreList is in 5.10' );

is( $apt->find_core_perl_dependency( 'Module::CoreList', '2.12' ), 'perl (>= 5.10.0)',
    'Module::CoreList 2.12 is in 5.10' );

# 2.17 is in 5.10.1, which is not in Debian
is( $apt->find_core_perl_dependency( 'Module::CoreList', '2.17' ), 'perl (>= 5.10.1)',
    'Module::CoreList 2.17 is in 5.10.1' );

# try with an impossibly high version that should never exist
is( $apt->find_core_perl_dependency( 'Module::CoreList', '999999.9' ), undef,
    'Module::CoreList 999999.9 is nowhere' );

# try a bogus module
is( $apt->find_core_perl_dependency( 'Foo::Bar', undef ), undef,
    'Foo::Bar is not in core' );

# try a version that is not in Debian's perl
# this will fail when Debian's perl is sufficiently new
is( $apt->find_core_perl_dependency( 'Module::CoreList', '2.19' ), undef ,
    'Module::CoreList 2.19 is not in Debian\'s perl' );

# M::B 0.3603 is in perl 5.11.4
# perl 5.10.1 has M:B 0.340201 which may fool us
is( $apt->find_core_perl_dependency( 'Module::Build', '0.3603' ),
    undef, 'Module::Build 0.3603 is not in Debian\'s perl' );
