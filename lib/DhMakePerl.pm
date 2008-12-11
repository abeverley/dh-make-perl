package DhMakePerl;

use warnings;
use strict;

=head1 NAME

DhMakePerl - create Debian source package from CPAN dist

=head1 VERSION

Version 0.51

=cut

our $VERSION = '0.51';

=head1 SYNOPSIS

TO BE FILLED

    use DhMakePerl;

    my $foo = DhMakePerl->new();
    ...

=head1 METHODS

=cut

use DhMakePerl::PodParser;
use YAML;
use IO::File;
use File::Basename;
use File::Find;
use File::Copy qw(copy move);
use User::pwent;
use Getopt::Long;
use Cwd;
use CPAN;
use Module::Depends;
use Module::Depends::Intrusive;
use Email::Date::Format qw(email_date);
use Text::Wrap;
use Module::CoreList ();
use AptPkg::Config;
use Debian::Dependency;
use Debian::Dependencies;

# TODO:
# * get more info from the package (maybe using CPAN methods)

use Debian::AptContents;
use Debian::Dependency;

my ($min_perl_version, $debstdversion, $priority,  $section,
    @depends,          @bdepends,      @bdependsi, $maintainer,
    $arch,             $closes,        $date,      $debiandir,
    $startdir,
);
our %overrides;

$debstdversion = '3.8.0';
$priority      = 'optional';
$section       = 'perl';
@depends       = ( Debian::Dependency->new( '${perl:Depends}' ) );

# 5.6.0-12 is where arch-indep modules are moved in /usr/share/perl5
# (according to dh_perl)
# if the module has stricter requirements, this build-dependency
# is replaced below by calling substitute_perl_dependency
$min_perl_version = '5.6.0-12';

@bdependsi = ( Debian::Dependency->new( 'perl', $min_perl_version ) );
$arch      = 'all';
$date      = email_date(time);
$startdir  = getcwd();

# If we're being required rather than called as a main command, then
# return now without doing any work.  This facilitates easier testing.

my ( $perlname, $maindir, $modulepm, $meta );
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
my ( @docs, @examples, $changelog, @args );

my $opt_dh           = 7;
my $opt_dist         = '{sid,unstable}';
my $opt_sources_list = '/etc/apt/sources.list';
my $opt_verbose      = 1;
my $opt_email        = '';
my $opt_exclude      = '(?:\/|^)(?:CVS|\.svn)\/';
my $opt_datadir      = '/usr/share/dh-make-perl';
my $opt_homedir      = "$ENV{HOME}/.dh-make-perl";

my ($opt_arch,        $opt_basepkgs, $opt_bdepends,    $opt_bdependsi,
    $opt_depends,     $opt_build,    $opt_install,     $opt_core_ok,
    $opt_cpan,        $opt_cpanplus, $opt_cpan_mirror, $opt_closes,
    $opt_dbflags,     $opt_desc,     $opt_help,        $opt_nometa,
    $opt_notest,      $opt_pkg_perl, $opt_requiredeps, $opt_version,
    $opt_packagename, $opt_refresh,  $opt_refresh_cache
);

my $mod_cpan_version;

