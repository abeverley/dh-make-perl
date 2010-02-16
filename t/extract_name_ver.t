#!/usr/bin/perl -w
use strict;
use Test::More tests => 3;

use DhMakePerl;
use DhMakePerl::Config;

my $maker = DhMakePerl->new;
$maker->cfg( DhMakePerl::Config->new );

$maker->meta( { name => 'Foo::Bar', version => 'v1.002003' } );

my ($name, $ver);

eval { ( $name, $ver ) = $maker->extract_name_ver; };

is($@, "", "Calling extract_name_ver should not die");

is($name, "Foo-Bar", "Dist name should be Foo-Bar");
is($ver,  "1.2.3",   "Dist version should be 1.2.3");