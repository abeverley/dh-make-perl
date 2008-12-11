use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'App::DhMakePerl',
    license             => 'gpl2',
    build_requires => {
        'Test::More' => 0,
    },
    add_to_cleanup      => [ 'App-DhMakePerl-*' ],
    create_makefile_pl => 'traditional',
    script_files    => [ 'dh-make-perl' ],
    install_path    => {
        share   => '/usr/share/dh-make-perl',
    },
    share_files => { map( ( $_ => $_ ), glob 'share/*' ) },
);

$builder->add_build_element('share');
$builder->create_build_script();
