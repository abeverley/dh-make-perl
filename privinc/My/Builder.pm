package My::Builder;
use strict;
use warnings;

use base qw(Module::Build);

sub ACTION_orig {
    my $self = shift;
    $self->ACTION_manifest();
    $self->ACTION_dist();
    my $dn       = $self->dist_name;
    my $ver      = $self->dist_version;
    my $pkg_name = 'dh-make-perl';
    rename "$dn-$ver.tar.gz", "../$pkg_name\_$ver.orig.tar.gz";
    $self->ACTION_distclean;
    unlink 'MANIFEST', 'MANIFEST.bak', 'META.yml';
    print "../$pkg_name\_$ver.orig.tar.gz ready.\n";
}

1;

