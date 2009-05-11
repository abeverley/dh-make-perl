#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More tests => 145;

BEGIN {
    use_ok('Debian::Dependency');

};

my $plain = eval{ Debian::Dependency->new('perl') };
ok( !$@, 'simple Dep constructed' );
is( $plain->pkg, 'perl', 'name parsed correctly' );
is( $plain->rel, undef, "plain dependency has no relation" );
is( $plain->ver, undef, "plain dependency has no version" );

my $ver   = eval { Debian::Dependency->new('libfoo', '5.6') };
ok( !$@, 'versioned Dep constructed' );
is( $ver->pkg, 'libfoo', 'versioned name parsed' );
is( $ver->ver, '5.6', 'oversion parsed' );
is( $ver->rel, '>=', '>= relation parsed' );

$ver = eval { Debian::Dependency->new('libfoo (>= 5.6)') };
ok( !$@, 'versioned Dep parsed' );
is( $ver->pkg, 'libfoo', 'package of ver dep' );
is( $ver->rel, '>=', 'relation of ver dep' );
is( $ver->ver, '5.6', 'version of ver dep' );
is( "$ver", 'libfoo (>= 5.6)', 'Versioned Dep stringified' );

my $loe = eval { Debian::Dependency->new('libbar (<= 1.2)') };
ok( !$@, '<= dependency parsed' );
is( $loe->rel, '<=', '<= dependency detected' );

my $se = eval { Debian::Dependency->new('libfoo-perl (=1.2)') };
ok( !$@, '= dependency parsed' );
is( $se->rel, '=', '= dependency detected' );

my $d = Debian::Dependency->new( 'foo', '0' );
is( "$d", 'foo', 'zero version is ignored when given in new' );

$d = Debian::Dependency->new( 'foo', '0.000' );
is( "$d", 'foo', '0.000 version is ignored when given in new' );

$d = Debian::Dependency->new('libfoo (>= 0.000)');
is( "$d", 'libfoo', 'zero version is ignored when parsing' );

sub sat( $ $ $ ) {
    my( $dep, $test, $expected ) = @_;

    ok( $dep->satisfies($test) == $expected, "$dep ".($expected ? 'satisfies' : "doesn't satisfy"). " $test" );
}

my $dep = Debian::Dependency->new('foo');
sat( $dep, 'bar', 0 );
sat( $dep, 'foo', 1 );
sat( $dep, 'foo (>> 4)', 0 );
sat( $dep, 'foo (>= 4)', 0 );
sat( $dep, 'foo (= 4)',  0 );
sat( $dep, 'foo (<= 4)', 0 );
sat( $dep, 'foo (<< 4)', 0 );

$dep = Debian::Dependency->new('foo (>> 4)');
sat( $dep, 'bar', 0 );
sat( $dep, 'foo', 1 );

sat( $dep, 'foo (>> 3)', 1 );
sat( $dep, 'foo (>= 3)', 1 );
sat( $dep, 'foo (= 3)',  0 );
sat( $dep, 'foo (<= 3)', 0 );
sat( $dep, 'foo (<< 3)', 0 );

sat( $dep, 'foo (>> 4)', 1 );
sat( $dep, 'foo (>= 4)', 1 );
sat( $dep, 'foo (= 4)',  0 );
sat( $dep, 'foo (<= 4)', 0 );
sat( $dep, 'foo (<< 4)', 0 );

sat( $dep, 'foo (>> 5)', 0 );
sat( $dep, 'foo (>= 5)', 0 );
sat( $dep, 'foo (= 5)',  0 );
sat( $dep, 'foo (<= 5)', 0 );
sat( $dep, 'foo (<< 5)', 0 );

$dep = Debian::Dependency->new('foo (>= 4)');
sat( $dep, 'bar', 0 );
sat( $dep, 'foo', 1 );

sat( $dep, 'foo (>> 4)', 0 );
sat( $dep, 'foo (>= 4)', 1 );
sat( $dep, 'foo (= 4)',  0 );
sat( $dep, 'foo (<= 4)', 0 );
sat( $dep, 'foo (<< 4)', 0 );

sat( $dep, 'foo (>> 3)', 1 );
sat( $dep, 'foo (>= 3)', 1 );
sat( $dep, 'foo (= 3)',  0 );
sat( $dep, 'foo (<= 3)', 0 );
sat( $dep, 'foo (<< 3)', 0 );

sat( $dep, 'foo (>> 5)', 0 );
sat( $dep, 'foo (>= 5)', 0 );
sat( $dep, 'foo (= 5)',  0 );
sat( $dep, 'foo (<= 5)', 0 );
sat( $dep, 'foo (<< 5)', 0 );

$dep = Debian::Dependency->new('foo (= 4)');
sat( $dep, 'bar', 0 );
sat( $dep, 'foo', 1 );

sat( $dep, 'foo (>> 4)', 0 );
sat( $dep, 'foo (>= 4)', 1 );
sat( $dep, 'foo (= 4)',  1 );
sat( $dep, 'foo (<= 4)', 1 );
sat( $dep, 'foo (<< 4)', 0 );

