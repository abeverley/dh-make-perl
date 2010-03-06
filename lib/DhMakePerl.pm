package DhMakePerl;

use warnings;
use strict;
use 5.010;    # we use smart matching

use base 'Class::Accessor';

__PACKAGE__->mk_accessors( qw( cfg apt_contents ) );

=head1 NAME

DhMakePerl - create Debian source package from CPAN dist

=head1 VERSION

Version 0.65

=cut

our $VERSION = '0.65';

=head1 SYNOPSIS

    use DhMakePerl;

    DhMakePerl->run;

=head1 CLASS METHODS

=over

=cut

use Debian::AptContents ();
use DhMakePerl::Config;
use Module::CoreList ();
use version          ();

=item run( I<%init> )

Runs DhMakePerl.

Unless the %init contains an I<cfg> member, constructs and instance of
L<DhMakePerl::Config> and assigns it to I<$init{cfg}>.

Then determines the dh-make-perl command requested (via cfg->command), loads
the appropriate I<DhMakePerl::Command::$command> class, constructs an instance
of it and calls its I<execute> method.

=cut

sub run {
    my ( $class, %c ) = @_;

    unless ( $c{cfg} ) {
        my $cfg = DhMakePerl::Config->new;
        $cfg->parse_command_line_options;
        $cfg->parse_config_file;
        $c{cfg} = $cfg;
    }

    my $cmd_mod = $c{cfg}->command;
    $cmd_mod =~ s/-/_/g;
    require "DhMakePerl/Command/$cmd_mod.pm";

    $cmd_mod =~ s{/}{::}g;
    $cmd_mod = "DhMakePerl::Command::$cmd_mod";

    my $self = $cmd_mod->new( \%c );

    return $self->execute;
}

=item is_core_module I<module>, I<version>

Returns the version of the C<perl> package containing the given I<module> (at
least version I<version>).

Returns C<undef> if I<module> is not a core module.

=cut

sub is_core_module {
    my ( $self, $module, $ver ) = @_;

    my $v = Module::CoreList->first_release($module, $ver);   # 5.009002

    return unless defined $v;

    $v = version->new($v);                              # v5.9.2
    ( $v = $v->normal ) =~ s/^v//;                      # "5.9.2"

    return $v;
}

=item get_apt_contents

Returns (possibly cached) instance of L<Debian::AptContents>.

=cut

sub get_apt_contents {
    my $self = shift;

    return $self->apt_contents
        if $self->apt_contents;

    my $apt_c = Debian::AptContents->new(
        {   homedir      => $self->cfg->home_dir,
            dist         => $self->cfg->dist,
            sources      => $self->cfg->sources_list,
            verbose      => $self->cfg->verbose,
            contents_dir => $self->cfg->apt_contents_dir,
        }
    );

    undef $apt_c unless $apt_c->cache;

    return $self->apt_contents($apt_c);
}

=back

=head1 COPYRIGHT & LICENSE

=over

=item Copyright (C) 2009, 2010 Damyan Ivanov <dmn@debian.org>

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
