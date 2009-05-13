=head1 NAME

Debian::Control::FromCPAN - fill F<debian/control> from unpacked CPAN distribution

=head1 SYNOPSIS

    my $c = Debian::Control::FromCPAN->new_from_cpan_meta( $meta, {opts} );
                      # construct from unpacked CPAN dist META.yml

    Debian::Control::FromCPAN inherits from L<Debian::Control>.
=cut

package Debian::Control::FromCPAN;

use strict;

use base 'Debian::Control';

use YAML ();
use File::Spec qw( catfile );

use constant min_perl_version  => '5.6.0-12';

=head1 CONSTRUCTOR

=over

=item new_from_cpan_meta( I<$meta>[, I<$opts>] )

Accepts two arguments, a parsed F<META.yml> file (i.e. a hash reference of
file's content as returned by L<YAML>) and a hash of options. These are given
to the L</fill_from_cpan_meta> method of the newly constructed instance.

=back

=cut

sub new_from_cpan_meta {
    my ( $class, $meta, $opts ) = @_;

    my $self = $class->new;

    $self->fill_from_cpan_meta( $meta, $opts );

    return $self;
}

=head1 METHODS

=over

=item fill_from_cpan_meta( I<meta>, I<options> )

C<meta> is the hash representation of CPAN's F<META.yml> file. Its contents are
converted to the relevant F<debian/control> fields.

Options

=over

=item apt_contents

An instance of Debian::AptContents class, used for finding packages corresponding to depended on modules.

=back

=cut

sub fill_from_cpan_meta {
    my ( $self, $meta, $opts ) = @_;

    my $name = $meta->{name};
    defined($name)
        or die "META.yml contains no distribution name or version";

    $name = lc($name);
    $name =~ s/::/-/g;
    $name = "lib$name" unless $name =~ /^lib/;

    $self->source->Source($name);
    my $src = $self->source;

    my $bin = $self->binary->{$name} = Debian::Control::Stanza::Binary({
        Package => $name,
    });

    $self->dependencies_from_cpan_meta( $meta, $opts->{apt_contents} )
        if $opts->{apt_contents};

    do {
        $src->Section('perl');
        $bin->Section('perl');
    } unless defined( $src->Section ) or defined( $bin->Section );
    do {
        $src->Priority('optional');
        $bin->Priority('optional');
    } unless defined( $src->Priority ) or defined( $bin->Priority );
}

=item parse_meta_dep_list( src, apt_depends, missing )

Convert the given CPAN META dependency list (I<src>, hashref with module names
for keys and versions for values) into an instance of the
L<Debian::Dependencies> class. Supplied I<apt_depends> is used for finding
Debian packages corresponfing to CPAN modules. Modules with no corresponding
Debian packages are added to the I<missing> parameter (which must be an
instance of the L<Debian::Dependencies> class).

=cut

sub parse_meta_dep_list {
    my( $self, $src, $apt_contents, $missing ) = @_;

    my $deps = Debian::Dependencies->new;

    while( my($k,$v) = each %$src ) {
        my $pkg_dep = $apt_contents->find_perl_module_package( $k, $v );

        $deps->add($pkg_dep) if $pkg_dep;
    }

    return $deps;
}

=item dependencies_from_cpan_meta( I<meta>, I<apt_contents> )

Fills dependencies (build-time, run-time, recommends and conflicts) from given
CPAN META.

=cut

sub dependencies_from_cpan_meta {
    my ( $self, $meta, $apt_contents, $opt_verbose ) = @_;

    my $missing = Debian::Dependencies->new();

    my $depends = $self->parse_meta_dep_list( $meta->{requires}, $apt_contents, $missing );
    my $build_depends = $self->parse_meta_dep_list( $meta->{build_requires}, $apt_contents, $missing );
    my $recommends = $self->parse_meta_dep_list( $meta->{recommends}, $apt_contents, $missing );
    my $conflicts = $self->parse_meta_dep_list( $meta->{conflicts}, $apt_contents, $missing );

    my $all = $depends + $build_depends + $recommends;

    $build_depends += $depends;
    $depends->add('${perl:Depends}');
    $depends->add('${misc:Depends}');

    my $bin = $self->binary->Values(0);

    $bin->Depends->add($depends);
    $bin->Recommends->add($recommends);
    $bin->Conflicts->add($conflicts);

    if( $self->source->Architecture eq 'all' ) {
        $self->source->Build_Depends_Indep->add($build_depends);
    }
    else {
        $self->source->Build_Depends->add($build_depends);
    }

    if ($opt_verbose) {
        print "\n";
        print "Needs the following debian packages: $all\n" if @$all;
    }
    if (@$missing) {
        my ($missing_debs_str);
        if ($apt_contents) {
            $missing_debs_str = join( "\n",
                "Needs the following modules for which there are no debian packages available",
                map( {" - $_"} @$missing ),
                '' );
        }
        else {
            $missing_debs_str = join( "\n",
                "The following Perl modules are required and not installed in your system:",
                map( {" - $_"} @$missing ),
                "You do not have 'apt-file' currently installed - If you install it, I will",
                "be able to tell you which Debian packages are those modules in (if they are",
                "packaged)." );
        }

        print $missing_debs_str;
    }
}

=back

=head1 COPYRIGHT & LICENSE

Copyright (C) 2009 Damyan Ivanov L<dmn@debian.org>

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License version 2 as published by the Free
Software Foundation.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE.

=cut

1;


