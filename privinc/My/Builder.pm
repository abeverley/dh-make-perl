package My::Builder;
use strict;
use warnings;

use base qw(Module::Build);

sub ACTION_orig {
    my $self = shift;
    $self->ACTION_manifest();
    $self->SUPER::ACTION_dist();
    my $dn       = $self->dist_name;
    my $ver      = $self->dist_version;
    my $pkg_name = 'dh-make-perl';
    my $orig = "$pkg_name\_$ver.orig.tar.gz";
    my $dist = "$dn-$ver.tar.gz";
    rename $dist, "../$orig" or die "rename( $dist, ../$orig ): $!";
    print "../$orig ready.\n";
    if ( -e "../$dist" ) {
        unlink("../$dist") or die "unlink(../$dist): $!";
    }
    link "../$orig", "../$dist" or die "link( ../$orig, ../$dist ): $!";
    print "../$dist (hardlinked with $orig) ready.\n";
    $self->ACTION_distclean;
    unlink 'MANIFEST', 'MANIFEST.bak', 'META.yml';
}

sub ACTION_dist {
    warn <<EOF;
The 'dist' action is usualy used to create a tar.gz to upload to CPAN.

The primary distribution point of dh-make-perl is the Debian archive. If you
need a tar.gz for CPAN, download the source tarball from Debian. `apt-get
source --tar-only dh-make-perl' can be used for that.

If you don't happen to run Debian (!), see
http://packages.debian.org/source/unstable/dh-make-perl

In case you want to upload to Debian and need and .orig.tar.gz, run the
`orig' action.
EOF

    return 1;
}


1;
