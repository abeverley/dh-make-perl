use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'DhMakePerl',
    license             => 'gpl',
    requires            => {
        perl    => '5.010',

        'AptPkg::Cache'             => 0,
        'AptPkg::Config'            => 0,
        'Carp'                      => 0,
        'CPAN'                      => 0,
        'Cwd'                       => 0,
        'Dpkg::Source::Package'     => 0,
        'Email::Date::Format'       => 0,
        'File::Basename'            => 0,
        'File::Copy'                => 0,
        'File::Find::Rule'          => 0,
        'File::Spec'                => 0,
        'File::Spec::Functions'     => 0,
        'FindBin'                   => 0,
        'Getopt::Long'              => 0,
        'IO::File'                  => 0,
        'IO::Uncompress::Gunzip'    => 0,
        'List::MoreUtils'           => 0,
        'Module::CoreList'          => 0,
        'Module::Depends'           => 0,
        'Module::Depends::Intrusive'=> 0,
        'Parse::DebianChangelog'    => 0,
        'Parse::DebControl'         => 0,
        'Storable'                  => 0,
        'Text::Diff'                => 0,
        'Text::Wrap'                => 0,
        'Tie::File'                 => 0,
        'Tie::IxHash'               => 0,
        'User::pwent'               => 0,
        'version'                   => 0,
        'WWW::Mechanize'            => 0,
        'YAML'                      => 0,
    },
    build_requires      => {
        'Test::Deep'        => 0,
        'Test::Exception'   => 0,
        'Test::Differences' => 0,
        'Test::More'        => 0,
    },
    add_to_cleanup      => [ 'DhMakePerl-*' ],
    create_makefile_pl  => 'passthrough',
    script_files        => [ 'dh-make-perl' ],
    install_path        => {
        share   => '/usr/share/dh-make-perl',
    },
    share_files         => { map( ( $_ => $_ ), glob 'share/*' ) },
);

$builder->add_build_element('share');
$builder->create_build_script();