sub run {
    $opt_dbflags = $> == 0 ? "" : "-rfakeroot";
    chomp($date);

    GetOptions(
        'arch=s'          => \$opt_arch,
        'basepkgs=s'      => \$opt_basepkgs,
        'bdepends=s'      => \$opt_bdepends,
        'bdependsi=s'     => \$opt_bdependsi,
        'build!'          => \$opt_build,
        'core-ok'         => \$opt_core_ok,
        'cpan=s'          => \$opt_cpan,
        'cpanplus=s'      => \$opt_cpanplus,
        'closes=i'        => \$opt_closes,
        'cpan-mirror=s'   => \$opt_cpan_mirror,
        'dbflags=s'       => \$opt_dbflags,
        'depends=s'       => \$opt_depends,
        'desc=s'          => \$opt_desc,
        'exclude|i:s{,}'  => \$opt_exclude,
        'help'            => \$opt_help,
        'install!'        => \$opt_install,
        'nometa'          => \$opt_nometa,
        'notest'          => \$opt_notest,
        'pkg-perl!'       => \$opt_pkg_perl,
        'requiredeps'     => \$opt_requiredeps,
        'version=s'       => \$opt_version,
        'e|email=s'       => \$opt_email,
        'p|packagename=s' => \$opt_packagename,
        'refresh|R'       => \$opt_refresh,
        'dh=i'            => \$opt_dh,
        'sources-list=s'  => \$opt_sources_list,
        'dist=s'          => \$opt_dist,
        'verbose!'        => \$opt_verbose,
        'data-dir=s'      => \$opt_datadir,
        'home-dir=s'      => \$opt_homedir,
        'refresh-cache'   => \$opt_refresh_cache,
    ) or die usage_instructions();

    @bdepends = ( Debian::Dependency->new( 'debhelper', $opt_dh ) );

    # Help requested? Nice, we can just die! Isn't it helpful?
    die usage_instructions() if $opt_help;
    die "CPANPLUS support disabled, sorry" if $opt_cpanplus;

    if ($opt_refresh_cache) {
        my $apt_contents = Debian::AptContents->new({
            homedir      => $opt_homedir,
            dist         => $opt_dist,
            sources_file => $opt_sources_list,
            verbose      => $opt_verbose,
        });

        return 0;
    }

    $arch = $opt_arch if defined $opt_arch;

    $maintainer = get_maintainer($opt_email);

    if ( defined $opt_desc ) {
        $desc = $opt_desc;
    }
    else {
        $desc = '';
    }

    if ($opt_refresh) {
        print "Engaging refresh mode\n" if $opt_verbose;
        $maindir = '.';

        die "debian/rules.bak already exists. Aborting!\n"
            if -e "debian/rules.bak";

        die "debian/copyright.bak already exists. Aborting!\n"
            if -e "debian/copyright.bak";

        $meta = process_meta("$maindir/META.yml") if ( -f "$maindir/META.yml" );
        ( $pkgname, $version ) = extract_basic();  # also detects arch-dep package
        $module_build = ( -f "$maindir/Build.PL" ) ? "Module-Build" : "MakeMaker";
        $debiandir = './debian';
        extract_changelog($maindir);
        extract_docs($maindir);
        extract_examples($maindir);
        print "Found changelog: $changelog\n"
            if defined $changelog and $opt_verbose;
        print "Found docs: @docs\n" if $opt_verbose;
        print "Found examples: @examples\n" if @examples and $opt_verbose;
        copy( "$debiandir/rules", "$debiandir/rules.bak" );
        create_rules("$debiandir/rules");
        if (! -f "$debiandir/compat" or $opt_dh == 7) {
            create_compat("$debiandir/compat");
        }
        fix_rules( "$debiandir/rules", ( defined $changelog ? $changelog : '' ),
            \@docs, \@examples, );
        copy( "$debiandir/copyright", "$debiandir/copyright.bak" );
        create_copyright("$debiandir/copyright");
        print "--- Done\n" if $opt_verbose;
        return 0;
    }

    load_overrides();
    my $tarball = setup_dir();
    $meta = process_meta("$maindir/META.yml") if ( -f "$maindir/META.yml" );
    findbin_fix();

    ( $pkgname, $version ) = extract_basic();
    if ( defined $opt_packagename ) {
        $pkgname = $opt_packagename;
    }
    unless ( defined $opt_version ) {
        $pkgversion = $version . "-1";
    }
    else {
        $pkgversion = $opt_version;
    }

    move( $tarball, dirname($tarball) . "/${pkgname}_${version}.orig.tar.gz" )
        if ( $tarball && $tarball =~ /(?:\.tar\.gz|\.tgz)$/ );

    # fail before further inspection of the source
    # $debiandir is set by extract_basic() above
    -d $debiandir
        && die
        "The directory $debiandir is already present and I won't overwrite it: remove it yourself.\n";

    my $apt_contents = Debian::AptContents->new({
        homedir      => $opt_homedir,
        dist         => $opt_dist,
        sources_file => $opt_sources_list,
        verbose      => $opt_verbose,
    });

    undef($apt_contents) unless $apt_contents->cache;

    push @depends, Debian::Dependency->new('${shlibs:Depends}') if $arch eq 'any';
    push @depends, Debian::Dependency->new('${misc:Depends}');
    my $extradeps = extract_depends( $maindir, $apt_contents, 0 );
    push @depends, @$extradeps;
    push @depends, Debian::Dependencies->new($opt_depends) if $opt_depends;

    $module_build = ( -f "$maindir/Build.PL" ) ? "Module-Build" : "MakeMaker";
    extract_changelog($maindir);
    extract_docs($maindir);
    extract_examples($maindir);

    push @bdepends, Debian::Dependency->new('libmodule-build-perl')
        if ( $module_build eq "Module-Build" );

    my ( @extrabdepends, @extrabdependsi );
    if ( $arch eq 'any' ) {
        @extrabdepends = (
            @{ extract_depends( $maindir, $apt_contents, 1 ) },
            @$extradeps,
        );
    }
    else {
        @extrabdependsi = (
            @{ extract_depends( $maindir, $apt_contents, 1 ) },
            @$extradeps,
        );
    }

    push @bdepends, Debian::Dependencies->new($opt_bdepends) if $opt_bdepends;
    push @bdepends, @extrabdepends;

    push @bdependsi, Debian::Dependencies->new($opt_bdependsi) if $opt_bdependsi;
    push @bdependsi, @extrabdependsi;

    apply_overrides();

    die "Cannot find a description for the package: use the --desc switch\n"
        unless $desc;
    print "Package does not provide a long description - ",
        " Please fill it in manually.\n"
        if ( !defined $longdesc or $longdesc =~ /^\s*\.?\s*$/ ) and $opt_verbose;
    print "Using maintainer: $maintainer\n" if $opt_verbose;
    print "Found changelog: $changelog\n" if defined $changelog and $opt_verbose;
    print "Found docs: @docs\n" if $opt_verbose;
    print "Found examples: @examples\n" if @examples and $opt_verbose;

    # start writing out the data
    mkdir( $debiandir, 0755 ) || die "Cannot create $debiandir dir: $!\n";
    create_control("$debiandir/control");
    if ( defined $opt_closes ) {
        $closes = $opt_closes;
    }
    else {
        $closes = get_itp($pkgname);
    }
    create_changelog( "$debiandir/changelog", $closes );
    create_rules("$debiandir/rules");
    create_compat("$debiandir/compat");
    create_watch("$debiandir/watch") if $upsurl;

    #create_readme("$debiandir/README.Debian");
    create_copyright("$debiandir/copyright");
    fix_rules( "$debiandir/rules", ( defined $changelog ? $changelog : '' ),
        \@docs, \@examples );
    apply_final_overrides();
    build_package($maindir) if $opt_build or $opt_install;
    install_package($debiandir) if $opt_install;
    print "--- Done\n" if $opt_verbose;
    return(0);
}

