#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More 'no_plan';

use FindBin qw($Bin);
use File::Touch qw(touch);

require "$Bin/../dh-make-perl";        # Load our code for testing.

unlink("$Bin/Contents.cache");

eval { AptContents->new() };
ok( $@, 'AptContents->new with no homedir dies' );
like( $@, qr/No homedir given/, 'should say why it died' );

my $apt_contents = AptContents->new(
    { homedir => '.', contents_dir => 'non-existent' }
);

is( $apt_contents, undef, 'should not create with no contents' );


$apt_contents = AptContents->new(
    { homedir => $Bin, contents_dir => "$Bin/contents", verbose => 0 }
);

isnt( $apt_contents, undef, 'object created' );

is_deeply(
    $apt_contents->contents_files,
    [ sort glob "$Bin/contents/*Contents*" ],
    'contents in a dir'
);

ok( -f "$Bin/Contents.cache", 'Contents.cache created' );

is( $apt_contents->source, 'parsed files', 'no cache was used' );

$apt_contents = AptContents->new(
    { homedir => $Bin, contents_dir => "$Bin/contents", verbose => 0 }
);

is( $apt_contents->source, 'cache', 'cache was used' );

touch( glob "$Bin/contents/*Contents*" );

$apt_contents = AptContents->new(
    { homedir => $Bin, contents_dir => "$Bin/contents", verbose => 0 }
);

is( $apt_contents->source, 'parsed files', 'cache updated' );

ok( unlink "$Bin/Contents.cache", 'Contents.cache unlnked' );
