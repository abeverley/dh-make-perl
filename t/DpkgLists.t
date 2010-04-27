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

is_deeply( [ $m->scan_partial_path('/bin/perl') ],
    ['perl-base'], 'partial /bin/perl is in perl-base' );

is_deeply( [ $m->scan_pattern(qr{/bin/perl$}) ],
    ['perl-base'], 'qr{/bin/perl$} is in perl-base' );

is_deeply( [ $m->scan_perl_mod('Errno') ],
    ['perl-base'], 'Errno is in perl-base' );

is_deeply( [ $m->scan_perl_mod('IO::Socket::UNIX') ],
    ['perl-base'], 'IO::Socket::UNIX is in perl-base' );

is_deeply( [ $m->scan_perl_mod('utf8') ],
    ['perl-base'], 'utf8 is in perl-base' );