sub usage_instructions {
    return <<"USAGE"
Usage:
$0 [ --build ] [ --install ] [ SOURCE_DIR | --cpan MODULE ]
$0 --refresh|-R
Other options: [ --desc DESCRIPTION ] [ --arch all|any ] [ --version VERSION ]
               [ --depends DEPENDS ] [ --bdepends BUILD-DEPENDS ]
               [ --bdependsi BUILD-DEPENDS-INDEP ] [ --cpan-mirror MIRROR ]
               [ --exclude|-i [REGEX] ] [ --notest ] [ --nometa ]
               [ --requiredeps ] [ --core-ok ] [ --basepkgs PKGSLIST ]
               [ --closes ITPBUG ] [ --packagename|-p PACKAGENAME ]
               [ --email|-e EMAIL ] [ --pkg-perl ] [ --dh <ver> ]
               [ --sources-list file ] [ --dist <pattern> ]
               [ --[no-]verbose ] [ --data-dir dir ]
USAGE
}

sub is_core_module {
    my $module = shift;

    my $core = $Module::CoreList::version{$]}
            || $Module::CoreList::version{$]+0};

    $core
        or die "Internal error: \$Module::CoreList::version{ $] } is empty";

    return exists( $core->{$module} );
}

sub setup_dir {
    my ( $dist, $mod, $cpanversion, $tarball );
    $mod_cpan_version = '';
    if ($opt_cpan) {
        my ($new_maindir);

        # Is the module a core module?
        if ( is_core_module($opt_cpan) ) {
            die "$opt_cpan is a standard module. Will not build without --core-ok.\n"
                unless $opt_core_ok;
        }

        # Make CPAN happy, make the user happy: Be more tolerant!
        # Accept names to be specified with double-colon, dash or slash
        $opt_cpan =~ s![/-]!::!g;

###		require CPAN;
        CPAN::Config->load( be_silent => not $opt_verbose );

        unshift( @{ $CPAN::Config->{'urllist'} }, $opt_cpan_mirror )
            if $opt_cpan_mirror;

        $CPAN::Config->{'build_dir'} = $ENV{'HOME'} . "/.cpan/build";
        $CPAN::Config->{'cpan_home'} = $ENV{'HOME'} . "/.cpan/";
        $CPAN::Config->{'histfile'}  = $ENV{'HOME'} . "/.cpan/history";
        $CPAN::Config->{'keep_source_where'} = $ENV{'HOME'} . "/.cpan/source";
        $CPAN::Config->{'tar_verbosity'} = $opt_verbose ? 'v' : '';
        $CPAN::Config->{'load_module_verbosity'}
            = $opt_verbose ? 'verbose' : 'silent';

        # This modification allows to retrieve all the modules that
        # match the user-provided string.
        #
        # expand() returns a list of matching items when called in list
        # context, so after retrieving it, I try to match exactly what
        # the user asked for. Specially important when there are
        # different modules which only differ in case.
        #
        # This Closes: #451838
        my @mod = CPAN::Shell->expand( 'Module', '/^' . $opt_cpan . '$/' )
            or die "Can't find '$opt_cpan' module on CPAN\n";
        foreach (@mod) {
            my $file = $_->cpan_file();
            $file =~ s#.*/##;          # remove directory
            $file =~ s/(.*)-.*/$1/;    # remove version and extension
            $file =~ s/-/::/g;         # convert dashes to colons
            if ( $file eq $opt_cpan ) {
                $mod = $_;
                last;
            }
        }
        $mod              = shift @mod unless ($mod);
        $mod_cpan_version = $mod->cpan_version;
        $cpanversion      = $CPAN::VERSION;
        $cpanversion =~ s/_.*//;

        $tarball = $CPAN::Config->{'keep_source_where'} . "/authors/id/";

        if ( $cpanversion < 1.59 ) {    # wild guess on the version number
            $dist = $CPAN::META->instance( 'CPAN::Distribution',
                $mod->{CPAN_FILE} );
            $dist->get || die "Cannot get $mod->{CPAN_FILE}\n";
            $tarball .= $mod->{CPAN_FILE};
            $maindir = $dist->{'build_dir'};
        }
        else {

            # CPAN internals changed
            $dist = $CPAN::META->instance( 'CPAN::Distribution',
                $mod->cpan_file );
            $dist->get || die "Cannot get ", $mod->cpan_file, "\n";
            $tarball .= $mod->cpan_file;
            $maindir = $dist->dir;
        }

        copy( $tarball, $ENV{'PWD'} );
        $tarball = $ENV{'PWD'} . "/" . basename($tarball);

        # build_dir contains a random part since 1.88_59
        # use the new CPAN::Distribution::base_id (introduced in 1.91_53)
        $new_maindir = $ENV{PWD} . "/"
            . ( $cpanversion < 1.9153 ? basename($maindir) : $dist->base_id );

        # rename existing directory
        if ( -d $new_maindir
            && system( "mv", "$new_maindir", "$new_maindir.$$" ) == 0 )
        {
            print '=' x 70, "\n";
            print
                "Unpacked tarball already existed, directory renamed to $new_maindir.$$\n";
            print '=' x 70, "\n";
        }
        system( "mv", "$maindir", "$new_maindir" ) == 0
            or die "Failed to move $maindir to $new_maindir: $!";
        $maindir = $new_maindir;

    }
    elsif ($opt_cpanplus) {
        die "CPANPLUS support is b0rken at the moment.";

        #  	        my ($cb, $href, $file);

# 		eval "use CPANPLUS 0.045;";
# 		$cb = CPANPLUS::Backend->new(conf => {debug => 1, verbose => 1});
# 		$href = $cb->fetch( modules => [ $opt_cpanplus ], fetchdir => $ENV{'PWD'});
# 		die "Cannot get $opt_cpanplus\n" if keys(%$href) != 1;
# 		$file = (values %$href)[0];
# 		print $file, "\n\n";
# 		$maindir = $cb->extract( files => [ $file ], extractdir => $ENV{'PWD'} )->{$file};
    }
    else {
        $maindir = shift(@ARGV) || '.';
        $maindir =~ s/\/$//;
    }
    return $tarball;
}

