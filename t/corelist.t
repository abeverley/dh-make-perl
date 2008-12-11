#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More 'no_plan';

use DhMakePerl;

# Check to see if our module list contains some obvious candidates.

foreach my $module ( qw(Fatal File::Copy FindBin CGI IO::Handle Safe) ) {
    ok(DhMakePerl::is_core_module($module), "$module should be a core module");
}
