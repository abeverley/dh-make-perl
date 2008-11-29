#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More 'no_plan';

use FindBin qw($Bin);

system( "$Bin/../dh-make-perl", "--no-verbose",
        "--home-dir", "$Bin/contents", "--sources-list",
        "$Bin/contents/sources.list", "$Bin/dists/Strange-0.1" );

is( $?, 0, 'system returned 0' );