sub build_package {
    my $maindir = shift;

    # uhmf! dpkg-genchanges doesn't cope with the deb being in another dir..
    #system("dpkg-buildpackage -b -us -uc $opt_dbflags") == 0
    system("fakeroot make -C $maindir -f debian/rules clean");
    system("fakeroot make -C $maindir -f debian/rules binary") == 0
        || die "Cannot create deb package\n";
}

sub install_package {
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
    my ( $file, $yaml );
    $file = shift;

    # Command line option nometa causes this function not to be run
    return {} if $opt_nometa;

    # YAML::LoadFile has the bad habit of dying when it cannot properly parse
    # a file - Catch it in an eval, and if it dies, return -again- just an
    # empty hashref. Oh, were it not enough: It dies, but $! is not set, so we
    # check against $@. Crap, crap, crap :-/
    eval { $yaml = YAML::LoadFile($file); };
    if ($@) {
        print "Error parsing $file - Ignoring it.\n";
        print "Please notify module upstream maintainer.\n";
        $yaml = {};
    }

    # Returns a simple hashref with all the keys/values defined in META.yml
    return $yaml;
}

sub extract_basic_copyright {
    for my $f ( map( "$maindir/$_", qw(LICENSE LICENCE COPYING) ) ) {
        if ( -f $f ) {
            my $fh = _file_r($f);
            return join( '', $fh->getlines );
        }
    }
    return undef;
}

sub extract_basic {
    ( $perlname, $version ) = extract_name_ver();
    find( \&check_for_xs, $maindir );
    $pkgname = lc $perlname;
    $pkgname = 'lib' . $pkgname unless $pkgname =~ /^lib/;
    $pkgname .= '-perl'
        unless ( $pkgname =~ /-perl$/ and $opt_cpan !~ /::perl$/i );

    # ensure policy compliant names and versions (from Joeyh)...
    $pkgname =~ s/[^-.+a-zA-Z0-9]+/-/g;

    $srcname = $pkgname;
    $version =~ s/[^-.+a-zA-Z0-9]+/-/g;
    $version = "0$version" unless $version =~ /^\d/;

    print "Found: $perlname $version ($pkgname arch=$arch)\n" if $opt_verbose;
    $debiandir = "$maindir/debian";

    $upsurl = "http://search.cpan.org/dist/$perlname/";

    $copyright = extract_basic_copyright();
    if ($modulepm) {
        extract_desc($modulepm);
    }

    $opt_exclude = '^$' unless $opt_exclude;
    find(
        sub {
            $File::Find::name !~ /$opt_exclude/
                && /\.(pm|pod)$/
                && extract_desc($_);
        },
        $maindir
    );

    return ( $pkgname, $version );
}

sub makefile_pl {
    return "$maindir/Makefile.PL";
}

sub findbin_fix {

    # FindBin requires to know the name of the invoker - and requires it to be
    # Makefile.PL to function properly :-/
    $0 = makefile_pl();
    if ( exists $FindBin::{Bin} ) {
        FindBin::again();
    }
}

sub extract_name_ver {
    my ( $name, $ver, $makefile );
    $makefile = makefile_pl();

    if ( defined $meta->{name} and defined $meta->{version} ) {
        $name = $meta->{name};
        $ver  = $meta->{version};

    }
    else {
        ( $name, $ver ) = extract_name_ver_from_makefile($makefile);
    }

    $name =~ s/::/-/g;
    return ( $name, $ver );
}

