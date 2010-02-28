#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More tests => 12;

use FindBin qw($Bin);
use File::Compare ();
use File::DirCompare;
use File::Find::Rule;
use File::Spec::Functions qw(splitpath);
use File::Path ();
use Text::Diff qw(diff);

sub compare_tree {
    my ( $real, $wanted, $hint ) = @_;

    my @errors;
    File::DirCompare->compare(
        $real, $wanted,
        sub {
            my ( $a, $b ) = @_;
            return
                if $a and $a =~ m{/\.(?:svn|gh|git|CVS)/}
                    or $b and $b =~ m{/\.(?:svn|gh|git|CVS)/};
            return
                if $a and $a =~ /\.bak$/
                    or $b and $b =~ /\.bak$/;

            unless ( defined($b) ) {
                push @errors, diff( $a, '/dev/null' );
                return;
            }
            unless ( defined($a) ) {
                push @errors, diff( $a, '/dev/null' );
                return;
            }
            push @errors, diff( $a, $b );
        },
        {   cmp => sub {
                File::Compare::compare_text(
                    @_,
                    sub {
                        my ( $a, $b ) = @_;

                        # different copyright years are normal
                        # (test written in 2002 and run in 2020
                        return 0
                            if $a
                                =~ /^Copyright: \d+, Joe Maintainer <joemaint\@test\.local>$/
                                and $b
                                =~ /^Copyright: \d+, Joe Maintainer <joemaint\@test\.local>$/;

                        # likewise, it is normal that the timestamp in the changelog differs
                        return 0
                            if $a
                                =~ /^ -- Joe Maintainer <joemaint\@test\.local>  \w+, \d+ \w+ \d+ \d+:\d+:\d+ \+\d+$/
                                and $b
                                =~ /^ -- Joe Maintainer <joemaint\@test\.local>  \w+, \d+ \w+ \d+ \d+:\d+:\d+ \+\d+$/;

                        return $a ne $b;
                    }
                );
            },
        }
    );

    is( join( "\n", @errors ), '',
        'Generated tree matches template' . ( $hint ? " ($hint)" : '' ) );
}

sub dist_ok($) {
    my $dist_dir = shift;
    my $dist = "$Bin/dists/$dist_dir";

    system( "$Bin/../dh-make-perl", "--no-verbose",
            "--home-dir", "$Bin/contents",
            "--apt-contents-dir", "$Bin/contents",
            "--data-dir", "$Bin/../share",
            $ENV{NO_NETWORK} ? '--no-network' : (),
            "--sources-list",
            "$Bin/contents/sources.list", "--email", "joemaint\@test.local",
            $dist );

    is( $?, 0, "$dist_dir: system returned 0" );

    compare_tree( "$dist/debian", "$dist/wanted-debian" );

    system( "$Bin/../dh-make-perl", "--no-verbose",
            "--home-dir", "$Bin/contents",
            "--apt-contents-dir", "$Bin/contents",
            "--data-dir", "$Bin/../share",
            $ENV{NO_NETWORK} ? '--no-network' : (),
            "--sources-list",
            "$Bin/contents/sources.list", "--email", "joemaint\@test.local",
            "refresh",
            $dist );

    is( $?, 0, "$dist_dir refresh: system returned 0" );

    compare_tree( "$dist/debian", "$dist/wanted-debian--refresh", 'refresh' );

    unlink File::Find::Rule->file->name('*.bak')->in("$dist/debian");

    system( "$Bin/../dh-make-perl", "--no-verbose",
            "--home-dir", "$Bin/contents",
            "--apt-contents-dir", "$Bin/contents",
            "--data-dir", "$Bin/../share",
            $ENV{NO_NETWORK} ? '--no-network' : (),
            "--sources-list",
            "$Bin/contents/sources.list", "--email", "joemaint\@test.local",
            "refresh", '--source-format', '3.0 (quilt)',
            $dist );

    is( $?, 0,
        "$dist_dir refresh --source-format '3.0 (quilt)': system returned 0"
    );

    compare_tree(
        "$dist/debian",
        "$dist/wanted-debian--refresh--source-format=3.0_quilt",
        'refresh --source-format 3.0 (quilt)'
    );

    # clean after the test
    File::Path::rmtree("$dist/debian");

    unlink "$Bin/contents/Contents.cache" or die "unlink($Bin/contents.cache): $!";
    -e "$Bin/contents/wnpp.cache" and ( unlink "$Bin/contents/wnpp.cache"
        or die "unlink($Bin/contents/wnpp.cache): $!" );
}

$ENV{DEBFULLNAME} = "Joe Maintainer";

for( qw( Strange-0.1 Strange-2.1 ) ) {
    dist_ok($_);
}
