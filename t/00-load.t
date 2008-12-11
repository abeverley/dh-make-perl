#!perl -T

use Test::More tests => 1;

BEGIN {
	use_ok( 'App::DhMakePerl' );
}

diag( "Testing App::DhMakePerl $App::DhMakePerl::VERSION, Perl $], $^X" );
