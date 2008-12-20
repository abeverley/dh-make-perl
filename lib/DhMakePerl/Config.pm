package DhMakePerl::Config;

use strict;
use warnings;

use base 'Class::Accessor';

use constant options => (
    'arch=s',         'basepkgs=s',
    'bdepends=s',     'bdependsi=s',
    'build!',         'closes=i',
    'core-ok',        'cpan-mirror=s',
    'cpan=s',         'cpanplus=s',
    'data-dir=s',     'dbflags=s',
    'depends=s',      'desc=s',
    'dh=i',           'dist=s',
    'email|e=s',      'exclude|i:s{,}',
    'help',           'home-dir=s',
    'install!',       'nometa',
    'notest',         'packagename|p=s',
    'pkg-perl!',      'requiredeps',
    'sources-list=s', 'verbose!',
    'version=s',
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
);

use Getopt::Long;

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

sub new {
    my $class = shift;
    my $values = shift || {};

    my $self = $class->SUPER::new( { %{ $class->DEFAULTS }, @_ } );
}

sub parse_command_line_options {
    my $self = shift;

    # first get 'regular' options. commands are parsed in another
    # run below.
    Getopt::Long::Configure('pass_through');
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

1;
