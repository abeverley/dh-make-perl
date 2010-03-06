package DhMakePerl;

use warnings;
use strict;
use 5.010;    # we use smart matching

use base 'Class::Accessor';

__PACKAGE__->mk_accessors(
    qw(
        cfg apt_contents main_dir debian_dir meta bdepends bdependsi depends
        priority section maintainer arch start_dir overrides
        perlname version pkgversion pkgname srcname
        desc longdesc copyright author
        extrasfields  extrapfields
        mod_cpan_version
        docs examples rules
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

use Debian::AptContents ();
use DhMakePerl::Config;
use Module::CoreList ();
use version          ();

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

sub is_core_module {
    my ( $self, $module, $ver ) = @_;

    my $v = Module::CoreList->first_release($module, $ver);   # 5.009002

    return unless defined $v;

    $v = version->new($v);                              # v5.9.2
    ( $v = $v->normal ) =~ s/^v//;                      # "5.9.2"

    return $v;
}

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
