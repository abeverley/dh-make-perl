#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More 'no_plan';

use DhMakePerl;
use Config;
use File::Find::Rule;

# Check to see if our module list contains some obvious candidates.
my $maker = DhMakePerl->new();

foreach my $module ( qw(Fatal File::Copy FindBin CGI IO::Handle Safe) ) {
    ok($maker->is_core_module($module), "$module should be a core module");
}

my @files = File::Find::Rule->file()
                            ->name('*.pm')
                            ->in(
                                "/usr/share/perl/$Config{version}",
                                "/usr/lib/perl/$Config{version}",
                            );

for (@files) {
    s{/usr/(?:share|lib)/perl/$Config{version}/}{}o;

    s{/}{::}g;
    s/\.pm$//;

    ok( $maker->is_core_module($_), "$_ is core" );
}
