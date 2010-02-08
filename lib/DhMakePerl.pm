package DhMakePerl;

use warnings;
use strict;
use 5.010;    # we use smart matching

use base 'Class::Accessor';
use Pod::Usage;

__PACKAGE__->mk_accessors(qw( cfg apt_contents main_dir meta ));

=head1 NAME

DhMakePerl - create Debian source package from CPAN dist

=head1 VERSION

Version 0.63

=cut

our $VERSION = '0.64';

=head1 SYNOPSIS

TO BE FILLED

    use DhMakePerl;

    my $foo = DhMakePerl->new();
    ...

=head1 METHODS

=over

=cut

use AptPkg::Cache ();
use Array::Unique;
use Config qw( %Config );
use CPAN ();
use Cwd qw( getcwd );
use Debian::AptContents       ();
use Debian::Control           ();
use Debian::Control::FromCPAN ();
use Debian::Dependencies      ();
use Debian::Dependency        ();
use Debian::Version qw(deb_ver_cmp);
use Parse::DebianChangelog;
use DhMakePerl::Config;
use DhMakePerl::PodParser ();
use Email::Date::Format qw(email_date);
use File::Basename qw( basename dirname );
use File::Copy qw( copy move );
use File::Find qw( find );
use File::Spec::Functions qw( catfile );
use IO::File                   ();
use Module::CoreList           ();
use Module::Depends::Intrusive ();
use Module::Depends            ();
use Text::Wrap qw( fill wrap );
use Tie::File;
use User::pwent qw(:FIELDS);
use WWW::Mechanize ();
use YAML           ();
use version qw( qv );

# TODO:
# * get more info from the package (maybe using CPAN methods)

my ($oldest_perl_version, $debstdversion, $priority,
    $section,             $depends,       $bdepends,
    $bdependsi,           $maintainer,    $arch,
    $closes,              $date,          $debiandir,
    $startdir,
);
our %overrides;

$debstdversion = '3.8.4';
$priority      = 'optional';
$section       = 'perl';
$depends       = Debian::Dependencies->new('${perl:Depends}');

# this is the version in 'oldstable'. No much point on depending on something
# older
$oldest_perl_version = '5.8.8-7';

$bdependsi = Debian::Dependencies->new("perl");
$arch      = 'all';
$date      = email_date(time);
$startdir  = getcwd();

# If we're being required rather than called as a main command, then
# return now without doing any work.  This facilitates easier testing.

my ( $perlname, $modulepm );
my ($pkgname, $srcname,

    # $version is the version from the perl module itself
    $version,

    # $pkgversion is the resulting version of the package: User's
    # --version=s or "$version-1"
    $pkgversion,
    $desc, $longdesc, $copyright, $author, $upsurl
);
my ( $extrasfields, $extrapfields );
my ($module_build);
my ( @docs, @examples, @args );

# use Array::Unique for @docs and @examples
tie @examples, 'Array::Unique';
tie @docs,     'Array::Unique';

my $mod_cpan_version;

=item main_file(file_name)

Constructs a file name relative to the main source directory, L</main_dir>

=cut

sub main_file {
    my( $self, $file ) = @_;

    catfile( $self->main_dir, $file );
}

=item debian_file(file_name)

Constructs a file name relative to the debian/ subdurectory of the main source
directory.

=cut

sub debian_file {
    my( $self, $file ) = @_;

    catfile( $self->main_file('debian'), $file );
}

=item backup_file(file_name)

Creates a backup copy of the specified file by adding C<.bak> to its name.

Does nothing unless the C<backups> option is set.

=cut

sub backup_file {
    my( $self, $file ) = @_;

    copy( $file, "$file.bak" )
        if $self->cfg->backups;
}

