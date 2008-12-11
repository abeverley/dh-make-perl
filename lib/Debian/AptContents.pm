package Debian::AptContents;

use base qw(Class::Accessor);
__PACKAGE__->mk_accessors(
    qw(
        cache homedir cache_file contents_dir contents_files verbose
        source sources_file dist
    )
);

use Storable;
use File::Spec::Functions qw( catfile catdir splitpath );

sub new
{
    my $class = shift;
    $class = ref($class) if ref($class);
    my $self = $class->SUPER::new(@_);

    # required options
    $self->homedir
        or die "No homedir given";

    # some defaults
    $self->contents_dir( '/var/cache/apt/apt-file' )
        unless $self->contents_dir;
    $self->sources_file('/etc/apt/sources.list')
        unless defined( $self->sources_file );
    $self->dist('{sid,unstable}') unless $self->dist;
    $self->contents_files( $self->get_contents_file_list )
        unless $self->contents_files;
    $self->cache_file( catfile( $self->homedir, 'Contents.cache' ) )
        unless $self->cache_file;
    $self->verbose(1) unless defined( $self->verbose );

    $self->read_cache();

    return $self;
}

sub warning
{
    my( $self, $level, $msg ) = @_;

    warn "$msg\n" if $self->verbose >= $level;
}

sub repo_source_to_contents_path {
    my ( $self, $source ) = @_;

    my ( $schema, $proto, $host, $port, $dir, $dist, $components ) = $source =~ m{
        ^
        (\S+)           # deb or deb-src
        \s+
        ([^:\s]+)       # ftp/http/file/cdrom
        ://
        (/?             # file:///
            [^:/\s]+    # host name or path
        )
        (?:
            :(\d+)      # optional port number
        )?
        (?:
            /
            (\S*)       # path on server (or local)
        )?
        \s+
        (\S+)           # distribution
        (?:
            \s+
            (.+)            # components
        )?
    }x;

    unless ( defined $schema ) {
        $self->warning( 1, "'$_' has unknown format" );
        next;
    }

    return undef unless $schema eq 'deb';

    $dir ||= '';    # deb http://there sid main

        s{/$}{} for( $host, $dir, $dist );  # remove trailing /
        s{/}{_}g for( $host, $dir, $dist ); # replace remaining /

    return join( "_", $host, $dir||(), "dists", $dist );
}

sub get_contents_filename_filters
{
    my $self = shift;

    my $sources = IO::File->new( $self->sources_file, 'r' )
        or die "Unable to open '" . $self->sources_file . "': $!\n";

    my @re;

    while( <$sources> ) {
        chomp;
        s/#.*//;
        s/^\s+//;
        s/\s+$//;
        next unless $_;

        my $path = $self->repo_source_to_contents_path($_);
        push @re, qr{\Q$path\E} if $path;
    }

    return @re;
}

sub get_contents_file_list {
    my $self = shift;

    my $archspec = `dpkg --print-architecture`;
    chomp($archspec);

    my @re = $self->get_contents_filename_filters;

    my $pattern = catfile(
        $self->contents_dir,
        "*_". $self->dist . "_Contents{,-$archspec}{,.gz}"
    );

    my @list = glob $pattern;

    my @filtered;
    for my $path (@list) {
        my( $vol, $dirs, $file ) = splitpath( $path );

        for (@re) {
            push @filtered, $path if $file =~ $_;
        }
    }
    return [ sort @filtered ];
}

sub read_cache() {
    my $self = shift;

    my $cache;

    if ( -r $self->cache_file ) {
        $cache = eval { Storable::retrieve(  $self->cache_file ) };
        undef($cache) unless ref($cache) and ref($cache) eq 'HASH';
    }

    # see if the cache is stale
    if ( $cache and $cache->{stamp} and $cache->{contents_files} ) {
        undef($cache)
            unless join( '><', @{ $self->contents_files } ) eq
                join( '><', @{ $cache->{contents_files} } );

        # file lists are the same?
        # see if any of the files has changed since we
        # last read it
        if ( $cache ) {
            for ( @{ $self->contents_files } ) {
                if ( ( stat($_) )[9] > $cache->{stamp} ) {
                    undef($cache);
                    last;
                }
            }
        }
    }
    else {
        undef($cache);
    }

    unless ($cache) {
        $self->source('parsed files');
        $cache->{stamp}          = time;
        $cache->{contents_files} = [];
        $cache->{apt_contents}   = {};
        for ( @{ $self->contents_files } ) {
            push @{ $cache->{contents_files} }, $_;
            my $f = /\.gz$/
                ? IO::Uncompress::Gunzip->new($_)
                : IO::File->new( $_, 'r' );

            unless ($f) {
                warn "Error reading '$_': $!\n";
                next;
            }

            $self->warning( 1, "Parsing $_ ..." );
            my $capturing = 0;
            my $line;
            while ( defined( $line = $f->getline ) ) {
                if ($capturing) {
                    my ( $file, $packages ) = split( /\s+/, $line );
                    next unless $file =~ s{
                        ^usr/
                        (?:share|lib)/
                        (?:perl\d+/             # perl5/
                        | perl/(?:\d[\d.]+)/   # or perl.5.10/
                        )
                    }{}x;
                    $cache->{apt_contents}{$file} = $packages;

                    # $packages is a comma-separated list of
                    # section/package items. We'll parse it when a file
                    # matches. Otherwise we'd parse thousands of entries,
                    # while checking only a couple
                }
                else {
                    $capturing = 1 if $line =~ /^FILE\s+LOCATION/;
                }
            }
        }

        if ( %{ $cache->{apt_contents} } ) {
            $self->cache($cache);
            $self->store_cache;
        }
    }
    else {
        $self->source('cache');
        $self->warning( 1,
            "Using cached Contents from "
            . localtime( $cache->{stamp} )
        );

        $self->cache($cache);
    }
}

sub store_cache {
    my $self = shift;

    my ( $vol, $dir, $file ) = splitpath( $self->cache_file );

    $dir = catdir( $vol, $dir );
    unless ( -d $dir ) {
        mkdir $dir
            or die "Error creating directory '$dir': $!\n"
    }

    Storable::store( $self->cache, $self->cache_file . '-new' );
    rename( $self->cache_file . '-new', $self->cache_file );
}

sub find_file_packages {
    my( $self, $file ) = @_;

    my $packages = $self->cache->{apt_contents}{$file};

    return () unless $packages;

    my @packages = split( /,/, $packages );     # Contents contains a
                                                # comma-delimitted list
                                                # of packages

    s{[^/]+/}{} for @packages;  # remove section

    return @packages;
}

sub find_perl_module_package {
    my ( $self, $module ) = @_;

    my $module_file = $module;
    $module_file =~ s|::|/|g;

    my @matches = $self->find_file_packages("$module_file.pm");

    # rank non -perl packages lower
    @matches = sort {
        if    ( $a !~ /-perl: / ) { return 1; }
        elsif ( $b !~ /-perl: / ) { return -1; }
        else                      { return $a cmp $b; }    # or 0?
    } @matches;

    return $matches[0];
}

1;
