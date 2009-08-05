#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More tests => 7;

use DhMakePerl;
use Config;
use File::Find::Rule;

# Check to see if our module list contains some obvious candidates.
my $maker = DhMakePerl->new();

foreach my $module ( qw(Fatal File::Copy FindBin CGI IO::Handle Safe) ) {
    ok($maker->is_core_module($module), "$module should be a core module");
}

ok( !$maker->is_core_module('Foo::Bar'), 'Foo::Bar is not a core module' );
