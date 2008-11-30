#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More tests => 15;

use FindBin qw($Bin);

sub compare {

    return unless -f $File::Find::name;

    my $wanted = $File::Find::name;
    $wanted =~ s{/debian/}{/wanted-debian/};
    my $diff = diff($wanted, $File::Find::name);

    $diff = ''
        unless grep { /^[-+] /
                     and not /^[-+] -- Joe Maintainer <joemaint\@test.local>  / }
            split( /\n/, $diff );

    is($diff, '', "$File::Find::name is OK");
}

sub dist_ok($) {
    my $dist_dir = shift;
    my $dist = "$Bin/dists/$dist_dir";

    system( "$Bin/../dh-make-perl", "--no-verbose",
            "--home-dir", "$Bin/contents", "--sources-list",
            "$Bin/contents/sources.list", "--email", "joemaint\@test.local",
            $dist );

    is( $?, 0, "$dist_dir: system returned 0" );

    use File::Find qw(find);
    use Text::Diff qw(diff);

    find(\&compare, "$dist/debian");

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