sub run {
    my ($self) = @_;

    unless ( $self->cfg ) {
        $self->cfg( DhMakePerl::Config->new );
        $self->cfg->parse_command_line_options;
        $self->cfg->parse_config_file;
    }

    chomp($date);

    $bdepends = Debian::Dependencies->new(
        'debhelper (>=' . $self->cfg->dh . ')',
    );

    # Help requested? Nice, we can just die! Isn't it helpful?
    die pod2usage(-message => "See `man 1 dh-make-perl' for details.\n") if $self->cfg->help;
    die "CPANPLUS support disabled, sorry" if $self->cfg->cpanplus;

    if ( $self->cfg->command eq 'refresh-cache' ) {
        $self->get_apt_contents;

        return 0;
    }

    if ( $self->cfg->command eq 'dump-config' ) {
        print $self->cfg->dump_config;

        return 0;
    }

    $arch = $self->cfg->arch if $self->cfg->arch;

    $maintainer = $self->get_maintainer( $self->cfg->email );

    $desc = $self->cfg->desc || '';

    if ( $self->cfg->command eq 'refresh' ) {
        print "Engaging refresh mode\n" if $self->cfg->verbose;
        $self->main_dir('.');

        die $self->debian_file('rules.bak') . " already exists. Aborting!\n"
            if ( -e $self->debian_file('rules.bak') and 'rules' ~~ $self->cfg->only );

        die $self->debian_file('copyright.bak')
            . " already exists. Aborting!\n"
            if ( -e $self->debian_file('copyright.bak') and 'copyright' ~~ $self->cfg->only );

        die $self->debian_file('control.bak') . " already exists. Aborting!\n"
            if ( -e $self->debian_file('control.bak') and 'control' ~~ $self->cfg->only );

        $self->process_meta;
        ( $pkgname, $version )
            = $self->extract_basic();    # also detects arch-dep package
        $module_build
            = ( -f $self->main_file('Build.PL') ) ? "Module-Build" : "MakeMaker";

        $self->extract_docs if 'docs' ~~ $self->cfg->only;
        $self->extract_examples if 'examples' ~~ $self->cfg->only;
        print "Found docs: @docs\n" if @docs and $self->cfg->verbose;
        print "Found examples: @examples\n" if @examples and $self->cfg->verbose;

        if ( 'rules' ~~ $self->cfg->only ) {
            $self->backup_file( $self->debian_file('rules') );
            $self->create_rules( $self->debian_file('rules') );
            if (! -f $self->debian_file('compat') or $self->cfg->dh == 7) {
                $self->create_compat( $self->debian_file('compat') );
            }
        }

        if ( 'docs' ~~ $self->cfg->only or 'examples' ~~ $self->cfg->only) {
            $self->update_file_list( docs => \@docs, examples => \@examples );
        }

        if ( 'copyright' ~~ $self->cfg->only ) {
            $self->backup_file( $self->debian_file('copyright') );
            $self->create_copyright("$debiandir/copyright");
        }

        if ( 'control' ~~ $self->cfg->only ) {
            my $control = Debian::Control::FromCPAN->new;
            $control->read( $self->debian_file('control') );
            if ( -e catfile( $self->debian_file('patches'), 'series' ) ) {
                $self->add_quilt( $control );
            }
            else {
                $self->drop_quilt( $control );
            }

            if( my $apt_contents = $self->get_apt_contents ) {
                $control->dependencies_from_cpan_meta(
                    $self->meta, $self->get_apt_contents, $self->cfg->verbose );
            }
            else {
                warn "No APT contents can be loaded.\n";
                warn "Please install 'apt-file' package and run 'apt-file update'\n";
                warn "as root.\n";
                warn "Dependencies not updated.\n";
            }

            $control->prune_perl_deps();

            $self->backup_file( $self->debian_file('control') );
            $control->write( $self->debian_file('control') );
        }

        print "--- Done\n" if $self->cfg->verbose;
        return 0;
    }

    if ( $self->cfg->command eq 'locate' ) {
        @ARGV == 1
            or die
                 "--locate command requires exactly one non-option argument\n";

        my $apt_contents = $self->get_apt_contents;

        unless ($apt_contents) {
            die <<EOF;
Unable to locate module packages, because APT Contents files
are not available on the system.

Install the 'apt-file' package, run 'apt-file update' as root
and retry.
EOF
        }
        my $mod = $ARGV[0];

        if ( defined( my $core_since = $self->is_core_module($mod) ) ) {
            print "$mod is in Perl core (package perl)";
            print $core_since ? " since $core_since\n" : "\n";
            return 0;
        }

        if ( my $pkg = $apt_contents->find_perl_module_package($mod) ) {
            print "$mod is in $pkg package\n";
            return 0;
        }

        print "$mod is not found in any Debian package\n";
        return 1;
    }

    $self->load_overrides();
    my $tarball = $self->setup_dir();
    $self->process_meta;
    $self->findbin_fix();

    ( $pkgname, $version ) = $self->extract_basic();
    if ( defined $self->cfg->packagename ) {
        $pkgname = $self->cfg->packagename;
    }
    unless ( defined $self->cfg->version ) {
        $pkgversion = $version . "-1";
    }
    else {
        $pkgversion = $self->cfg->version;
    }

    move( $tarball, dirname($tarball) . "/${pkgname}_${version}.orig.tar.gz" )
        if ( $tarball && $tarball =~ /(?:\.tar\.gz|\.tgz)$/ );

    # fail before further inspection of the source
    # $debiandir is set by extract_basic() above
    -d $debiandir
        && die
        "The directory $debiandir is already present and I won't overwrite it: remove it yourself.\n";

    my $apt_contents = $self->get_apt_contents;

    $depends += Debian::Dependency->new('${shlibs:Depends}')
        if $arch eq 'any';
    $depends += Debian::Dependency->new('${misc:Depends}');
    my $extradeps = $self->extract_depends( $apt_contents, 0 );
    $depends += $extradeps;
    $depends += Debian::Dependencies->new( $self->cfg->depends )
        if $self->cfg->depends;

    $module_build = ( -f $self->main_file('Build.PL') ) ? "Module-Build" : "MakeMaker";
    $self->extract_docs;
    $self->extract_examples;

    $bdepends += Debian::Dependency->new('perl (>= 5.10) | libmodule-build-perl')
        if ( $module_build eq "Module-Build" );

    my ( $extrabdepends, $extrabdependsi );
    if ( $arch eq 'any' ) {
        $extrabdepends = $self->extract_depends( $apt_contents, 1 )
            + $extradeps;
    }
    else {
        $extrabdependsi = $self->extract_depends( $apt_contents, 1 )
            + $extradeps,
            ;
    }

    $bdepends += Debian::Dependencies->new( $self->cfg->bdepends )
        if $self->cfg->bdepends;
    $bdepends += $extrabdepends;

    $bdependsi += Debian::Dependencies->new( $self->cfg->bdependsi )
        if $self->cfg->bdependsi;
    $bdependsi += $extrabdependsi;

    $self->apply_overrides();

    die "Cannot find a description for the package: use the --desc switch\n"
        unless $desc;
    print "Package does not provide a long description - ",
        " Please fill it in manually.\n"
        if ( !defined $longdesc or $longdesc =~ /^\s*\.?\s*$/ )
            and $self->cfg->verbose;
    print "Using maintainer: $maintainer\n" if $self->cfg->verbose;
    print "Found docs: @docs\n" if $self->cfg->verbose;
    print "Found examples: @examples\n" if @examples and $self->cfg->verbose;

    # start writing out the data
    mkdir( $debiandir, 0755 ) || die "Cannot create $debiandir dir: $!\n";
    $self->create_control("$debiandir/control");
    if ( defined $self->cfg->closes ) {
        $closes = $self->cfg->closes;
    }
    else {
        $closes = $self->get_itp($pkgname);
    }
    $self->create_changelog( "$debiandir/changelog", $closes );
    $self->create_rules("$debiandir/rules");
    $self->create_compat("$debiandir/compat");
    $self->create_watch("$debiandir/watch") if $upsurl;

    #create_readme("$debiandir/README.Debian");
    $self->create_copyright("$debiandir/copyright");
    $self->update_file_list( docs => \@docs, examples => \@examples );
    $self->apply_final_overrides();
    $self->build_package
        if $self->cfg->build or $self->cfg->install;
    $self->install_package if $self->cfg->install;
    print "--- Done\n" if $self->cfg->verbose;

    $self->package_already_exists($apt_contents);

    return(0);
}

sub get_apt_contents {
    my $self = shift;

    return $self->apt_contents
        if $self->apt_contents;

    my $apt_c = Debian::AptContents->new(
        {   homedir => $self->cfg->home_dir,
            dist    => $self->cfg->dist,
            sources => $self->cfg->sources_list,
            verbose => $self->cfg->verbose,
        }
    );

    undef $apt_c unless $apt_c->cache;

    return $self->apt_contents($apt_c);
}

sub is_core_module {
    my ( $self, $module, $ver ) = @_;

    my $v = Module::CoreList->first_release($module, $ver);   # 5.009002

    return unless defined $v;

    $v = version->new($v);                              # v5.9.2
    ( $v = $v->normal ) =~ s/^v//;                      # "5.9.2"

    return $v;
}

=item configure_cpan

Configure CPAN module. It is safe to call this method more than once, it will
do nothing if CPAN is already configured.

=cut

sub configure_cpan {
    my $self = shift;

    return if $CPAN::Config_loaded;

    CPAN::Config->load( be_silent => not $self->cfg->verbose );

    unshift( @{ $CPAN::Config->{'urllist'} }, $self->cfg->cpan_mirror )
        if $self->cfg->cpan_mirror;

    $CPAN::Config->{'build_dir'}         = $ENV{'HOME'} . "/.cpan/build";
    $CPAN::Config->{'cpan_home'}         = $ENV{'HOME'} . "/.cpan/";
    $CPAN::Config->{'histfile'}          = $ENV{'HOME'} . "/.cpan/history";
    $CPAN::Config->{'keep_source_where'} = $ENV{'HOME'} . "/.cpan/source";
    $CPAN::Config->{'tar_verbosity'}     = $self->cfg->verbose ? 'v' : '';
    $CPAN::Config->{'load_module_verbosity'}
        = $self->cfg->verbose ? 'verbose' : 'silent';
}

=item find_cpan_module

Returns CPAN::Module object that corresponds to the supplied argument. Returns undef if no module is found by CPAN.

=cut

sub find_cpan_module {
    my( $self, $name ) = @_;

    my $mod;

    # expand() returns a list of matching items when called in list
    # context, so after retrieving it, we try to match exactly what
    # the user asked for. Specially important when there are
    # different modules which only differ in case.
    #
    # This Closes: #451838
    my @mod = CPAN::Shell->expand( 'Module', '/^' . $name . '$/' );

    foreach (@mod) {
        my $file = $_->cpan_file();
        $file =~ s#.*/##;          # remove directory
        $file =~ s/(.*)-.*/$1/;    # remove version and extension
        $file =~ s/-/::/g;         # convert dashes to colons
        if ( $self->cfg->cpan and $file eq $self->cfg->cpan ) {
            $mod = $_;
            last;
        }
    }
    $mod = shift @mod unless ($mod);

    return $mod;
}

