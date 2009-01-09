package DhMakePerl::Config;

use strict;
use warnings;

use base 'Class::Accessor';

use constant options => (
    'arch=s',          'basepkgs=s',
    'bdepends=s',      'bdependsi=s',
    'build!',          'closes=i',
    'config-file=s',   'core-ok',
    'cpan-mirror=s',   'cpan=s',
    'cpanplus=s',      'data-dir=s',
    'dbflags=s',       'depends=s',
    'desc=s',          'dh=i',
    'dist=s',          'email|e=s',
    'exclude|i:s{,}',  'help',
    'home-dir=s',      'install!',
    'nometa',          'notest',
    'packagename|p=s', 'pkg-perl!',
    'requiredeps',     'sources-list=s',
    'verbose!',        'version=s',
);

use constant commands => ( 'refresh|R', 'refresh-cache' );

__PACKAGE__->mk_accessors(
    do {
        my @opts = ( __PACKAGE__->options, __PACKAGE__->commands );
        for (@opts) {
            s/[=:!|].*//;
            s/-/_/g;
        }
        @opts;
    },
    'command',
    '_explicitly_set',
);

use File::Basename qw(basename);
use File::Spec::Functions qw(catfile);
use Getopt::Long;
use Tie::IxHash ();
use YAML        ();

use constant DEFAULTS => {
    data_dir     => '/usr/share/dh-make-perl',
    dbflags      => ( $> == 0 ? "" : "-rfakeroot" ),
    dh           => 7,
    dist         => '{sid,unstable}',
    email        => '',
    exclude      => '(?:\/|^)(?:CVS|\.svn)\/',
    home_dir     => "$ENV{HOME}/.dh-make-perl",
    sources_list => '/etc/apt/sources.list',
    verbose      => 1,
};

use constant cpan2deb_DEFAULTS => {
    verbose => 0,
    build   => 1,

    #recursive   => 1,
};

sub new {
    my $class = shift;
    my $values = shift || {};

    my $self = $class->SUPER::new(
        {   %{ $class->DEFAULTS },
            (   ( basename($0) eq 'cpan2deb' )
                ? %{ $class->cpan2deb_DEFAULTS }
                : ()
            ),
            @_,
        },
    );

    $self->_explicitly_set( {} );

    return $self;
}

sub parse_command_line_options {
    my $self = shift;

    # first get 'regular' options. commands are parsed in another
    # run below.
    Getopt::Long::Configure( qw( pass_through no_auto_abbrev no_ignore_case ) );
    my %opts;
    GetOptions( \%opts, $self->options, )
        or die "Error parsing command-line options\n";

    # Make CPAN happy, make the user happy: Be more tolerant!
    # Accept names to be specified with double-colon, dash or slash
    $opts{cpan} =~ s![/-]!::!g if $opts{cpan};
    $opts{exclude} ||= '^$';

    while ( my ( $k, $v ) = each %opts ) {
        my $field = $k;
        $field =~ s/-/_/g;
        $self->$field( $opts{$k} );
        $self->_explicitly_set->{$k} = 1;
    }

    # see what are we told to do
    %opts = ();
    Getopt::Long::Configure('no_pass_through');
    GetOptions( \%opts, $self->commands )
        or die "Error parsing command-line options\n";

    # by default, create source package
    %opts = ( command => 'make' ) unless %opts;

    if ( scalar( keys %opts ) > 1 ) {
        die "Only one of " .
            map( "--$_", $self->commands ) . " can be specified\n";
    }

    $self->command( ( keys %opts )[0] );
}

sub parse_config_file {
    my $self = shift;

    my $fn = $self->config_file
        || catfile( $self->home_dir, 'dh-make-perl.conf' );

    if ( -e $fn ) {
        local $@;
        my $yaml = eval { YAML::Load($fn) };

        die "Error parsing $fn: $@" if $@;

        die
            "Error parsing $fn: config-file is not allowed in the configuration file"
            if $yaml->{'config-file'};

        for ( $self->options ) {
            ( my $key = $_ ) =~ s/_/-/g;

            next unless exists $yaml->{$key};
            next
                if $self->_explicitly_set
                    ->{$key};    # cmd-line opts take precedence

            $self->$_( delete $yaml->{$key} );
        }

        die "Error parsing $fn: the following keys are not known:\n"
            . join( "\n", map( "  - $_", keys %$yaml ) )
            if %$yaml;
    }
}

sub dump_config {
    my $self = shift;

    my %hash;
    tie %hash, 'Tie::IxHash';

    for my $opt ( $self->options ) {
        $opt =~ s/[=!|].*//;
        ( my $field = $opt ) =~ s/-/_/g;
        $hash{$opt} = '' . $self->$field    # stringified
            if defined $self->$field;
    }

    return YAML::Dump( \%hash );
}

1;
