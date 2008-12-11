#!perl -T

use Test::More tests => 1;

BEGIN {
	use_ok( 'DhMakePerl' );
}

diag( "Testing DhMakePerl $DhMakePerl::VERSION, Perl $], $^X" );
