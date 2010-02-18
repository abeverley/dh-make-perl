=head1 NAME

Debian::Control::FromCPAN - fill F<debian/control> from unpacked CPAN distribution

=head1 SYNOPSIS

    my $c = Debian::Control::FromCPAN->new_from_cpan_meta( $meta, {opts} );
                      # construct from unpacked CPAN dist META.yml

    Debian::Control::FromCPAN inherits from L<Debian::Control>.
=cut

package Debian::Control::FromCPAN;

use strict;
use Carp qw(croak);

use base 'Debian::Control';

use YAML ();
use Debian::Version qw(deb_ver_cmp);
use File::Spec qw( catfile );

use constant oldstable_perl_version => '5.8.8';

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

An instance of Debian::AptContents class, used for finding packages
corresponding to depended on modules.

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

    my $arch_dep = 0;
    for( $self->binary->Values ) {
        if( $_->Architecture ne 'all' ) {
            $arch_dep = 1;
            last;
        }
    }

    if( $arch_dep ) {
        $self->source->Build_Depends->add($build_depends);
    }
    else {
        $self->source->Build_Depends_Indep->add($build_depends);
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

=item prune_simple_perl_dep

Input:

=over

=item dependency object

shall be a simple dependency (no alternatives)

=item (optional) build dependency flag

true value indicates the dependency is a build-time one

=back


The following checks are made

=over

=item dependencies on C<perl-modules>

These are replaced with C<perl> as per Perl policy.

=item dependencies on C<perl-base> and build-dependencies on C<perl> or
C<perl-base>

These are removed, unless they specify a version greater than the one available
in C<oldstable> or the dependency relation is not C<< >= >> or C<<< >> >>>.

=back

Return value:

=over

=item undef

if the dependency is redundant.

=item pruned dependency

otherwise. C<perl-modules> replaced with C<perl>.

=back

=cut

sub prune_simple_perl_dep {
    my( $self, $dep, $build ) = @_;

    croak "No alternative dependencies can be given"
        if $dep->alternatives;

    return $dep unless $dep->pkg =~ /^(?:perl|perl-base|perl-modules)$/;

    # perl-modules is replaced with perl
    $dep->pkg('perl') if $dep->pkg eq 'perl-modules';

    my $unversioned = (
        not $dep->ver
            or $dep->rel =~ />/
            and deb_ver_cmp( $dep->ver, $self->oldstable_perl_version ) <= 0
    );

    # if the dependency is considered unversioned, make sure there is no
    # version
    if ($unversioned) {
        $dep->ver(undef);
        $dep->rel(undef);
    }

    # perl-base is (build-)essential
    return undef
        if $dep->pkg eq 'perl-base' and $unversioned;

    # perl is needed in build-dependencies (see Policy 4.2)
    return $dep if $dep->pkg eq 'perl' and $build;

    # unversioned perl non-build-dependency is redundant, because it will be
    # covered by ${perl:Depends}
    return undef
        if not $build
            and $dep->pkg eq 'perl'
            and $unversioned;

    return $dep;
}

=item prune_perl_dep

Similar to L</prune_simple_perl_dep>, but supports alternative dependencies.
If any of the alternatives is redundant, the whole dependency is considered
redundant.

=cut

sub prune_perl_dep {
    my( $self, $dep, $build ) = @_;

    return $self->prune_simple_perl_dep( $dep, $build )
        unless $dep->alternatives;

    for my $simple ( @{ $dep->alternatives } ) {
        my $pruned = $self->prune_simple_perl_dep( $simple, $build );

        # redundant alternative?
        return undef unless $pruned;

        $simple = $pruned;
    }

    return $dep;
}

=item prune_perl_deps

Remove redundant (build-)dependencies on perl, perl-modules and perl-base.

=cut

sub prune_perl_deps {
    my $self = shift;

    # remove build-depending on ancient perl versions
    for my $perl ( qw( perl perl-base perl-modules ) ) {
        for ( qw( Build_Depends Build_Depends_Indep ) ) {
            my @ess = $self->source->$_->remove($perl);
            # put back non-redundant ones (possibly modified)
            for my $dep (@ess) {
                my $pruned = $self->prune_perl_dep( $dep, 1 );

                $self->source->$_->add($pruned) if $pruned;
            }
        }
    }

    # remove depending on ancient perl versions
    for my $perl ( qw( perl perl-base perl-modules ) ) {
        for my $pkg ( $self->binary->Values ) {
            for my $rel ( qw(Depends Recommends Suggests) ) {
                my @ess = $pkg->$rel->remove($perl);
                for my $dep (@ess) {
                    my $pruned = $self->prune_perl_dep( $dep, 0 );

                    $pkg->$rel->add($pruned) if $pruned;
                }
            }
        }
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


