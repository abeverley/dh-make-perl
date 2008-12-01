#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More tests => 15;

use FindBin qw($Bin);

sub compare {
    my $dist = shift;

    return unless -f $File::Find::name;

    my $real = $File::Find::name;
    $real =~ s{/wanted-debian/}{/debian/};
    my $diff = diff($File::Find::name, $real);

    if ( $_ eq 'changelog' ) {
        my $only_date_differs = 1;
        for ( split( /\n/, $diff ) ) {
            next if /^--- / or /^\+\+\+ /;
            next unless /^[-+] /;
            next if /^[-+] -- Joe Maintainer <joemaint\@test\.local>  /;

            $only_date_differs = 0;
            diag $_;
            last;
        }

        $diff = '' if $only_date_differs;
    }

    if ( $_ eq 'copyright' ) {
        my $only_date_differs = 1;
        for ( split( /\n/, $diff ) ) {
            next if /^--- / or /^\+\+\+ /;
            next unless /^[-+] /;
            next if /^[-+] Copyright: \d+, Joe Maintainer <joemaint\@test\.local>/;

            $only_date_differs = 0;
            diag $_;
            last;
        }

        $diff = '' if $only_date_differs;
    }

    is($diff, '', "$dist/debian/$_ is OK");
}

sub dist_ok($) {
    my $dist_dir = shift;
    my $dist = "$Bin/dists/$dist_dir";

    system( "$Bin/../dh-make-perl", "--no-verbose",
            "--home-dir", "$Bin/contents", "--data-dir", "$Bin/../share",
            "--sources-list",
            "$Bin/contents/sources.list", "--email", "joemaint\@test.local",
            $dist );

    is( $?, 0, "$dist_dir: system returned 0" );

    use File::Find qw(find);
    use Text::Diff qw(diff);

    find( sub { compare($dist_dir) }, "$dist/wanted-debian");

    # clean after the test
    find( sub{
            unlink $File::Find::name 
                or die "unlink($File::Find::name): $!"
            if -f $File::Find::name;
        }, "$dist/debian" );

    rmdir "$dist/debian" or die "rmdir($dist/debian): $!";
}

$ENV{DEBFULLNAME} = "Joe Maintainer";

for( qw( Strange-0.1 Strange-2.1 ) ) {
    dist_ok($_);
}
