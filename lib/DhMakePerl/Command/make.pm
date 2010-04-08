package DhMakePerl::Command::make;

use warnings;
use strict;
use 5.010;    # we use smart matching

use base 'DhMakePerl::Command::Packaging';

__PACKAGE__->mk_accessors(
    qw(
        cfg apt_contents main_dir debian_dir meta
        start_dir
        perlname version pkgversion
        copyright author
        extrasfields  extrapfields
        mod_cpan_version
        docs examples
        )
);

=head1 NAME

DhMakePerl - create Debian source package from CPAN dist

=head1 VERSION

Version 0.65

=cut

our $VERSION = '0.65';

=head1 SYNOPSIS

TO BE FILLED

    use DhMakePerl;

    my $foo = DhMakePerl->new();
    ...

=head1 METHODS

=over

=cut

use AptPkg::Cache ();
use CPAN ();
use Debian::Dependencies      ();
use Debian::Dependency        ();
use Debian::WNPP::Query;
use DhMakePerl::Utils qw( find_cpan_module is_core_module );
use Email::Date::Format qw(email_date);
use File::Basename qw( basename dirname );
use File::Copy qw( copy move );
use File::Path ();
use File::Spec::Functions qw( catfile );
use Module::Depends            ();
use Text::Wrap qw( wrap );

# TODO:
# * get more info from the package (maybe using CPAN methods)

sub check_deprecated_overrides {
    my $self = shift;

    my $overrides = catfile( $self->cfg->data_dir, 'overrides' );

    if ( -e $overrides ) {
        warn "*** deprecated overrides file ignored\n";
        warn "***\n";
        warn "*** Overrides mechanism is deprecated in dh-make-perl 0.65\n";
        warn "*** You may want to remove $overrides\n";
    }
}