sat( $dep, 'foo (>> 3)', 1 );
sat( $dep, 'foo (>= 3)', 1 );
sat( $dep, 'foo (= 3)',  0 );
sat( $dep, 'foo (<= 3)', 0 );
sat( $dep, 'foo (<< 3)', 0 );

sat( $dep, 'foo (>> 5)', 0 );
sat( $dep, 'foo (>= 5)', 0 );
sat( $dep, 'foo (= 5)',  0 );
sat( $dep, 'foo (<= 5)', 1 );
sat( $dep, 'foo (<< 5)', 1 );

$dep = Debian::Dependency->new('foo (<= 4)');
sat( $dep, 'bar', 0 );
sat( $dep, 'foo', 1 );

sat( $dep, 'foo (>> 4)', 0 );
sat( $dep, 'foo (>= 4)', 0 );
sat( $dep, 'foo (= 4)',  0 );
sat( $dep, 'foo (<= 4)', 1 );
sat( $dep, 'foo (<< 4)', 0 );

sat( $dep, 'foo (>> 3)', 0 );
sat( $dep, 'foo (>= 3)', 0 );
sat( $dep, 'foo (= 3)',  0 );
sat( $dep, 'foo (<= 3)', 0 );
sat( $dep, 'foo (<< 3)', 0 );

sat( $dep, 'foo (>> 5)', 0 );
sat( $dep, 'foo (>= 5)', 0 );
sat( $dep, 'foo (= 5)',  0 );
sat( $dep, 'foo (<= 5)', 1 );
sat( $dep, 'foo (<< 5)', 1 );

$dep = Debian::Dependency->new('foo (<< 4)');
sat( $dep, 'bar', 0 );
sat( $dep, 'foo', 1 );

sat( $dep, 'foo (>> 4)', 0 );
sat( $dep, 'foo (>= 4)', 0 );
sat( $dep, 'foo (= 4)',  0 );
sat( $dep, 'foo (<= 4)', 1 );
sat( $dep, 'foo (<< 4)', 1 );

sat( $dep, 'foo (>> 3)', 0 );
sat( $dep, 'foo (>= 3)', 0 );
sat( $dep, 'foo (= 3)',  0 );
sat( $dep, 'foo (<= 3)', 0 );
sat( $dep, 'foo (<< 3)', 0 );

sat( $dep, 'foo (>> 5)', 0 );
sat( $dep, 'foo (>= 5)', 0 );
sat( $dep, 'foo (= 5)',  0 );
sat( $dep, 'foo (<= 5)', 1 );
sat( $dep, 'foo (<< 5)', 1 );

sub comp {
    my( $one, $two, $expected ) = @_;

    $one = Debian::Dependency->new($one);
    $two = Debian::Dependency->new($two);

    is( $one <=> $two, $expected,
        $expected
        ? (
            ( $expected == -1 )
            ? "$one is less than $two"
            : "$one is greater than $two"
        )
        : "$one and $two are equal"
    );
}

comp( 'foo', 'bar', 1 );
comp( 'bar', 'foo', -1 );
comp( 'foo', 'foo', 0 );
comp( 'foo', 'foo (>= 2)', -1 );
comp( 'foo (>= 2)', 'foo', 1 );
comp( 'foo (<< 2)', 'foo (<= 1)', 1 );
comp( 'foo (<< 1)', 'foo (<= 2)', -1 );

comp( 'foo (<< 2)', 'foo (<< 2)', 0 );
comp( 'foo (<< 2)', 'foo (<= 2)', -1 );
comp( 'foo (<< 2)', 'foo (= 2)', -1 );
comp( 'foo (<< 2)', 'foo (>= 2)', -1 );
comp( 'foo (<< 2)', 'foo (>> 2)', -1 );

comp( 'foo (<= 2)', 'foo (<< 2)', 1 );
comp( 'foo (<= 2)', 'foo (<= 2)', 0 );
comp( 'foo (<= 2)', 'foo (= 2)', -1 );
comp( 'foo (<= 2)', 'foo (>= 2)', -1 );
comp( 'foo (<= 2)', 'foo (>> 2)', -1 );

comp( 'foo (= 2)', 'foo (<< 2)', 1 );
comp( 'foo (= 2)', 'foo (<= 2)', 1 );
comp( 'foo (= 2)', 'foo (= 2)', 0 );
comp( 'foo (= 2)', 'foo (>= 2)', -1 );
comp( 'foo (= 2)', 'foo (>> 2)', -1 );

comp( 'foo (>= 2)', 'foo (<< 2)', 1 );
comp( 'foo (>= 2)', 'foo (<= 2)', 1 );
comp( 'foo (>= 2)', 'foo (= 2)',  1 );
comp( 'foo (>= 2)', 'foo (>= 2)', 0 );
comp( 'foo (>= 2)', 'foo (>> 2)', -1 );

comp( 'foo (>> 2)', 'foo (<< 2)', 1 );
comp( 'foo (>> 2)', 'foo (<= 2)', 1 );
comp( 'foo (>> 2)', 'foo (= 2)',  1 );
comp( 'foo (>> 2)', 'foo (>= 2)', 1 );
comp( 'foo (>> 2)', 'foo (>> 2)', 0 );
