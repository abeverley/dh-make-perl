#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More tests => 7;

BEGIN {
    use_ok 'Debian::DpkgLists';
};

my $m = 'Debian::DpkgLists';

is_deeply( [ $m->scan_full_path('/usr/bin/perl') ],
    ['perl-base'], '/usr/bin/perl is in perl-base' );

my @found = $m->scan_partial_path('/bin/perl');
ok( grep( 'perl-base', @found ), 'partial /bin/perl is in perl-base' );

@found = $m->scan_pattern(qr{/bin/perl$});
ok( grep( 'perl-base', @found ), 'qr{/bin/perl$} is in perl-base' );

is_deeply( [ $m->scan_perl_mod('Errno') ],
    ['perl-base'], 'Errno is in perl-base' );

is_deeply( [ $m->scan_perl_mod('IO::Socket::UNIX') ],
    ['perl-base'], 'IO::Socket::UNIX is in perl-base' );

is_deeply( [ $m->scan_perl_mod('utf8') ],
    ['perl-base'], 'utf8 is in perl-base' );
