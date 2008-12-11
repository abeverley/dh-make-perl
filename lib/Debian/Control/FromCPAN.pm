# C<Control::FromCPAN> adds ability to fill the control data from unpacked
# CPAN distribution
#
# SYNOPSIS
#
#   my $c = DhMakePerl::FromCPAN->new_from_cpan_meta( $meta, {opts} );
#                      # construct from unpacked CPAN dist META.yml

package Debian::Control::FromCPAN;

use base 'Debian::Control';

use YAML ();
use File::Spec qw( catfile );

sub new_from_cpan_meta {
    my ( $class, $meta, $opts ) = @_;

    my $self = $class->new;

    $self->fill_from_cpan_meta( $meta, $opts );

    return $self;
}

sub fill_from_cpan_meta {
    my ( $self, $meta, $opts ) = @_;

    my $name = $meta->{name};
    defined($name)
        or die "META.yml contains no distribution name or version";

    $name = lc($name);
    $name =~ s/::/-/g;
    $name = "lib$name" unless $name =~ /^lib/;

    $self->source( { Source => $name } );
    my $src = $self->source;

    $self->binary->{$name}{Package} = $name;
    my $bin = $self->binary->{$name};

    $self->description_from_meta($meta);
    $self->dependencies_from_meta( $meta, $opts->{apt_contents} )
        if $opts->{apt_contents};

    $src->{Section} = $bin->{Section} = 'perl'
        unless defined( $src->{Section} ) or defined( $bin->{Section} );
    $src->{Priority} = $bin->{Priority} = 'optional'
        unless defined( $src->{Priority} ) or defined( $bin->{Priority} );
}


1;