sub setup_dir {
    my ($self) = @_;

    my ( $dist, $mod, $tarball );
    $mod_cpan_version = '';
    if ( $self->cfg->cpan ) {
        my ($new_maindir, $orig_pwd);

        # CPAN::Distribution::get() sets $ENV{'PWD'} to $CPAN::Config->{build_dir}
        # so we have to save it here
        $orig_pwd = $ENV{'PWD'};

        # Is the module a core module?
        if ( $self->is_core_module( $self->cfg->cpan ) ) {
            die $self->cfg->cpan 
            . " is a standard module. Will not build without --core-ok.\n"
                unless $self->cfg->core_ok;
        }

        $self->configure_cpan;

        $mod = $self->find_cpan_module( $self->cfg->cpan )
            or die "Can't find '" . $self->cfg->cpan . "' module on CPAN\n";
        $mod_cpan_version = $mod->cpan_version;

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

    if ( $arch eq 'any' ) {
        $archspec = `dpkg --print-architecture`;
        chomp($archspec);
    }
    else {
        $archspec = $arch;
    }

    $debname = "${pkgname}_$version-1_$archspec.deb";

    system("dpkg -i $startdir/$debname") == 0
        || die "Cannot install package $startdir/$debname\n";
}

sub process_meta {
    my ($self) = @_;

    my $file = $self->main_file('META.yml');

    # META.yml non-existent?
    unless ( -f $file ) {
        $self->meta({});
        return;
    }

    # Command line option nometa causes this function not to be run
    if( $self->cfg->nometa ) {
        $self->meta({});
        return;
    }

    my $yaml;

    # YAML::LoadFile dies when it cannot properly parse a file - catch it in
    # an eval, and if it dies, return -again- just an empty hashref.
    eval { $yaml = YAML::LoadFile($file); };
    if ($@) {
        print "Error parsing $file - Ignoring it.\n";
        print "Please notify module upstream maintainer.\n";
        $yaml = {};
    }

    if (ref $yaml ne 'HASH') {
        print "$file does not contain a hash - Ignoring it\n";
        $yaml = {};
    }

    # Returns a simple hashref with all the keys/values defined in META.yml
    $self->meta($yaml);
}

sub extract_basic_copyright {
    my ($self) = @_;

    for my $f ( map( $self->main_file($_), qw(LICENSE LICENCE COPYING) ) ) {
        if ( -f $f ) {
            my $fh = $self->_file_r($f);
            return join( '', $fh->getlines );
        }
    }
    return;
}

sub extract_basic {
    my ($self) = @_;

    ( $perlname, $version ) = $self->extract_name_ver();
    find( sub { $self->check_for_xs }, $self->main_dir );
    $pkgname = lc $perlname;
    $pkgname = 'lib' . $pkgname unless $pkgname =~ /^lib/;
    $pkgname .= '-perl';

    # ensure policy compliant names and versions (from Joeyh)...
    $pkgname =~ s/[^-.+a-zA-Z0-9]+/-/g;

    $srcname = $pkgname;
    $version =~ s/[^-.+a-zA-Z0-9]+/-/g;
    $version = "0$version" unless $version =~ /^\d/;

    print "Found: $perlname $version ($pkgname arch=$arch)\n" if $self->cfg->verbose;
    $debiandir = $self->main_file('debian');

    $upsurl = "http://search.cpan.org/dist/$perlname/";

    $copyright = $self->extract_basic_copyright();
    if ($modulepm) {
        $self->extract_desc($modulepm);
    }

    find(
        sub {
            $File::Find::name !~ $self->cfg->exclude
                && /\.(pm|pod)$/
                && $self->extract_desc($_);
        },
        $self->main_dir
    );

    return ( $pkgname, $version );
}

sub makefile_pl {
    my ($self) = @_;

    return $self->main_file('Makefile.PL');
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

sub extract_name_ver {
    my ($self) = @_;

    my ( $name, $ver );

    if ( defined $self->meta->{name} and defined $self->meta->{version} ) {
        $name = $self->meta->{name};
        $ver  = $self->meta->{version};
        if ( $ver =~ s/^v// ) {    # v4.43.43?
            $ver =~ s/\.(\d\d\d)(\d\d\d)/.$1.$2/;    # 2.003004 -> 2.003.004
            $ver =~ s/\.0+/./g;                      # 2.003.004 -> 2.3.4
        }
    }
    else {
        ( $name, $ver ) = $self->extract_name_ver_from_makefile( $self->makefile_pl );
    }

    $name =~ s/::/-/g;
    return ( $name, $ver );
}

sub extract_name_ver_from_makefile {
    my ( $self, $makefile ) = @_;
    my ( $file, $name, $ver, $vfrom, $dir );

    {
        local $/ = undef;
        my $fh = $self->_file_r($makefile);
        $file = $fh->getline;
    }

    # Replace q[quotes] by "quotes"
    $file =~ s/q\[(.+)]/'$1'/g;

    # Get the name
    if ($file =~ /([\'\"]?)
	    DISTNAME\1\s*
	    (=>|,)
	    \s*
	    ([\'\"]?)
	    (\S+)\3/xs
        )
    {

        # Regular MakeMaker
        $name = $4;
    }
    elsif (
        $file =~ /([\'\"]?)
		 NAME\1\s*
		 (=>|,)
		 \s*
		 ([\'\"]?)
		 (\S+)\3/xs
        )
    {

        # Regular MakeMaker
        $name = $4;
    }
    elsif (
        $file =~ m{
                        name
                         \s*
                         \(?                    # Optional open paren
                             ([\'\"]?)          # Optional open quote
                                 (\S+)          # Quoted name
                             \1                 # Optional close quote
                         \)?                    # Optional close paren
                         \s*;
                 }xs
        )
    {

        # Module::Install syntax
        $name = $2;
    }
    $name =~ s/,.*$//;

    # band aid: need to find a solution also for build in directories
    # warn "name is $name (cpan name: $self->cfg->cpan)\n";
    $name = $self->cfg->cpan     if ( $name eq '__PACKAGE__' && $self->cfg->cpan );
    $name = $self->cfg->cpanplus if ( $name eq '__PACKAGE__' && $self->cfg->cpanplus );

    # Get the version
    if ( defined $self->cfg->version ) {

        # Explicitly specified
        $ver = $self->cfg->version;

    }
    elsif ( $file =~ /([\'\"]?)VERSION\1\s*(=>|,)\s*([\'\"]?)(\S+)\3/s ) {

        # Regular MakeMaker
        $ver = $4;

        # Where is the version taken from?
        $vfrom = $4
            if $file
                =~ /([\'\"]?)VERSION_FROM\1\s*(=>|,)\s*([\'\"]?)(\S+)\3/s;

    }
    elsif ( $file =~ /([\'\"]?)VERSION_FROM\1\s*(=>|,)\s*([\'\"]?)(\S+)\3/s )
    {

        # Regular MakeMaker pointing to where the version is taken from
        $vfrom = $4;

    }
    elsif ( 
        $file =~ m{
            \bversion\b\s*                  # The word version
            \(?\s*                          # Optional open-parens
            (['"]?)                         # Optional quotes
            ([\d_.]+)                       # The actual version.
            \1                              # Optional close-quotes
            \s*\)?                          # Optional close-parens.
        }sx 
    ) {

        # Module::Install
        $ver = $2;
    }

    $dir = dirname($makefile) || './';

    $modulepm = "$dir/$vfrom" if defined $vfrom;

    for ( ( $name, $ver ) ) {
        next unless defined;
        next unless /^\$/;

        # decode simple vars
        s/(\$\w+).*/$1/;
        if ( $file =~ /\Q$_\E\s*=\s*([\'\"]?)(\S+)\1\s*;/ ) {
            $_ = $2;
        }
    }

    unless ( defined $ver ) {
        local $/ = "\n";

        # apply the method used by makemaker
        if (    defined $dir
            and defined $vfrom
            and -f "$dir/$vfrom"
            and -r "$dir/$vfrom" )
        {
            my $fh = $self->_file_r("$dir/$vfrom");
            while ( my $lin = $fh->getline ) {
                if ( $lin =~ /([\$*])(([\w\:\']*)\bVERSION)\b.*\=/ ) {
                    no strict;

                    #warn "ver: $lin";
                    $ver = ( eval $lin )[0];
                    last;
                }
            }
            $fh->close;
        }
        else {
            if ($mod_cpan_version) {
                $ver = $mod_cpan_version;
                warn "Cannot use internal module data to gather the "
                    . "version; using cpan_version\n";
            }
            else {
                die "Cannot use internal module data to gather the "
                    . "version; use --cpan or --version\n";
            }
        }
    }

    return ( $name, $ver );
}

sub extract_desc {
    my ( $self, $file ) = @_;

    my ( $parser, $modulename );
    $parser = new DhMakePerl::PodParser;
    return unless -f $file;
    $parser->set_names(qw(NAME DESCRIPTION DETAILS COPYRIGHT AUTHOR AUTHORS));
    $parser->parse_from_file($file);
    if ($desc) {

        # No-op - We already have it, probably from the command line

    }
    elsif ( $self->meta->{abstract} ) {

        # Get it from META.yml
        $desc = $self->meta->{abstract};

    }
    elsif ( my $my_desc = $parser->get('NAME') ) {

        # Parse it, fix it, send it!
        $my_desc =~ s/^\s*\S+\s+-\s+//s;
        $my_desc =~ s/^\s+//s;
        $my_desc =~ s/\s+$//s;
        $my_desc =~ s/^([^\s])/ $1/mg;
        $my_desc =~ s/\n.*$//s;
        $desc = $my_desc;
    }

    # Replace linefeeds (not followed by a space) in $desc with spaces
    $desc =~ s/\n(?=\S)/ /gs;

    unless ($longdesc) {
        $longdesc 
            = $parser->get('DESCRIPTION')
            || $parser->get('DETAILS')
            || $desc;
        ( $modulename = $perlname ) =~ s/-/::/g;
        $longdesc =~ s/This module/$modulename/;

        local ($Text::Wrap::columns) = 78;
        $longdesc = fill( "", "", $longdesc );
    }
    if ( defined $longdesc && $longdesc !~ /^$/ ) {
        $longdesc =~ s/^\s+//s;
        $longdesc =~ s/\s+$//s;
        $longdesc =~ s/^\t/ /mg;
        $longdesc =~ s/^\s*$/ ./mg;
        $longdesc =~ s/^\s*/ /mg;
        $longdesc =~ s/^([^\s])/ $1/mg;
        $longdesc =~ s/\r//g;
    }

    $copyright 
        = $copyright
        || $parser->get('COPYRIGHT')
        || $parser->get('LICENSE')
        || $parser->get('COPYRIGHT & LICENSE');
    if ( !$author ) {
        if ( ref $self->meta->{author} ) {

            # Does the author information appear in META.yml?
            $author = join( ', ', @{ $self->meta->{author} } );
        }
        else {

            # Get it from the POD - and clean up
            # trailing/preceding spaces!
            $author = $parser->get('AUTHOR') || $parser->get('AUTHORS');
            $author =~ s/^\s*(\S.*\S)\s*$/$1/gs if $author;
        }
    }

    $parser->cleanup;
}

sub extract_docs {
    my ( $self ) = @_;

    my $dir = $self->main_dir;

    $dir .= '/' unless $dir =~ m(/$);
    find(
        sub {
            if (   $File::Find::dir eq '.svn-base'
                or $File::Find::dir eq '.git' )
            {
                $File::Find::prune = 1;
                return;
            }
            push( @docs, substr( $File::Find::name, length($dir) ) )
                if (
                    /^\b(README|TODO|BUGS|NEWS|ANNOUNCE)\b/i
                and !/\.(pod|pm)$/
                and ( !$self->cfg->exclude
                    or $File::Find::name !~ $self->cfg->exclude )
                and !/\.svn-base$/
                );
        },
        $dir
    );
}

sub extract_examples {
    my ( $self ) = @_;

    my $dir = $self->main_dir;

    $dir .= '/' unless $dir =~ m{/$};
    find(
        sub {
            return if $_ eq '.';  # skip the directory itself
            my $exampleguess = substr( $File::Find::name, length($dir) );
            push( @examples,
                ( -d $exampleguess ? $exampleguess . '/*' : $exampleguess ) )
                if ( /^(examples?|eg|samples?)$/i
                and ( !$self->cfg->exclude or $File::Find::name !~ $self->cfg->exclude )
                );
        },
        $dir
    );
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

sub nice_perl_ver {
    my( $self, $v ) = @_;

    if( $v =~ /\.(\d+)$/ ) {
        my $minor = $1;
        if( length($minor) % 3 ) {
            # right-pad with zeroes so that the number of digits after the dot
            # is a multiple of 3
            $minor .= '0' x ( 3 - length($minor) % 3 );
        }

        my $ver = 0 + substr( $minor, 0, 3 );
        if( length($minor) > 3 ) {
            $ver .= '.' . ( 0 + substr( $minor, 3 ) );
        }
        $v =~ s/\.\d+$/.$ver/;
    }

    return $v;
}

sub find_debs_for_modules {

    my ( $self, $dep_hash, $apt_contents ) = @_;

    my @uses;
    my $debs = Debian::Dependencies->new();

    foreach my $module ( keys(%$dep_hash) ) {
        my $dep;
        if ( my $ver = $self->is_core_module( $module, $dep_hash->{$module} )
        ) {
            print "= $module is a core module\n" if $self->cfg->verbose;

            $dep = Debian::Dependency->new( 'perl', $ver );
            $debs->add($dep) if $dep->satisfies( "perl (>= $oldest_perl_version)" );

            next;
        }

        push @uses, $module;
    }

    my @missing;

    foreach my $module (@uses) {

        my $dep;
        if ( $module eq 'perl' ) {
            $dep = Debian::Dependency->new( 'perl',
                $self->nice_perl_ver( $dep_hash->{$module} ) );
        }
        elsif ($apt_contents) {
            $dep = $apt_contents->find_perl_module_package( $module,
                $dep_hash->{$module} );
        }

        if ($dep) {
            print "+ $module found in " . $dep->pkg ."\n"
                if $self->cfg->verbose;
        }
        else {
            print "- $module not found in any package\n";
            push @missing, $module;

            my $mod = $self->find_cpan_module($module);
            if ($mod) {
                ( my $dist = $mod->distribution->base_id ) =~ s/-v?\d[^-]*$//;
                my $pkg = 'lib' . lc($dist) . '-perl';

                print "   CPAN contains it in $dist\n";
                print "   substituting package name of $pkg\n";

                $dep = Debian::Dependency->new( $pkg, $dep_hash->{$module} );
            }
            else {
                print "   - it seems it is not available even via CPAN\n";
            }
        }

        $debs->add($dep) if $dep;
    }

    return $debs, \@missing;
}

sub extract_depends {
    my ( $self, $apt_contents, $build_deps ) = @_;

    my ($dep_hash);
    local @INC = ( $self->main_dir, @INC );

    # try Module::Depends, but if that fails then
    # fall back to Module::Depends::Intrusive.

    eval {
        $dep_hash
            = $self->run_depends( 'Module::Depends', $build_deps );
    };
    if ($@) {
        if ($self->cfg->verbose) {
            warn '=' x 70, "\n";
            warn "First attempt (Module::Depends) at a dependency\n"
                . "check failed. Missing/bad META.yml?\n"
                . "Trying again with Module::Depends::Intrusive ... \n";
            warn '=' x 70, "\n";
        }

        eval {
            $dep_hash
                = $self->run_depends( 'Module::Depends::Intrusive', $build_deps );
        };
        if ($@) {
            if ($self->cfg->verbose) {
                warn '=' x 70, "\n";
                warn
                    "Could not find the " . ( $build_deps ? 'build-' : '' ) 
                    . "dependencies for the requested module.\n";
                warn "Generated error: $@";

                warn "Please bug the module author to provide a proper META.yml\n"
                    . "file.\n"
                    . "Automatic find of " . ( $build_deps ? 'build-' : '' )
                    . "dependencies failed. You may want to \n"
                    . "retry using the '" . ( $build_deps ? 'b' : '' )
                    . "depends' option\n";
                warn '=' x 70, "\n";
            }
        }
    }

    my ( $debs, $missing )
        = $self->find_debs_for_modules( $dep_hash, $apt_contents );

    if ($self->cfg->verbose) {
        print "\n";
        print "Needs the following debian packages: "
            . join( ", ", @$debs ) . "\n"
            if (@$debs);
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
                "You do not have 'apt-file' currently installed, or have not ran",
                "'apt-file update' - If you install it and run 'apt-file update' as",
                "root, I will be able to tell you which Debian packages are those",
                "modules in (if they are packaged)." );
        }

        if ($self->cfg->requiredeps) {
            die $missing_debs_str;
        }
        else {
            print $missing_debs_str;
        }

    }

    return $debs;
}

sub get_itp {
    return if $ENV{NO_NETWORK};

    my ( $self, $package ) = @_;

    my $wnpp
        = "http://bugs.debian.org/cgi-bin/pkgreport.cgi?pkg=wnpp;includesubj=ITP: $package";
    my $mech = WWW::Mechanize->new();

    $mech->get($wnpp);

    my @links = $mech->links();

    foreach my $link (@links) {
        my $desc = $link->text();

        if ($desc && $desc =~ /^ITP: $package /) {
            return $1 if $link->url =~ m/bug=(\d+)$/;
        }

    }
    return 0;
}

sub check_for_xs {
    my ($self) = @_;

    # we need the relative path here. Otherwise the check will give bogus
    # results if the working dir matches the pattern
    my $rel_path = substr( $File::Find::name, length( $self->main_dir ) );
    ( $rel_path !~ m{/(?:examples?|samples|eg|t|docs?)/} )
            and
    ( !$self->cfg->exclude or $rel_path !~ $self->cfg->exclude )
        && /\.(xs|c|cpp|cxx)$/i
        && do {
        $arch = 'any';
        };
}

=item add_quilt( $control )

Plugs quilt into F<debian/rules> and F<debian/control>. Depends on
F<debian/rules> being in DH7 three-liner format. Also bumps the debhelper
build-dependency to 7.0.50 (the first version to support overrides) and adds
debian/README.source documenting quilt usage.

=cut

sub add_quilt {
    my( $self, $control ) = @_;

    my @rules;
    tie @rules, 'Tie::File', $self->debian_file('rules')
        or die "Unable to read rules: $!";

    splice @rules, 1, 0, ( '', 'include /usr/share/quilt/quilt.make' )
        unless grep /quilt\.make/, @rules;

    push @rules,
        '',
        'override_dh_auto_configure: $(QUILT_STAMPFN)',
        "\tdh_auto_configure"
        unless grep /QUILT_STAMPFN/, @rules;

    push @rules,
        '',
        'override_dh_auto_clean: unpatch',
        "\tdh_auto_clean"
        unless grep /override_dh_auto_clean:.*unpatch/, @rules;

    # add build-dependency on quilt
    $control->source->Build_Depends->add('quilt');

    # bump build-dependency of DH to 7.0.50
    $control->source->Build_Depends->add('debhelper (>= 7.0.50)');
        # a later prune() will remove redundant >= 7

    # README.source
    my $quilt_mini_doc = <<EOF;
This package uses quilt for managing all modifications to the upstream
source. Changes are stored in the source package as diffs in
debian/patches and applied during the build.

See /usr/share/doc/quilt/README.source for a detailed explaination.
EOF

    my $readme = $self->debian_file('README.source');
    my $quilt_already_documented = 0;
    my $readme_source_exists = -e $readme;
    if($readme_source_exists) {
        my @readme;
        tie @readme, 'Tie::File', $readme
            or die "Unable to tie '$readme': $!";

        for( @readme ) {
            if( m{quilt/README.source} ) {
                $quilt_already_documented = 1;
                last;
            }
        }
    }

    print "README.source already documents quilt\n"
        if $quilt_already_documented and $self->cfg->verbose;

    unless($quilt_already_documented) {
        my $fh;
        open( $fh, '>>', $readme )
            or die "Unable to open '$readme' for writing: $!";

        print $fh "\n\n" if $readme_source_exists;
        print $fh $quilt_mini_doc;
        close $fh;
    }
}

=item drop_quilt( $control )

removes quilt from F<debian/rules> and F<debian/control>. Expects that
L<|add_quilt> was used to add quilt to F<debian/rules>.

If F<debian/README.source> exists, references to quilt are removed from it (and
the file removed if empty after that).

=cut

sub drop_quilt {
    my( $self, $control ) = @_;

    my @rules;
    tie @rules, 'Tie::File', $self->debian_file('rules')
        or die "Unable to read rules: $!";

    # look for the quilt include line and remove it and the previous empty one
    for( my $i = 1; $i < @rules; $i++ ) {
        if ( $rules[$i] eq ''
                and $rules[$i+1] eq 'include /usr/share/quilt/quilt.make' ) {
            splice @rules, $i, 2;
            last;
        }
    }

    # remove the QUILT_STAMPFN dependency override
    for( my $i = 1; $i < @rules; $i++ ) {
        if ( $rules[$i] eq ''
                and $rules[$i+1] eq 'override_dh_auto_configure: $(QUILT_STAMPFN)'
                and $rules[$i+2] eq "\tdh_auto_configure"
                and $rules[$i+3] eq '' ) {
            splice @rules, $i, 3;
            last;
        }
    }

    # remove unpatch dependency in clean
    for( my $i = 1; $i < @rules; $i++ ) {
        if ( $rules[$i] eq ''
                and $rules[$i+1] eq 'override_dh_auto_clean: unpatch'
                and $rules[$i+2] eq "\tdh_auto_clean"
                and $rules[$i+3] eq '' ) {
            splice @rules, $i, 3;
            last;
        }
    }

    # remove build-dependency on quilt
    $control->source->Build_Depends->remove('quilt');

    # if no overrides are used, lower dh dependency from 7.0.50 to 7
    if( not grep /^override_dh_/, @rules ) {
        $control->source->Build_Depends->remove('debhelper (>= 7.0.50)');
        $control->source->Build_Depends->add('debhelper (>= 7)');
    }

    # README.source
    my $readme = $self->debian_file('README.source');

    if( -e $readme ) {
        my @readme;
        tie @readme, 'Tie::File', $readme
            or die "Unable to tie '$readme': $!";

        my( $start, $end );
        for( my $i = 0; defined( $_ = $readme[$i] ); $i++ ) {
            if( m{^This package uses quilt } ) {
                $start = $i;
                next;
            }

            if( defined($start)
                    and m{^See /usr/share/doc/quilt/README.source} ) {
                $end = $i;
                last;
            }
        }

        if( defined($start) and defined($end) ) {
            print "Removing refences to quilt from README.source\n"
                if $self->cfg->verbose;

            splice @readme, $start, $end-$start+1;

            # file is now empty?
            if( join( '', @readme ) =~ /^\s*$/ ) {
                unlink $readme
                    or die "unlink($readme): $!";
            }
        }
    }
}

sub update_file_list( $ % ) {
    my ( $self, %p ) = @_;

    while ( my ( $file, $new_content ) = each %p ) {
        # pkgname.foo file
        my $pkg_file = $self->debian_file("$pkgname.$file");
        my %uniq_content;
        my @existing_content;

        # if a package.foo exists read its values first
        if ( -r $pkg_file ) {
            my $fh                = $self->_file_r($pkg_file);
            @existing_content = $fh->getlines;
            chomp(@existing_content);

            # make list of files for package.foo unique
            $uniq_content{$_} = 1 for @existing_content;
        }

        $uniq_content{$_} = 1 for @$new_content;

        # write package.foo file with unique entries
        open F, '>', $pkg_file or die $!;
        for ( @existing_content, @$new_content ) {

            # we have the unique hash
            # we delete from it each printed line
            # so if a line is not in the hash, this means we have already
            # printed it
            next unless exists $uniq_content{$_};

            delete $uniq_content{$_};
            print F "$_\n";
        }
        close F;
    }
}

sub create_control {
    my ( $self, $file ) = @_;

    my $fh = $self->_file_w($file);

    if (    $arch ne 'all'
        and !defined($self->cfg->bdepends)
        and !defined($self->cfg->bdependsi) )
    {
        $bdepends += $bdependsi;
        @$bdependsi = ();
    }

    $fh->print("Source: $srcname\n");
    $fh->print("Section: $section\n");
    $fh->print("Priority: $priority\n");
    local $Text::Wrap::break     = ', ';
    local $Text::Wrap::separator = ",\n";
    $fh->print( wrap( '', ' ', "Build-Depends: $bdepends\n" ) ) if $bdepends;

    $fh->print( wrap( '', ' ', "Build-Depends-Indep: $bdependsi\n" ) )
        if $bdependsi;

    $fh->print($extrasfields) if defined $extrasfields;

    if ($self->cfg->pkg_perl) {
        $fh->print(
            "Maintainer: Debian Perl Group <pkg-perl-maintainers\@lists.alioth.debian.org>\n"
        );
        $fh->print("Uploaders: $maintainer\n");
    }
    else {
        $fh->print("Maintainer: $maintainer\n");
    }
    $fh->print("Standards-Version: $debstdversion\n");
    $fh->print("Homepage: $upsurl\n") if $upsurl;
    do {
        $fh->print(
            "Vcs-Svn: svn://svn.debian.org/pkg-perl/trunk/$srcname/\n");
        $fh->print(
            "Vcs-Browser: http://svn.debian.org/viewsvn/pkg-perl/trunk/$srcname/\n"
        );
    } if $self->cfg->pkg_perl;
    $fh->print("\n");
    $fh->print("Package: $pkgname\n");
    $fh->print("Architecture: $arch\n");
    $fh->print( wrap( '', ' ', "Depends: $depends\n" ) ) if $depends;
    $fh->print($extrapfields) if defined $extrapfields;
    $fh->print(
        "Description:" . (($desc =~ m/^ /) ? "" : " ") . "$desc\n$longdesc\n .\n This description was automagically extracted from the module by dh-make-perl.\n"
    );
    $fh->close;
}

sub create_changelog {
    my ( $self, $file, $bug ) = @_;

    my $fh  = $self->_file_w($file);

    my $closes = $bug ? " (Closes: #$bug)" : '';
    my $changelog_dist = $self->cfg->pkg_perl ? "UNRELEASED" : "unstable";

    $fh->print("$srcname ($pkgversion) $changelog_dist; urgency=low\n");
    $fh->print("\n  * Initial Release.$closes\n\n");
    $fh->print(" -- $maintainer  $date\n");

    #$fh->print("Local variables:\nmode: debian-changelog\nEnd:\n");
    $fh->close;
}

sub create_rules {
    my ( $self, $file ) = @_;

    my ( $rulesname, $error );
    $rulesname = 'rules.dh7.tiny';

    for my $source (
        catfile( $self->cfg->home_dir, $rulesname ),
        catfile( $self->cfg->data_dir, $rulesname )
    ) {
        copy( $source, $file ) && do {
            print "Using rules: $source\n" if $self->cfg->verbose;
            last;
        };
        $error = $!;
    }
    die "Cannot copy rules file ($rulesname): $error\n" unless -e $file;
    chmod( 0755, $file );
}

sub create_compat {
    my ( $self, $file ) = @_;

    my $fh = $self->_file_w($file);
    $fh->print( $self->cfg->dh, "\n" );
    $fh->close;
}

sub copyright_from_changelog {
  my ( $self, $firstmaint, $firstyear ) = @_;
  my %maintainers = ();
  @{$maintainers{$firstmaint}} = ($firstyear);
  my $chglog = Parse::DebianChangelog->init( { infile => 'debian/changelog' } );
  foreach($chglog->data()) {
    my $person = $_->Maintainer;
    my $date = $_->Date;
    my @date_pieces = split(" ", $date);
    my $year = $date_pieces[3];
    if(defined($maintainers{$person})) {
      push @{$maintainers{$person}}, $year;
      @{$maintainers{$person}} = sort(@{$maintainers{$person}});
    } else {
      @{$maintainers{$person}} = ($year);
    }
  }
  my @strings;
  foreach my $maint_name (keys %maintainers) {
    my $str = " ";
    my %uniq = map { $_ => 0 } @{$maintainers{$maint_name}};
    foreach(sort keys %uniq) {
      $str .= $_;
      $str .= ", ";
    }
    $str .= $maint_name;
    push @strings, $str;
  }
  @strings = sort @strings;
  return @strings;
}

sub create_copyright {
    my ( $self, $filename ) = @_;

    my ( $fh, %fields, @res, @incomplete, $year );
    $fh = $self->_file_w($filename);

    # In case $author spawns more than one line, indent them all.
    my $cprt_author = $author || '(information incomplete)';
    $cprt_author =~ s/\n/\n    /gs;
    $cprt_author =~ s/^\s*$/    ./gm;

    push @res, "Format-Specification: http://svn.debian.org/wsvn/dep/web/deps/dep5.mdwn?op=file&rev=135";

    # Header section
    %fields = (
        Name       => $perlname,
        Maintainer => $cprt_author,
        Source     => $upsurl
    );
    for my $key ( keys %fields ) {
        my $full = "$key";
        if ( $fields{$key} ) {
            push @res, "$full: $fields{$key}";
        }
        else {
            push @incomplete, "Could not get the information for $full";
        }
    }
    push( @res,
        "DISCLAIMER: This copyright info was automatically extracted ",
        " from the perl module. It may not be accurate, so you better ",
        " check the module sources in order to ensure the module for its ",
        " inclusion in Debian or for general legal information. Please, ",
        " if licensing information is incorrectly generated, file a bug ",
        " on dh-make-perl.",
        " NOTE: Don't forget to remove this disclaimer once you are happy",
        " with this file." );
    push @res, '';

    # Files section - We cannot "parse" the module's licensing
    # information for anything besides general information.
    push @res, 'Files: *';

    # Absence of author should have already been reported in the
    # Header section
    push @res, "Copyright: $cprt_author";

    # This is far from foolproof, but usually works with most
    # boilerplate-generated modules.
    #
    # We go over the most common combinations only

    my ( %texts, %licenses );
    %texts = (
        'Artistic' =>
            " This program is free software; you can redistribute it and/or modify\n"
            . " it under the terms of the Artistic License, which comes with Perl.\n"
            . " .\n"
            . " On Debian GNU/Linux systems, the complete text of the Artistic License\n"
            . " can be found in `/usr/share/common-licenses/Artistic'",
        'GPL-1+' =>
            " This program is free software; you can redistribute it and/or modify\n"
            . " it under the terms of the GNU General Public License as published by\n"
            . " the Free Software Foundation; either version 1, or (at your option)\n"
            . " any later version.\n"
            . " .\n"
            . " On Debian GNU/Linux systems, the complete text of the GNU General\n"
            . " Public License can be found in `/usr/share/common-licenses/GPL'",
        'GPL-2' =>
            " This program is free software; you can redistribute it and/or modify\n"
            . " it under the terms of the GNU General Public License as published by\n"
            . " the Free Software Foundation; version 2 dated June, 1991.\n"
            . " .\n"
            . " On Debian GNU/Linux systems, the complete text of version 2 of the GNU\n"
            . " General Public License can be found in `/usr/share/common-licenses/GPL-2'",
        'GPL-2+' =>
            " This program is free software; you can redistribute it and/or modify\n"
            . " it under the terms of the GNU General Public License as published by\n"
            . " the Free Software Foundation; version 2 dated June, 1991, or (at your\n"
            . " option) any later version.\n"
            . " .\n"
            . " On Debian GNU/Linux systems, the complete text of version 2 of the GNU\n"
            . " General Public License can be found in `/usr/share/common-licenses/GPL-2'",
        'GPL-3' =>
            " This program is free software; you can redistribute it and/or modify\n"
            . " it under the terms of the GNU General Public License as published by\n"
            . " the Free Software Foundation; version 3 dated June, 2007.\n"
            . " .\n"
            . " On Debian GNU/Linux systems, the complete text of version 3 of the GNU\n"
            . " General Public License can be found in `/usr/share/common-licenses/GPL-3'",
        'GPL-3+' =>
            " This program is free software; you can redistribute it and/or modify\n"
            . " it under the terms of the GNU General Public License as published by\n"
            . " the Free Software Foundation; version 3 dated June, 2007, or (at your\n"
            . " option) any later version\n"
            . " .\n"
            . " On Debian GNU/Linux systems, the complete text of version 3 of the GNU\n"
            . " General Public License can be found in `/usr/share/common-licenses/GPL-3'",
        'Apache-2.0' =>
            " Licensed under the Apache License, Version 2.0 (the \"License\");\n"
            . " you may not use this file except in compliance with the License.\n"
            . " You may obtain a copy of the License at\n"
            . "     http://www.apache.org/licenses/LICENSE-2.0\n"
            . " Unless required by applicable law or agreed to in writing, software\n"
            . " distributed under the License is distributed on an \"AS IS\" BASIS,\n"
            . " WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.\n"
            . " See the License for the specific language governing permissions and\n"
            . " limitations under the License.\n"
            . " .\n"
            . " On Debian GNU/Linux systems, the complete text of the Apache License,\n"
            . " Version 2.0 can be found in `/usr/share/common-licenses/Apache-2.0'",
        'unparsable' =>
            " No known license could be automatically determined for this module.\n"
            . " If this module conforms to a commonly used license, please report this\n"
            . " as a bug in dh-make-perl. In any case, please find the proper license\n"
            . " and fix this file!"
    );

    if ( $self->meta->{license} or $copyright ) {
        my $mangle_cprt;

        # Pre-mangle the copyright information for the common similar cases
        $mangle_cprt = $copyright || '';    # avoid warning
        $mangle_cprt =~ s/GENERAL PUBLIC LICENSE/GPL/g;

        # Of course, more licenses (i.e. LGPL, BSD-like, Public
        # Domain, etc.) could be added... Feel free to do so. Keep in
        # mind that many licenses are not meant to be used as
        # templates (i.e. you must add the author name and some
        # information within the licensing text as such).
        if (   $self->meta->{license} and $self->meta->{license} =~ /perl/i
            or $mangle_cprt =~ /terms\s*as\s*Perl\s*itself/is )
        {
            $licenses{'GPL-1+'}   = 1;
            $licenses{'Artistic'} = 1;
        }
        else {
            if ( $mangle_cprt =~ /[^L]GPL/ ) {
                if ( $mangle_cprt =~ /GPL.*version\s*1.*later\s+version/is ) {
                    $licenses{'GPL-1+'} = 1;
                }
                elsif (
                    $mangle_cprt =~ /GPL.*version\s*2.*later\s+version/is )
                {
                    $licenses{'GPL-2+'} = 1;
                }
                elsif ( $mangle_cprt =~ /GPL.*version\s*2/is ) {
                    $licenses{'GPL-2'} = 1;
                }
                elsif (
                    $mangle_cprt =~ /GPL.*version\s*3.*later\s+version/is )
                {
                    $licenses{'GPL-3+'} = 1;
                }
                elsif ( $mangle_cprt =~ /GPL.*version\s*3/is ) {
                    $licenses{'GPL-3'} = 1;
                }
            }

            if ( $mangle_cprt =~ /Artistic\s*License/is ) {
                $licenses{'Artistic'} = 1;
            }

            if ( $mangle_cprt =~ /Apache\s*License.*2\.0/is ) {
                $licenses{'Apache-2.0'} = 1;
            }

            # Other licenses?

            if ( !keys(%licenses) ) {
                $licenses{unparsable} = 1;
                push( @incomplete,
                    "Licensing information is present, but cannot be parsed"
                );
            }
        }

        push @res, "License: " . join( ' or ', keys %licenses );

    }
    else {
        push @res,        "License: ";
        push @incomplete, 'No licensing information found';
    }

    # debian/* files information - We default to the module being
    # licensed as the superset of the module and Perl itself.
    $licenses{'Artistic'} = $licenses{'GPL-1+'} = 1;
    $year = (localtime)[5] + 1900;
    push( @res, "", "Files: debian/*" );
    if($self->cfg->command eq 'refresh') {
      my @from_changelog = $self->copyright_from_changelog($maintainer, $year);
      $from_changelog[0] = "Copyright:" . $from_changelog[0];
      push @res, @from_changelog;
    } else {
      push @res, "Copyright: $year, $maintainer";
    }
    push @res, "License: " . join( ' or ', keys %licenses );

    map { $texts{$_} && push( @res, '', "License: $_", $texts{$_} ) }
        keys %licenses;

    $fh->print( join( "\n", @res, '' ) );
    $fh->close;

    $self->_warn_incomplete_copyright( join( "\n", @incomplete ) )
        if @incomplete;
}

sub create_readme {
    my ( $self, $filename ) = @_;

    my $fh = $self->_file_w($filename);
    $fh->print(
        "This is the debian package for the $perlname module.
It was created by $maintainer using dh-make-perl.
"
    );
    $fh->close;
}

sub create_watch {
    my ( $self, $filename ) = @_;

    my $fh = $self->_file_w($filename);

    my $version_re = 'v?(\d[\d.-]+)\.(?:tar(?:\.gz|\.bz2)?|tgz|zip)';

    $fh->print(
        "version=3
$upsurl   .*/$perlname-$version_re\$
"
    );
    $fh->close;
}

sub get_maintainer {
    my ($self, $email ) = @_;

    my ( $user, $pwnam, $name, $mailh );
    $user = $ENV{LOGNAME} || $ENV{USER};
    $pwnam = getpwuid($<);
    die "Cannot determine current user\n" unless $pwnam;
    if ( defined $ENV{DEBFULLNAME} ) {
        $name = $ENV{DEBFULLNAME};
    }
    else {
        $name = $pwnam->gecos;
        $name =~ s/,.*//;
    }
    $user ||= $pwnam->name;
    $name ||= $user;
    $email ||= ( $ENV{DEBEMAIL} || $ENV{EMAIL} );
    unless ($email) {
        chomp( $mailh = `cat /etc/mailname` );
        $email = $user . '@' . $mailh;
    }

    $email =~ s/^(.*)\s+<(.*)>$/$2/;

    return "$name <$email>";
}

sub load_overrides {
    my ($self) = @_;

    eval {
        my $overrides = catfile( $self->cfg->data_dir, 'overrides' );
        do $overrides if -f $overrides;
        $overrides = catfile( $self->cfg->home_dir, 'overrides');
        do $overrides if -f $overrides;
    };
    if ($@) {
        die "Error when processing the overrides files: $@";
    }
}

sub apply_overrides {
    my ($self) = @_;

    my ( $data, $val, $subkey );

    ( $data, $subkey ) = $self->get_override_data();
    return unless defined $data;
    $pkgname = $val
        if (
        defined(
            $val = $self->get_override_val( $data, $subkey, 'pkgname' )
        )
        );
    $srcname = $val
        if (
        defined(
            $val = $self->get_override_val( $data, $subkey, 'srcname' )
        )
        );
    $section = $val
        if (
        defined(
            $val = $self->get_override_val( $data, $subkey, 'section' )
        )
        );
    $priority = $val
        if (
        defined(
            $val = $self->get_override_val( $data, $subkey, 'priority' )
        )
        );
    $depends = Debian::Dependencies->new($val)
        if (
        defined(
            $val = $self->get_override_val( $data, $subkey, 'depends' )
        )
        );
    $bdepends = Debian::Dependencies->new($val)
        if (
        defined(
            $val = $self->get_override_val( $data, $subkey, 'bdepends' )
        )
        );
    $bdependsi = Debian::Dependencies->new($val)
        if (
        defined(
            $val = $self->get_override_val( $data, $subkey, 'bdependsi' )
        )
        );
    $desc = $val
        if (
        defined( $val = $self->get_override_val( $data, $subkey, 'desc' ) ) );
    $longdesc = $val
        if (
        defined(
            $val = $self->get_override_val( $data, $subkey, 'longdesc' )
        )
        );
    $pkgversion = $val
        if (
        defined(
            $val = $self->get_override_val( $data, $subkey, 'version' )
        )
        );
    $arch = $val
        if (
        defined( $val = $self->get_override_val( $data, $subkey, 'arch' ) ) );
    @docs = split( /\s+/, $val )
        if (
        defined( $val = $self->get_override_val( $data, $subkey, 'docs' ) ) );

    $extrasfields = $val
        if (
        defined(
            $val = $self->get_override_val( $data, $subkey, 'sfields' )
        )
        );
    $extrapfields = $val
        if (
        defined(
            $val = $self->get_override_val( $data, $subkey, 'pfields' )
        )
        );
    $maintainer = $val
        if (
        defined(
            $val = $self->get_override_val( $data, $subkey, 'maintainer' )
        )
        );

    # fix longdesc if needed
    $longdesc =~ s/^\s*/ /mg;
}

sub apply_final_overrides {
    my ($self) = @_;

    my ( $data, $val, $subkey );

    ( $data, $subkey ) = $self->get_override_data();
    return unless defined $data;
    $self->get_override_val( $data, $subkey, 'finish' );
}

sub get_override_data {
    my ($self) = @_;

    my ( $data, $checkver, $subkey );
    $data = $overrides{$perlname};

    return unless defined $data;
    die "Value of '$perlname' in overrides not a hashref\n"
        unless ref($data) eq 'HASH';
    if ( defined( $checkver = $data->{checkver} ) ) {
        die "checkver not a function\n" unless ( ref($checkver) eq 'CODE' );
        $subkey = &$checkver( $self->main_dir );
    }
    else {
        $subkey = $pkgversion;
    }
    return ( $data, $subkey );
}

sub get_override_val {
    my ( $self, $data, $subkey, $key ) = @_;

    my $val;
    $val
        = defined( $data->{ $subkey . $key } )
        ? $data->{ $subkey . $key }
        : $data->{$key};
    return &$val() if ( defined($val) && ref($val) eq 'CODE' );
    return $val;
}

sub package_already_exists {
    my( $self, $apt_contents ) = @_;

    my $apt_cache = AptPkg::Cache->new;
    my $found = $apt_cache->packages->lookup($pkgname);

    if ($found) {
        warn "**********\n";
        warn "WARNING: a package named\n";
        warn "              '$pkgname'\n";
        warn "         is already available in APT repositories\n";
        warn "Maintainer: ", $found->{Maintainer}, "\n";
        my $short_desc = (split( /\n/, $found->{LongDesc} ))[0];
        warn "Description: $short_desc\n";
    }
    elsif ($apt_contents) {
        my $found = $apt_contents->find_perl_module_package($perlname);

        if ($found) {
            my $mod_name = $perlname =~ s/-/::/g;
            warn "**********\n";
            warn "NOTICE: the package '$found', available in APT repositories\n";
            warn "        already contains a module named $perlname\n";
        }
    }

    return $found ? 1 : 0;
}

sub _warn_incomplete_copyright {
    my $self = shift;

    print '*' x 10, '
Copyright information incomplete!

Upstream copyright information could not be automatically determined.

If you are building this package for your personal use, you might disregard
this information; however, if you intend to upload this package to Debian
(or in general, if you plan on distributing it), you must look into the
complete copyright information.

The causes for this warning are:
', @_, "\n";
}

sub _file_r {
    my ( $self, $filename ) = @_;

    my $fh = IO::File->new( $filename, 'r' )
        or die "Cannot open $filename: $!\n";
    return $fh;
}

sub _file_w {
    my ( $self, $filename ) = @_;

    my $fh = IO::File->new( $filename, 'w' )
        or die "Cannot open $filename: $!\n";
    return $fh;
}

sub _file_rw {
    my ( $self, $filename ) = @_;

    my $fh = IO::File->new( $filename, 'r+' )
        or die "Cannot open $filename: $!\n";
    return $fh;
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
