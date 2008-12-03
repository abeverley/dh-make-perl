#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More tests => 15;

use FindBin qw($Bin);
use File::Spec::Functions qw(splitpath);

sub compare {
    my ( $dist, $path ) = @_;
    my ( $vol, $dir, $name ) = splitpath($path);

    return unless -f $path;

    my $real = $path;
    $real =~ s{/wanted-debian/}{/debian/};
    my $diff = diff($path, $real);

    if ( $name eq 'changelog' ) {
        my $only_date_differs = 1;
        for ( split( /\n/, $diff ) ) {
            next if /^--- / or /^\+\+\+ /;
            next unless /^[-+] /;
            next if /^[-+] -- Joe Maintainer <joemaint\@test\.local>  /;

            $only_date_differs = 0;
            diag $name;
            last;
        }

        $diff = '' if $only_date_differs;
    }

    if ( $name eq 'copyright' ) {
        my $only_date_differs = 1;
        for ( split( /\n/, $diff ) ) {
            next if /^--- / or /^\+\+\+ /;
            next unless /^[-+] /;
            next if /^[-+] Copyright: \d+, Joe Maintainer <joemaint\@test\.local>/;

            $only_date_differs = 0;
            diag $name;
            last;
        }

        $diff = '' if $only_date_differs;
    }

    is($diff, '', "$dist/debian/$name is OK");
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

    use File::Find::Rule qw();
    use Text::Diff qw(diff);
    my @files = File::Find::Rule->or(
               File::Find::Rule->new
                    ->directory
                    ->name( '.svn', 'CVS', '.git', '.hg' )
                    ->prune
                    ->discard,
               File::Find::Rule->new,
            )
         ->in("$dist/wanted-debian");
    compare( $dist_dir, $_) for @files;

    # clean after the test
    File::Find::Rule->file
                    ->exec( sub{ unlink $_[2]
                                or die "unlink($_[2]): $!" } )
                    ->in("$dist/debian");

    rmdir "$dist/debian" or die "rmdir($dist/debian): $!";
}

$ENV{DEBFULLNAME} = "Joe Maintainer";

for( qw( Strange-0.1 Strange-2.1 ) ) {
    dist_ok($_);
}
