#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More tests => 10;
use Test::Exception;

BEGIN {
    use_ok('Debian::Control::FromCPAN');
    use_ok('Debian::Dependency');
};

my $ctl = 'Debian::Control::FromCPAN';
my $dep = 'Debian::Dependency';

dies_ok {
    $ctl->prune_simple_perl_dep( $dep->new('perl|perl-modules') )
} 'prune_simple_perl_dep croaks on alternatives';

is( $ctl->prune_perl_dep( $dep->new('perl-modules') ), 'perl', 'perl-modules is converted to perl' );

is( $ctl->prune_perl_dep( $dep->new('perl-modules|foo') ), 'perl | foo', 'perl-modules is converted to perl in alternatives' );

is( $ctl->prune_perl_dep( $dep->new('perl-base') ), undef, 'plain dependency on perl-base is redundant' );

is( $ctl->prune_perl_dep( $dep->new('perl-modules'), 1 ), undef, 'perl-modules is build-essential' );

is( $ctl->prune_perl_dep( $dep->new('foo|perl-modules'), 1 ), undef, 'redundant alternative makes redundand the whole' );

is( $ctl->prune_perl_dep( $dep->new('perl (>= 5.8.0)'), 1 ), undef, 'perl 5.8.0 is ancient' );

is( $ctl->prune_perl_dep( $dep->new('perl (= 5.8.0)'), 1 ), 'perl (= 5.8.0)', 'perl =5.8.0 is left intact' );
