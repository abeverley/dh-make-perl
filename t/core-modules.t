#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More tests => 5;

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