sub execute {
    my ($self) = @_;

    die "CPANPLUS support disabled, sorry" if $self->cfg->cpanplus;

    $self->check_deprecated_overrides;

    my $tarball = $self->setup_dir();
    $self->process_meta;
    $self->findbin_fix();

    $self->extract_basic();

    unless ( defined $self->cfg->version ) {
        $self->pkgversion( $self->version . '-1' );
    }
    else {
        $self->pkgversion( $self->cfg->version );
    }

    $self->fill_maintainer;

    my $bin = $self->control->binary->Values(0);
    $bin->short_description( $self->cfg->desc )
        if $self->cfg->desc;

    move(
        $tarball,
        sprintf(
            "%s/%s_%s.orig.tar.gz",
            dirname($tarball), $self->pkgname, $self->version
        )
    ) if ( $tarball && $tarball =~ /(?:\.tar\.gz|\.tgz)$/ );

    if ( -d $self->debian_dir ) {
        $self->warning( $self->debian_dir . ' already exists' );
        my $bak = $self->debian_dir . '.bak';
        $self->warning( "moving to $bak" );
        if ( -d $bak ) {
            $self->warning("overwriting existing $bak");
            File::Path::rmtree($bak);
        }
        rename $self->debian_dir, $bak or die $!;
    }

    my $apt_contents = $self->get_apt_contents;
    my $src = $self->control->source;

    $self->discover_dependencies;

    $bin->Depends->add( $self->cfg->depends )
        if $self->cfg->depends;

    $src->Build_Depends->add( $self->cfg->bdepends )
        if $self->cfg->bdepends;

    $src->Build_Depends_Indep->add( $self->cfg->bdependsi )
        if $self->cfg->bdependsi;

    $self->extract_docs;
    $self->extract_examples;

    die "Cannot find a description for the package: use the --desc switch\n"
        unless $bin->short_description;

    print "Package does not provide a long description - ",
        " Please fill it in manually.\n"
        if ( !defined $bin->long_description
        or $bin->long_description =~ /^\s*\.?\s*$/ )
        and $self->cfg->verbose;

    printf( "Using maintainer: %s\n", $src->Maintainer )
        if $self->cfg->verbose;

    print "Found docs: @{ $self->docs }\n" if $self->cfg->verbose;
    print "Found examples: @{ $self->examples }\n"
        if @{ $self->examples } and $self->cfg->verbose;

    # start writing out the data
    mkdir( $self->debian_dir, 0755 )
        || die "Cannot create " . $self->debian_dir . " dir: $!\n";
    $self->write_source_format(
        catfile( $self->debian_dir, 'source', 'format' ) );
    $self->create_changelog( $self->debian_file('changelog'),
        $self->cfg->closes // $self->get_wnpp( $self->pkgname ) );
    $self->create_rules;

    # now that rules are there, see if we need some dependency for them
    $self->discover_utility_deps( $self->control );
    $src->Standards_Version( $self->debstdversion );
    $src->Homepage( $self->upsurl );
    if ( $self->cfg->pkg_perl and my $cpan = $self->cfg->cpan ) {
        $self->control->source->Vcs_Svn(
            sprintf( "svn://svn.debian.org/pkg-perl/trunk/%s/",
                $self->pkgname )
        );
        $self->control->source->Vcs_Browser(
            sprintf( "http://svn.debian.org/viewsvn/pkg-perl/trunk/%s/",
                $self->pkgname )
        );
    }
    $self->control->write( $self->debian_file('control') );

    $self->create_compat( $self->debian_file('compat') );
    $self->create_watch( $self->debian_file('watch') );

    #create_readme("$debiandir/README.Debian");
    $self->create_copyright( $self->debian_file('copyright') );
    $self->update_file_list( docs => $self->docs, examples => $self->examples );
    $self->build_package
        if $self->cfg->build or $self->cfg->install;
    $self->install_package if $self->cfg->install;
    print "--- Done\n" if $self->cfg->verbose;

    $self->package_already_exists($apt_contents);

    return(0);
}

sub setup_dir {
    my ($self) = @_;

    my ( $dist, $mod, $tarball );
    if ( $self->cfg->cpan ) {
        my ($new_maindir, $orig_pwd);

        # CPAN::Distribution::get() sets $ENV{'PWD'} to $CPAN::Config->{build_dir}
        # so we have to save it here
        $orig_pwd = $ENV{'PWD'};

        # Is the module a core module?
        if ( is_core_module( $self->cfg->cpan ) ) {
            die $self->cfg->cpan 
            . " is a standard module. Will not build without --core-ok.\n"
                unless $self->cfg->core_ok;
        }

        $self->configure_cpan;

        $mod = find_cpan_module( $self->cfg->cpan )
            or die "Can't find '" . $self->cfg->cpan . "' module on CPAN\n";
        $self->mod_cpan_version( $mod->cpan_version );

        $tarball = $CPAN::Config->{'keep_source_where'} . "/authors/id/";

        $dist = $CPAN::META->instance( 'CPAN::Distribution',
            $mod->cpan_file );
        $dist->get || die "Cannot get ", $mod->cpan_file, "\n"; # <- here $ENV{'PWD'} gets set to $HOME/.cpan/build
        $tarball .= $mod->cpan_file;
        $self->main_dir( $dist->dir );

        copy( $tarball, $orig_pwd );
        $tarball = $orig_pwd . "/" . basename($tarball);

        # build_dir contains a random part since 1.88_59
        # use the new CPAN::Distribution::base_id (introduced in 1.91_53)
        $new_maindir = $orig_pwd . "/" . $dist->base_id;

        # rename existing directory
        if ( -d $new_maindir
            && system( "mv", "$new_maindir", "$new_maindir.$$" ) == 0 )
        {
            print '=' x 70, "\n";
            print
                "Unpacked tarball already existed, directory renamed to $new_maindir.$$\n";
            print '=' x 70, "\n";
        }
        system( "mv", $self->main_dir, "$new_maindir" ) == 0
            or die "Failed to move " . $self->main_dir . " to $new_maindir: $!";
        $self->main_dir($new_maindir);

    }
    elsif ( $self->cfg->cpanplus ) {
        die "CPANPLUS support is b0rken at the moment.";

        #  	        my ($cb, $href, $file);

# 		eval "use CPANPLUS 0.045;";
# 		$cb = CPANPLUS::Backend->new(conf => {debug => 1, verbose => 1});
# 		$href = $cb->fetch( modules => [ $self->cfg->cpanplus ], fetchdir => $ENV{'PWD'});
# 		die "Cannot get " . $self->cfg->cpanplus . "\n" if keys(%$href) != 1;
# 		$file = (values %$href)[0];
# 		print $file, "\n\n";
# 		$self->main_dir(
# 		    $cb->extract( files => [ $file ], extractdir => $ENV{'PWD'} )->{$file}
# 		);
    }
    else {
        my $maindir = shift(@ARGV) || '.';
        $maindir =~ s/\/$//;
        $self->main_dir($maindir);
    }
    return $tarball;
}

sub build_package {
    my ( $self ) = @_;

    my $main_dir = $self->main_dir;
    # uhmf! dpkg-genchanges doesn't cope with the deb being in another dir..
    #system("dpkg-buildpackage -b -us -uc " . $self->cfg->dbflags) == 0
    system("fakeroot make -C $main_dir -f debian/rules clean");
    system("make -C $main_dir -f debian/rules build") == 0 
        || die "Cannot create deb package: 'debian/rules build' failed.\n";
    system("fakeroot make -C $main_dir -f debian/rules binary") == 0
        || die "Cannot create deb package: 'fakeroot debian/rules binary' failed.\n";
}

sub install_package {
    my ($self) = @_;

    my ( $archspec, $debname );

    if ( $self->arch eq 'any' ) {
        $archspec = `dpkg --print-architecture`;
        chomp($archspec);
    }
    else {
        $archspec = $self->arch;
    }

    $debname = sprintf( "%s_%s-1_%s.deb", $self->pkgname, $self->version,
        $archspec );

    my $deb = $self->start_dir . "/$debname";
    system("dpkg -i $deb") == 0
        || die "Cannot install package $deb\n";
}

sub findbin_fix {
    my ($self) = @_;

    # FindBin requires to know the name of the invoker - and requires it to be
    # Makefile.PL to function properly :-/
    $0 = $self->makefile_pl();
    if ( exists $FindBin::{Bin} ) {
        FindBin::again();
    }
}

# finds the list of modules that the distribution depends on
# if $build_deps is true, returns build-time dependencies, otherwise
# returns run-time dependencies
sub run_depends {
    my ( $self, $depends_module, $build_deps ) = @_;

    no warnings;
    local *STDERR;
    open( STDERR, ">/dev/null" );
    my $mod_dep = $depends_module->new();

    $mod_dep->dist_dir( $self->main_dir );
    $mod_dep->find_modules();

    my $deps = $build_deps ? $mod_dep->build_requires : $mod_dep->requires;

    my $error = $mod_dep->error();
    die "Error: $error\n" if $error;

    return $deps;
}

# filter @deps to contain only one instance of each package
# say we have te following list of dependencies:
#   libppi-perl, libppi-perl (>= 3.0), libarm-perl, libalpa-perl, libarm-perl (>= 2)
# we want a clean list instead:
#   libalpa-perl, libarm-perl (>= 2), libppi-perl (>= 3.0)
sub prune_deps(@) {
    my $self = shift;

    my %deps;
    for (@_) {
        my $p = $_->pkg;
        my $v = $_->ver;
        if ( exists $deps{$p} ) {
            my $cur_ver = $deps{$p};

            $deps{$p} = $v
                if defined($v) and not defined($cur_ver)
                    or deb_ver_cmp( $cur_ver, $v ) < 0;
        }
        else {
            $deps{$p} = $v;
        }

    }

    return map( Debian::Dependency->new( $_, $deps{$_} ), sort( keys(%deps) ) );
}

sub create_changelog {
    my ( $self, $file, $bug ) = @_;

    my $fh  = $self->_file_w($file);

    my $closes = $bug ? " (Closes: #$bug)" : '';
    my $changelog_dist = $self->cfg->pkg_perl ? "UNRELEASED" : "unstable";

    $fh->printf( "%s (%s) %s; urgency=low\n",
        $self->srcname, $self->pkgversion, $changelog_dist );
    $fh->print("\n  * Initial Release.$closes\n\n");
    $fh->printf( " -- %s  %s\n", $self->get_developer,
        email_date(time) );

    #$fh->print("Local variables:\nmode: debian-changelog\nEnd:\n");
    $fh->close;
}

sub create_readme {
    my ( $self, $filename ) = @_;

    my $fh = $self->_file_w($filename);
    $fh->printf(
        "This is the debian package for the %s module.
It was created by %s using dh-make-perl.
", $self->perlname, $self->maintainer,
    );
    $fh->close;
}

sub create_watch {
    my ( $self, $filename ) = @_;

    my $fh = $self->_file_w($filename);

    my $version_re = 'v?(\d[\d.-]+)\.(?:tar(?:\.gz|\.bz2)?|tgz|zip)';

    $fh->printf( "version=3\n%s   .*/%s-%s\$\n",
        $self->upsurl, $self->perlname, $version_re );
    $fh->close;
}

sub package_already_exists {
    my( $self, $apt_contents ) = @_;

    my $found;

    eval {
        my $apt_cache = AptPkg::Cache->new;
        $found = $apt_cache->packages->lookup( $self->pkgname )
            if $apt_cache;
    };

    warn "Error initializing AptPkg::Cache: $@" if $@;

    if ($found) {
        warn "**********\n";
        warn "WARNING: a package named\n";
        warn "              '" . $self->pkgname ."'\n";
        warn "         is already available in APT repositories\n";
        warn "Maintainer: ", $found->{Maintainer}, "\n";
        my $short_desc = (split( /\n/, $found->{LongDesc} ))[0];
        warn "Description: $short_desc\n";
    }
    elsif ($apt_contents) {
        my $found
            = $apt_contents->find_perl_module_package( $self->perlname );

        if ($found) {
            ( my $mod_name = $self->perlname ) =~ s/-/::/g;
            warn "**********\n";
            warn "NOTICE: the package '$found', available in APT repositories\n";
            warn "        already contains a module named "
                . $self->perlname . "\n";
        }
    }

    return $found ? 1 : 0;
}

=item warning I<string> ...

In verbose mode, prints supplied arguments on STDERR, prepended with C<W: > and
suffixed with a new line.

Does nothing in non-verbose mode.

=cut

sub warning {
    my $self = shift;

    return unless $self->cfg->verbose;

    warn "W: ", @_, "\n";
}

=back

=head1 AUTHOR

dh-make-perl was created by Paolo Molaro.

It is currently maintained by Gunnar Wolf and others, under the umbrella of the
Debian Perl Group <debian-perl@lists.debian.org>

=head1 BUGS

Please report any bugs or feature requests to the Debian Bug Tracking System
(L<http://bugs.debian.org/>, use I<dh-make-perl> as package name) or to the
L<debian-perl@lists.debian.org> mailing list.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc DhMakePerl

You can also look for information at:

=over 4

=item * Debian Bugtracking System

L<http://bugs.debian.org/dh-make-perl>

=back



=head1 COPYRIGHT & LICENSE

=over 4

=item Copyright (C) 2000, 2001 Paolo Molaro <lupus@debian.org>

=item Copyright (C) 2002, 2003, 2008 Ivan Kohler <ivan-debian@420.am>

=item Copyright (C) 2003, 2004 Marc 'HE' Brockschmidt <he@debian.org>

=item Copyright (C) 2005-2007 Gunnar Wolf <gwolf@debian.org>

=item Copyright (C) 2006 Frank Lichtenheld <djpig@debian.org>

=item Copyright (C) 2007-2010 Gregor Herrmann <gregoa@debian.org>

=item Copyright (C) 2007-2010 Damyan Ivanov <dmn@debian.org>

=item Copyright (C) 2008, Roberto C. Sanchez <roberto@connexer.com>

=item Copyright (C) 2009-2010, Salvatore Bonaccorso <salvatore.bonaccorso@gmail.com>

=back

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License version 2 as published by the Free
Software Foundation.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 51 Franklin
Street, Fifth Floor, Boston, MA 02110-1301 USA.

=cut

1; # End of DhMakePerl
