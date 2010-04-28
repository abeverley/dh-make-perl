=head1 NAME

Debian::Control::FromCPAN - fill F<debian/control> from unpacked CPAN distribution

=head1 SYNOPSIS

    my $c = Debian::Control::FromCPAN->new();
    $c->discover_dependencies( { ... } );
    $c->prune_perl_deps;

    Debian::Control::FromCPAN inherits from L<Debian::Control>.
=cut

package Debian::Control::FromCPAN;

use strict;
use Carp qw(croak);

use base 'Debian::Control';

use CPAN ();
use DhMakePerl::Utils qw( is_core_module find_cpan_module nice_perl_ver split_version_relation );
use File::Spec qw( catfile );
use Module::Depends ();

use constant oldstable_perl_version => '5.8.8';

=head1 METHODS

=over

=item discover_dependencies( [ { options hash } ] )

Discovers module dependencies and fills the debendency fields in
F<debian/control> accordingly.

Options:

=over

=item apt_contents

An instance of L<Debian::AptContents> to be used when locating to which package
a required module belongs.

=item dir

The directory where the cpan distribution was unpacked.

=item intrusive

A flag indicating permission to use L<Module::Depends::Intrusive> for
discovering dependencies in case L<Module::Depends> fails. Sinse this requires
loading all Perl modules in the distribution (and running their BEGIN blocks
(and the BEGIN blocks of their dependencies, recursively), it is recommended to
use this only when dealing with trusted sources.

=item require_deps

If true, causes the method to die if some a package for some dependency cannot
be found. Otherwise only a warning is issued.

=item verbose

=item wnpp_query

An instance of L<Debian::WNPP::Query> to be used when checking for WNPP bugs of
depeended upon packages.

=back

Returns a list of module names for which no suitable Debian packages were
found.

=cut

sub discover_dependencies {
    my ( $self, $opts ) = @_;

    $opts //= {};
    ref($opts) and ref($opts) eq 'HASH'
        or die 'Usage: $obj->{ [ { opts hash } ] )';
    my $apt_contents = delete $opts->{apt_contents};
    my $dir = delete $opts->{dir};
    my $intrusive = delete $opts->{intrusive};
    my $require_deps = delete $opts->{require_deps};
    my $verbose = delete $opts->{verbose};
    my $wnpp_query = delete $opts->{wnpp_query};

    die "Unsupported option(s) given: " . join( ', ', sort( keys(%$opts) ) )
        if %$opts;

    my $src = $self->source;
    my $bin = $self->binary->Values(0);

    local @INC = ( $dir, @INC );

    # try Module::Depends, but if that fails then
    # fall back to Module::Depends::Intrusive.

    my $finder = Module::Depends->new->dist_dir($dir);
    my $deps;
    do {
        no warnings;
        local *STDERR;
        open( STDERR, ">/dev/null" );
        $deps = $finder->find_modules;
    };

    my $error = $finder->error();
    if ($error) {
        if ($verbose) {
            warn '=' x 70, "\n";
            warn "Failed to detect dependencies using Module::Depends.\n";
            warn "The error given was:\n";
            warn "$error";
        }

        if ( $intrusive ) {
            warn "Trying again with Module::Depends::Intrusive ... \n"
                if $verbose;
            require Module::Depends::Intrusive;
            $finder = Module::Depends::Intrusive->new->dist_dir($dir);
            do {
                no warnings;
                local *STDERR;
                open( STDERR, ">/dev/null" );
                $deps = $finder->find_modules;
            };

            if ( $finder->error ) {
                if ($verbose) {
                    warn '=' x 70, "\n";
                    warn
                        "Could not find the "
                        . "dependencies for the requested module.\n";
                    warn "Generated error: " . $finder->error;

                    warn "Please bug the module author to provide a"
                        . " proper META.yml file.\n"
                        . "Automatic find of" 
                        . " dependencies failed. You may want to \n"
                        . "retry using the '--[b]depends[i]' options\n"
                        . "or just fill the dependency fields in debian/rules"
                        . " by hand\n";

                        return;
                }
            }
        }
        else {
            warn
                "If you understand the security implications, try --intrusive.\n"
                if $verbose;
        }
        warn '=' x 70, "\n"
            if $verbose;

        return;
    }

    # run-time
    my ( $debs, $missing )
        = $self->find_debs_for_modules( $deps->{requires}, $apt_contents, $verbose );

    if (@$debs) {
        if ($verbose) {
            print "\n";
            print "Needs the following debian packages: "
                . join( ", ", @$debs ) . "\n";
        }
        $bin->Depends->add(@$debs);
        if ( $bin->Architecture eq 'all' ) {
            $src->Build_Depends_Indep->add(@$debs);
        }
        else {
            $src->Build_Depends->add(@$debs);
        }
    }

    # build-time
    my ( $b_debs, $b_missing )
        = $self->find_debs_for_modules( $deps->{build_requires}, $apt_contents, $verbose );

    if (@$b_debs) {
        if ($verbose) {
            print "\n";
            print "Needs the following debian packages during building: "
                . join( ", ", @$b_debs ) . "\n";
        }
        if ( $self->is_arch_dep ) {
            $src->Build_Depends->add(@$b_debs);
        }
        else {
            $src->Build_Depends_Indep->add(@$b_debs);
        }
    }

    push @$missing, @$b_missing;

    if (@$missing) {
        my ($missing_debs_str);
        if ($apt_contents) {
            $missing_debs_str
                = "Needs the following modules for which there are no debian packages available:\n";
            for (@$missing) {
                my $bug = ( $wnpp_query->bugs_for_package($_) )[0];
                $missing_debs_str .= " - $_";
                $missing_debs_str .= " (" . $bug->type_and_number . ')'
                    if $bug;
                $missing_debs_str .= "\n";
            }
        }
        else {
            $missing_debs_str = "The following Perl modules are required and not installed in your system:\n";
            for (@$missing) {
                my $bug = ( $wnpp_query->bugs_for_package($_) )[0];
                $missing_debs_str .= " - $_";
                $missing_debs_str .= " (" . $bug->type_and_number . ')'
                    if $bug;
                $missing_debs_str .= "\n";
            }
            $missing_debs_str .= <<EOF
You do not have 'apt-file' currently installed, or have not ran
'apt-file update' - If you install it and run 'apt-file update' as
root, I will be able to tell you which Debian packages are those
modules in (if they are packaged).
EOF
        }

        if ($require_deps) {
            die $missing_debs_str;
        }
        else {
            warn $missing_debs_str;
        }

    }

    return @$missing;
}

=item find_debs_for_modules I<dep hash>[, APT contents[, verbose ]]

Scans the given hash of dependencies ( module => version ) and returns matching
Debian package dependency specification (as an instance of
L<Debian::Dependencies> class) and a list of missing modules.

=cut

sub find_debs_for_modules {

    my ( $self, $dep_hash, $apt_contents, $verbose ) = @_;

    my $debs = Debian::Dependencies->new();

    my @missing;

    while ( my ( $module, $version ) = each %$dep_hash ) {

        my $ver_rel;

        ( $ver_rel, $version ) = split_version_relation($version) if $version;

        $version =~ s/^v// if $version;

        my $dep;

        if ($apt_contents) {
            $dep = $apt_contents->find_perl_module_package( $module, $version );
        }
        elsif ( my $ver = is_core_module( $module, $version ) ) {
            $dep = Debian::Dependency->new( 'perl', $ver );
        }
        else {
            require Debian::DpkgLists;
            if ( my @pkgs = Debian::DpkgLists->scan_perl_mod($module) ) {
                $dep = Debian::Dependency->new(
                      ( @pkgs > 1 )
                    ? [ map { { pkg => $_, ver => $version } } @pkgs ]
                    : ( $pkgs[0], $version )
                );
            }
        }

        $dep->rel($ver_rel) if $dep and $ver_rel and $dep->ver;

        my $mod_ver = join( " ", $module, $ver_rel, $version || () );
        if ($dep) {
            if ($verbose) {
                if ( $dep->pkg and $dep->pkg eq 'perl' ) {
                    print "= $mod_ver is in core";
                    print " since " . $dep->ver if $dep->ver;
                    print "\n";
                }
                else {
                    print "+ $mod_ver found in $dep\n";
                }
            }
        }
        else {
            print "- $mod_ver not found in any package\n";
            push @missing, $module;

            my $mod = find_cpan_module($module);
            if ( $mod and $mod->distribution ) {
                ( my $dist = $mod->distribution->base_id ) =~ s/-v?\d[^-]*$//;
                my $pkg = 'lib' . lc($dist) . '-perl';

                print "   CPAN contains it in $dist\n";
                print "   substituting package name of $pkg\n";

                $dep = Debian::Dependency->new( $pkg, $ver_rel, $version );
            }
            else {
                print "   - it seems it is not available even via CPAN\n";
            }
        }

        $debs->add($dep) if $dep;
    }

    return $debs, \@missing;
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
            and $dep->ver <= $self->oldstable_perl_version
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

Copyright (C) 2009, 2010 Damyan Ivanov L<dmn@debian.org>

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License version 2 as published by the Free
Software Foundation.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE.

=cut

1;