sub extract_name_ver_from_makefile {
    my ( $file, $name, $ver, $vfrom, $dir, $makefile );
    $makefile = shift;

    {
        local $/ = undef;
        my $fh = _file_r($makefile);
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
    # warn "name is $name (cpan name: $opt_cpan)\n";
    $name = $opt_cpan     if ( $name eq '__PACKAGE__' && $opt_cpan );
    $name = $opt_cpanplus if ( $name eq '__PACKAGE__' && $opt_cpanplus );

    # Get the version
    if ( defined $opt_version ) {

        # Explicitly specified
        $ver = $opt_version;

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
            my $fh = _file_r("$dir/$vfrom");
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
    my ( $file, $parser, $modulename );
    $file   = shift;
    $parser = new DhMakePerl::PodParser;
    return unless -f $file;
    $parser->set_names(qw(NAME DESCRIPTION DETAILS COPYRIGHT AUTHOR AUTHORS));
    $parser->parse_from_file($file);
    if ($desc) {

        # No-op - We already have it, probably from the command line

    }
    elsif ( $meta->{abstract} ) {

        # Get it from META.yml
        $desc = $meta->{abstract};

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
        if ( ref $meta->{author} ) {

            # Does the author information appear in META.yml?
            $author = join( ', ', @{ $meta->{author} } );
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

sub extract_changelog {
    my ($dir) = shift;
    $dir .= '/' unless $dir =~ m(/$);
    find(
        sub {
            $changelog = substr( $File::Find::name, length($dir) )
                if ( !defined($changelog) && /^change(s|log)$/i
                and ( !$opt_exclude or $File::Find::name !~ /$opt_exclude/ )
                );
        },
        $dir
    );
}

sub extract_docs {
    my ($dir) = shift;
    $dir .= '/' unless $dir =~ m(/$);
    find(
        sub {
            push( @docs, substr( $File::Find::name, length($dir) ) )
                if ( /^(README|TODO|BUGS|NEWS|ANNOUNCE)/i
                and ( !$opt_exclude or $File::Find::name !~ /$opt_exclude/ )
                );
        },
        $dir
    );
}

sub extract_examples {
    my ($dir) = shift;
    $dir .= '/' unless $dir =~ m(/$);
    find(
        sub {
            push( @examples,
                substr( $File::Find::name, length($dir) ) . '/*' )
                if ( /^(examples?|eg|samples?)$/i
                and ( !$opt_exclude or $File::Find::name !~ /$opt_exclude/ )
                );
        },
        $dir
    );
}

# finds the list of modules that the distribution in $dir depends on
# if $build_deps is true, returns build-time dependencies, otherwise
# returns run-time dependencies
sub run_depends {
    my ( $depends_module, $dir, $build_deps ) = @_;

    no warnings;
    local *STDERR;
    open( STDERR, ">/dev/null" );
    my $mod_dep = $depends_module->new();

    $mod_dep->dist_dir($dir);
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
    my %deps;
    for (@_) {
        my $p = $_->pkg;
        my $v = $_->ver;
        if ( exists $deps{$p} ) {
            my $cur_ver = $deps{$p};

            $deps{$p} = $v
                if defined($v) and not defined($cur_ver)
                    or $AptPkg::Config::_config->system->versioning->compare(
                        $cur_ver, $v ) < 0;
        }
        else {
            $deps{$p} = $v;
        }

    }

    return map( Debian::Dependency->new( $_, $deps{$_} ), sort( keys(%deps) ) );
}

sub find_debs_for_modules {

    my ( $dep_hash, $apt_contents ) = @_;

    my @uses;

    foreach my $module ( keys(%$dep_hash) ) {
        if ( is_core_module($module) ) {
            print "= $module is a core module\n" if $opt_verbose;

            # TODO
            # see if there is a version requirement and if the core
            # module satisfies it. If it does, see if previous perl
            # releases satisfy it too and if needed, bump the perl
            # dependency to the lowest version that contains module
            # version satisfying the dependency
            next;
        }

        push @uses, $module;
    }

    my ( @debs, @missing );

    foreach my $module (@uses) {

        my $deb;
        if ( $module eq 'perl' ) {
            $deb = 'perl';
        }
        elsif ($apt_contents) {
            $deb = $apt_contents->find_perl_module_package($module);
        }

        if ($deb) {
            print "+ $module found in $deb\n" if $opt_verbose;
            if ( exists $dep_hash->{$module} ) {
                my $v = $dep_hash->{$module};
                $v =~ s/^v//;    # strip leading 'v' from version

                # perl versions need special handling
                if ( $module eq 'perl' and $v =~ /\.(\d+)$/ ) {
                    my $ver = 0 + substr( $1, 0, 3 );
                    if( length($1) > 3 ) {
                        $ver .= '.' . ( 0 + substr( $1, 3 ) );
                    }
                    $v =~ s/\.\d+$/.$ver/;

                    # no point depending on ancient perl versions
                    # perl is Priority: standard
                    next
                    if $AptPkg::Config::_config->system->versioning->compare(
                        $v, $min_perl_version
                    ) <= 0;
                }

                push @debs, Debian::Dependency->new( $deb, $v );
            }
            else {
                push @debs, Debian::Dependency->new($deb);
            }
        }
        else {
            print "- $module not found in any package\n";
            push @missing, $module;
        }
    }

    return \@debs, \@missing;
}

sub extract_depends {
    my $dir  = shift;
    my $apt_contents = shift;
    my $build_deps = shift;
    my ($dep_hash);
    local @INC = ( $dir, @INC );

    $dir .= '/' unless $dir =~ m/\/$/;

    # try Module::Depends, but if that fails then
    # fall back to Module::Depends::Intrusive.

    eval { $dep_hash = run_depends( 'Module::Depends', $dir, $build_deps ); };
    if ($@) {
        if ($opt_verbose) {
            warn '=' x 70, "\n";
            warn "First attempt (Module::Depends) at a dependency\n"
                . "check failed. Missing/bad META.yml?\n"
                . "Trying again with Module::Depends::Intrusive ... \n";
            warn '=' x 70, "\n";
        }

        eval {
            $dep_hash = run_depends(
                'Module::Depends::Intrusive', $dir, $build_deps );
        };
        if ($@) {
            if ($opt_verbose) {
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

    my( $debs, $missing ) = find_debs_for_modules( $dep_hash, $apt_contents );

    if ($opt_verbose) {
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
                "You do not have 'apt-file' currently installed - If you install it, I will",
                "be able to tell you which Debian packages are those modules in (if they are",
                "packaged)." );
        }

        if ($opt_requiredeps) {
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

    use WWW::Mechanize;

    my ($package) = shift @_;

    my $wnpp
        = "http://bugs.debian.org/cgi-bin/pkgreport.cgi?pkg=wnpp;includesubj=ITP: $package";
    my $mech = WWW::Mechanize->new();

    $mech->get($wnpp);

    my @links = $mech->links();

    foreach my $link (@links) {
        my $desc = $link->text();

        return $1 if $desc and $desc =~ /^#(\d+): ITP: $package /;
    }
    return 0;
}

sub check_for_xs {
    ( !$opt_exclude or $File::Find::name !~ /$opt_exclude/ )
        && /\.(xs|c|cpp|cxx)$/i
        && do {
        $arch = 'any';
        };
}

sub fix_rules {
    my ( $rules_file, $changelog_file, $docs, $examples, $test_line, $fh,
        @content );
    ( $rules_file, $changelog_file, $docs, $examples ) = @_;

    $fh      = _file_rw($rules_file);
    @content = $fh->getlines;

    $fh->seek( 0, 0 ) || die "Can't rewind $rules_file: $!";
    $fh->truncate(0) || die "Can't truncate $rules_file: $!";

    if ( $opt_dh < 7 ) {
        $test_line
            = ( $module_build eq 'Module-Build' )
            ? '$(PERL) Build test'
            : '$(MAKE) test';
        $test_line = "#$test_line" if $opt_notest;

        for (@content) {
            s/#CHANGES#/$changelog_file/g;
            s/#EXAMPLES#/join " ", @examples/eg;
            s/\s+dh_installexamples\s+$//g
                ;    # no need for empty dh_installexamples
            s/#DOCS#/join " ", @docs/eg;
            s/#TEST#/$test_line/g;
            $fh->print($_);
        }
    }
    else {
        for (@content) {
            if ($opt_notest) {
                s/dh build/dh build --before dh_auto_test\n\tdh build --after dh_auto_test/;
            }
            $fh->print($_)
        }
        if (@examples) {
            open F, '>>', "$maindir/debian/$pkgname.examples" or die $!;
            print F "$_\n" foreach @examples;
            close F;
        }
        if (@docs) {
            open F, '>>', "$maindir/debian/$pkgname.docs" or die $!;
            print F "$_\n" foreach @docs;
            close F;
        }
    }
    $fh->close;
}

sub create_control {
    my $fh = _file_w(shift);

    if (    $arch ne 'all'
        and !defined($opt_bdepends)
        and !defined($opt_bdependsi) )
    {
        @bdepends = prune_deps( @bdepends, @bdependsi );
        @bdependsi = ();
    }

    $fh->print("Source: $srcname\n");
    $fh->print("Section: $section\n");
    $fh->print("Priority: $priority\n");
    local $Text::Wrap::break     = ', ';
    local $Text::Wrap::separator = ",\n";
    $fh->print(
        wrap( '', ' ', "Build-Depends: " . join( ', ', @bdepends ) . "\n" )
    ) if @bdepends;

    $fh->print(
        wrap(
            '',
            ' ',
            "Build-Depends-Indep: " . join( ', ', @bdependsi ) . "\n"
        )
    ) if @bdependsi;

    $fh->print($extrasfields) if defined $extrasfields;

    if ($opt_pkg_perl) {
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
    } if $opt_pkg_perl;
    $fh->print("\n");
    $fh->print("Package: $pkgname\n");
    $fh->print("Architecture: $arch\n");
    $fh->print(
        wrap( '', ' ', "Depends: " . join( ', ', @depends ) . "\n" )
    ) if @depends;
    $fh->print($extrapfields) if defined $extrapfields;
    $fh->print(
        "Description: $desc\n$longdesc\n .\n This description was automagically extracted from the module by dh-make-perl.\n"
    );
    $fh->close;
}

sub create_changelog {
    my $fh  = _file_w(shift);
    my $bug = shift;

    my $closes = $bug ? " (Closes: #$bug)" : '';

    $fh->print("$srcname ($pkgversion) unstable; urgency=low\n");
    $fh->print("\n  * Initial Release.$closes\n\n");
    $fh->print(" -- $maintainer  $date\n");

    #$fh->print("Local variables:\nmode: debian-changelog\nEnd:\n");
    $fh->close;
}

sub create_rules {
    my ( $file, $rulesname, $error );
    ($file) = shift;
    $rulesname = (
          ( $opt_dh eq 7 )
        ? $arch eq 'all'
                ? 'rules.dh7.noxs'
                : 'rules.dh7.xs'
        : $arch eq 'all' ? "rules.$module_build.noxs"
        : "rules.$module_build.xs"
    );

    for my $source ( ( "$opt_homedir/$rulesname", "$opt_datadir/$rulesname" ) ) {
        copy( $source, $file ) && do {
            print "Using rules: $source\n" if $opt_verbose;
            last;
        };
        $error = $!;
    }
    die "Cannot copy rules file ($rulesname): $error\n" unless -e $file;
    chmod( 0755, $file );
}

sub create_compat {
    my $fh = _file_w(shift);
    $fh->print("$opt_dh\n");
    $fh->close;
}

sub create_copyright {
    my ( $fh, %fields, @res, @incomplete, $year );
    $fh = _file_w(shift);

    # In case $author spawns more than one line, indent them all.
    my $cprt_author = $author || '(information incomplete)';
    $cprt_author =~ s/\n/\n    /gs;
    $cprt_author =~ s/^\s*$/    ./gm;

    push @res, "Format-Specification:
    http://wiki.debian.org/Proposals/CopyrightFormat?action=recall&rev=196";

    # Header section
    %fields = (
        Name       => $perlname,
        Maintainer => $cprt_author,
        Source     => $upsurl
    );
    for my $key ( keys %fields ) {
        my $full = "Upstream-$key";
        if ( $fields{$key} ) {
            push @res, "$full: $fields{$key}";
        }
        else {
            push @incomplete, "Could not get the information for $full";
        }
    }
    push( @res,
        "Disclaimer: This copyright info was automatically extracted ",
        "    from the perl module. It may not be accurate, so you better ",
        "    check the module sources in order to ensure the module for its ",
        "    inclusion in Debian or for general legal information. Please, ",
        "    if licensing information is incorrectly generated, file a bug ",
        "    on dh-make-perl." );
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
            "    This program is free software; you can redistribute it and/or modify\n"
            . "    it under the terms of the Artistic License, which comes with Perl.\n"
            . "    On Debian GNU/Linux systems, the complete text of the Artistic License\n"
            . "    can be found in `/usr/share/common-licenses/Artistic'",
        'GPL-1+' =>
            "    This program is free software; you can redistribute it and/or modify\n"
            . "    it under the terms of the GNU General Public License as published by\n"
            . "    the Free Software Foundation; either version 1, or (at your option)\n"
            . "    any later version.\n"
            . "    On Debian GNU/Linux systems, the complete text of the GNU General\n"
            . "    Public License can be found in `/usr/share/common-licenses/GPL'",
        'GPL-2' =>
            "    This program is free software; you can redistribute it and/or modify\n"
            . "    it under the terms of the GNU General Public License as published by\n"
            . "    the Free Software Foundation; version 2 dated June, 1991.\n"
            . "    On Debian GNU/Linux systems, the complete text of version 2 of the GNU\n"
            . "    General Public License can be found in `/usr/share/common-licenses/GPL-2'",
        'GPL-2+' =>
            "    This program is free software; you can redistribute it and/or modify\n"
            . "    it under the terms of the GNU General Public License as published by\n"
            . "    the Free Software Foundation; version 2 dated June, 1991, or (at your\n"
            . "    option) any later version.\n"
            . "    On Debian GNU/Linux systems, the complete text of version 2 of the GNU\n"
            . "    General Public License can be found in `/usr/share/common-licenses/GPL-2'",
        'GPL-3' =>
            "    This program is free software; you can redistribute it and/or modify\n"
            . "    it under the terms of the GNU General Public License as published by\n"
            . "    the Free Software Foundation; version 3 dated June, 2007.\n"
            . "    On Debian GNU/Linux systems, the complete text of version 3 of the GNU\n"
            . "    General Public License can be found in `/usr/share/common-licenses/GPL-3'",
        'GPL-3+' =>
            "    This program is free software; you can redistribute it and/or modify\n"
            . "    it under the terms of the GNU General Public License as published by\n"
            . "    the Free Software Foundation; version 3 dated June, 2007, or (at your\n"
            . "    option) any later version\n"
            . "    On Debian GNU/Linux systems, the complete text of version 3 of the GNU\n"
            . "    General Public License can be found in `/usr/share/common-licenses/GPL-3'",
        'unparsable' =>
            "    No known license could be automatically determined for this module.\n"
            . "    If this module conforms to a commonly used license, please report this\n"
            . "    as a bug in dh-make-perl. In any case, please find the proper license\n"
            . "    and fix this file!"
    );

    if ( $meta and $meta->{license} or $copyright ) {
        my $mangle_cprt;

        # Pre-mangle the copyright information for the common similar cases
        $mangle_cprt = $copyright || '';    # avoid warning
        $mangle_cprt =~ s/GENERAL PUBLIC LICENSE/GPL/g;

        # Of course, more licenses (i.e. LGPL, BSD-like, Public
        # Domain, etc.) could be added... Feel free to do so. Keep in
        # mind that many licenses are not meant to be used as
        # templates (i.e. you must add the author name and some
        # information within the licensing text as such).
        if (   $meta and $meta->{license} and $meta->{license} =~ /perl/i
            or $mangle_cprt =~ /terms\s*as\s*Perl\s*itself/is )
        {
            push @res, "License-Alias: Perl";
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

            # Other licenses?

            if ( !keys(%licenses) ) {
                $licenses{unparsable} = 1;
                push( @incomplete,
                    "Licensing information is present, but cannot be parsed"
                );
            }
        }

        push @res, "License: " . join( ' | ', keys %licenses );

    }
    else {
        push @res,        "License: ";
        push @incomplete, 'No licensing information found';
    }

    # debian/* files information - We default to the module being
    # licensed as the superset of the module and Perl itself.
    $licenses{'Artistic'} = $licenses{'GPL-1+'} = 1;
    $year = (localtime)[5] + 1900;
    push( @res, "", "Files: debian/*", "Copyright: $year, $maintainer" );
    push @res, "License: " . join( ' | ', keys %licenses );

    map { $texts{$_} && push( @res, '', "License: $_", $texts{$_} ) }
        keys %licenses;

    $fh->print( join( "\n", @res, '' ) );
    $fh->close;

    _warn_incomplete_copyright( join( "\n", @incomplete ) ) if @incomplete;
}

sub create_readme {
    my $fh = _file_w(shift);
    $fh->print(
        "This is the debian package for the $perlname module.
It was created by $maintainer using dh-make-perl.
"
    );
    $fh->close;
}

sub create_watch {
    my $fh = _file_w(shift);

    my $version_re = 'v?(\d[\d_.-]+)\.(?:tar(?:\.gz|\.bz2)?|tgz|zip)';

    $fh->print(
        "\# format version number, currently 3; this line is compulsory!
version=3
\# URL to the package page followed by a regex to search
$upsurl   .*/$perlname-$version_re\$
"
    );
    $fh->close;
}

sub get_maintainer {
    my ( $user, $pwnam, $email, $name, $mailh );
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
    $email = shift @_ || ( $ENV{DEBEMAIL} || $ENV{EMAIL} );
    unless ($email) {
        chomp( $mailh = `cat /etc/mailname` );
        $email = $user . '@' . $mailh;
    }

    $email =~ s/^(.*)\s+<(.*)>$/$2/;

    return "$name <$email>";
}

sub load_overrides {
    eval {
        do "$opt_datadir/overrides" if -f "$opt_datadir/overrides";
        do "$opt_homedir/overrides" if -f "$opt_homedir/overrides";
    };
    if ($@) {
        die "Error when processing the overrides files: $@";
    }
}

sub apply_overrides {
    my ( $data, $val, $subkey );

    ( $data, $subkey ) = get_override_data();
    return unless defined $data;
    $pkgname = $val
        if (
        defined( $val = get_override_val( $data, $subkey, 'pkgname' ) ) );
    $srcname = $val
        if (
        defined( $val = get_override_val( $data, $subkey, 'srcname' ) ) );
    $section = $val
        if (
        defined( $val = get_override_val( $data, $subkey, 'section' ) ) );
    $priority = $val
        if (
        defined( $val = get_override_val( $data, $subkey, 'priority' ) ) );
    @depends = Debian::Dependencies->new($val)
        if (
        defined( $val = get_override_val( $data, $subkey, 'depends' ) ) );
    @bdepends = Debian::Dependencies->new($val)
        if (
        defined( $val = get_override_val( $data, $subkey, 'bdepends' ) ) );
    @bdependsi = Debian::Dependencies->new($val)
        if (
        defined( $val = get_override_val( $data, $subkey, 'bdependsi' ) ) );
    $desc = $val
        if ( defined( $val = get_override_val( $data, $subkey, 'desc' ) ) );
    $longdesc = $val
        if (
        defined( $val = get_override_val( $data, $subkey, 'longdesc' ) ) );
    $pkgversion = $val
        if (
        defined( $val = get_override_val( $data, $subkey, 'version' ) ) );
    $arch = $val
        if ( defined( $val = get_override_val( $data, $subkey, 'arch' ) ) );
    $changelog = $val
        if (
        defined( $val = get_override_val( $data, $subkey, 'changelog' ) ) );
    @docs = split( /\s+/, $val )
        if ( defined( $val = get_override_val( $data, $subkey, 'docs' ) ) );

    $extrasfields = $val
        if (
        defined( $val = get_override_val( $data, $subkey, 'sfields' ) ) );
    $extrapfields = $val
        if (
        defined( $val = get_override_val( $data, $subkey, 'pfields' ) ) );
    $maintainer = $val
        if (
        defined( $val = get_override_val( $data, $subkey, 'maintainer' ) ) );

    # fix longdesc if needed
    $longdesc =~ s/^\s*/ /mg;
}

sub apply_final_overrides {
    my ( $data, $val, $subkey );

    ( $data, $subkey ) = get_override_data();
    return unless defined $data;
    get_override_val( $data, $subkey, 'finish' );
}

sub get_override_data {
    my ( $data, $checkver, $subkey );
    $data = $overrides{$perlname};

    return unless defined $data;
    die "Value of '$perlname' in overrides not a hashref\n"
        unless ref($data) eq 'HASH';
    if ( defined( $checkver = $data->{checkver} ) ) {
        die "checkver not a function\n" unless ( ref($checkver) eq 'CODE' );
        $subkey = &$checkver($maindir);
    }
    else {
        $subkey = $pkgversion;
    }
    return ( $data, $subkey );
}

sub get_override_val {
    my ( $data, $subkey, $key, $val );
    ( $data, $subkey, $key ) = @_;
    $val
        = defined( $data->{ $subkey . $key } )
        ? $data->{ $subkey . $key }
        : $data->{$key};
    return &$val() if ( defined($val) && ref($val) eq 'CODE' );
    return $val;
}

sub _warn_incomplete_copyright {
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
    my ( $file, $fh );
    $file = shift;
    $fh = IO::File->new( $file, 'r' ) or die "Cannot open $file: $!\n";
    return $fh;
}

sub _file_w {
    my ( $file, $fh );
    $file = shift;
    $fh = IO::File->new( $file, 'w' ) or die "Cannot open $file: $!\n";
    return $fh;
}

sub _file_rw {
    my ( $file, $fh );
    $file = shift;
    $fh = IO::File->new( $file, 'r+' ) or die "Cannot open $file: $!\n";
    return $fh;
}


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

=item Copyright (C) 2000,2001 Paolo Molaro <lupus@debian.org>

=item Copyright (C) 2002,2003,2008 Ivan Kohler <ivan-debian@420.am>

=item Copyright (C) 2003,2004 Marc 'HE' Brockschmidt <he@debian.org>

=item Copyright (C) 2005-2007 Gunnar Wolf <gwolf@debian.org>

=item Copyright (C) 2006 Frank Lichtenheld <djpig@debian.org>

=item Copyright (C) 2007-2008 Gregor Herrmann <gregoa@debian.org>

=item Copyright (C) 2007-2008 Damyan Ivanov <dmn@debian.org>

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