#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More tests => 3;

use Debian::AptContents;

my $apt = 'Debian::AptContents';

is( $apt->find_core_perl_dependency('Module::CoreList'), 'perl (>= 5.10.0)',
    'Module::CoreList is in 5.10' );

is( $apt->find_core_perl_dependency( 'Module::CoreList', '2.12' ), 'perl (>= 5.10.0)',
    'Module::CoreList 2.12 is in 5.10' );

# 2.17 is in 5.8.9, which is not in Debian
is( $apt->find_core_perl_dependency( 'Module::CoreList', '2.17' ), undef,
    'Module::CoreList 2.17 is not in core' );
