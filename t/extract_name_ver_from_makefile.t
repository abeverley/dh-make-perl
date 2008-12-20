#!/usr/bin/perl -w
use strict;
use Test::More 'no_plan';
use FindBin qw($Bin);

use DhMakePerl;
use DhMakePerl::Config;

my $maker = DhMakePerl->new;
$maker->cfg( DhMakePerl::Config->new );

my ($name, $ver);

eval {
  ($name, $ver) = 
    $maker->extract_name_ver_from_makefile("$Bin/makefiles/module-install-autodie.PL");
};

is($@, "", "Calling extract_name_ver_from_makefile should not die on legit file");

is($name, "autodie", "Module name should be autodie");
is($ver,  "1.994",   "Module version should be 1.994");
