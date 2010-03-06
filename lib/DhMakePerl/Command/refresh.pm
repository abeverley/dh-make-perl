package DhMakePerl::Command::refresh;

=head1 NAME

DhMakePerl::Command::refresh - dh-make-perl refresh implementation

=head1 DESCRIPTION

This module implements the I<refresh> command of L<dh-make-perl(1)>.

=cut

use strict; use warnings;

use base 'DhMakePerl';
use Debian::Rules ();
use File::Spec::Functions qw(catfile);

=head1 METHODS

=over

=item execute

Provides I<refresh> command implementation.

=cut

sub execute {
    my $self = shift;

    $self->main_dir( $ARGV[0] || '.' );
    print "Engaging refresh mode in " . $self->main_dir . "\n"
        if $self->cfg->verbose;

    $self->rules( Debian::Rules->new( $self->debian_file('rules') ) );
    $self->maintainer( $self->get_maintainer( $self->cfg->email ) );
    $self->process_meta;
    $self->extract_basic();    # also detects arch-dep package

    $self->extract_docs     if 'docs'     ~~ $self->cfg->only;
    $self->extract_examples if 'examples' ~~ $self->cfg->only;
    print "Found docs: @{ $self->docs }\n"
        if @{ $self->docs } and $self->cfg->verbose;
    print "Found examples: @{ $self->examples }\n"
        if @{ $self->examples } and $self->cfg->verbose;

    if ( 'rules' ~~ $self->cfg->only ) {
        $self->backup_file( $self->debian_file('rules') );
        $self->create_rules( $self->debian_file('rules') );
        if ( !-f $self->debian_file('compat') or $self->cfg->dh == 7 ) {
            $self->create_compat( $self->debian_file('compat') );
        }
    }

    if ( 'examples' ~~ $self->cfg->only ) {
        $self->update_file_list( examples => $self->examples );
    }

    if ( 'docs' ~~ $self->cfg->only ) {
        $self->update_file_list( docs => $self->docs );
    }

    if ( 'copyright' ~~ $self->cfg->only ) {
        $self->backup_file( $self->debian_file('copyright') );
        $self->create_copyright( $self->debian_file('copyright') );
    }

    if ( 'control' ~~ $self->cfg->only ) {
        my $control = Debian::Control::FromCPAN->new;
        $control->read( $self->debian_file('control') );
        if ( -e catfile( $self->debian_file('patches'), 'series' )
            and $self->cfg->source_format ne '3.0 (quilt)' )
        {
            $self->add_quilt($control);
        }
        else {
            $self->drop_quilt($control);
        }

        $self->write_source_format(
            catfile( $self->debian_dir, 'source', 'format' ) );

        if ( my $apt_contents = $self->get_apt_contents ) {
            $control->dependencies_from_cpan_meta( $self->meta,
                $self->get_apt_contents, $self->cfg->verbose );
        }
        else {
            warn "No APT contents can be loaded.\n";
            warn
                "Please install 'apt-file' package and run 'apt-file update'\n";
            warn "as root.\n";
            warn "Dependencies not updated.\n";
        }

        $self->discover_utility_deps($control);
        $control->prune_perl_deps();

        $self->backup_file( $self->debian_file('control') );
        $control->write( $self->debian_file('control') );
    }

    print "--- Done\n" if $self->cfg->verbose;
    return 0;
}

=back

=cut

1;

=head1 COPYRIGHT & LICENSE

=over

=item Copyright (C) 2008, 2009, 2010 Damyan Ivanov <dmn@debian.org>

=item Copyright (C) 2010 gregor herrmann <gregoa@debian.org>

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

