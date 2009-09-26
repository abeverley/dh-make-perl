package Debian::Version;

=head1 NAME

Debian::Version - working with Debian package versions

=head1 DESCRIPTION

One day this package may be a class for encapsulating Debian versions with all
of their epochs, versions and revisions. For now, though, it only provides a
single comparison function.

=cut

use base 'Exporter';

our @EXPORT_OK = qw( deb_ver_cmp );

use AptPkg::Config;

=head1 FUNCTIONS

=over

=item deb_ver_cmp( $ver1, $ver2 )

Compares the Debian versions and returns a negative value, zero or a
positive value if the first version is smaller, equal or bigger than the
second.

This function is a short-named wrapper around C<<
$AptPkg::Config::_config->system->versioning->compare >>.  The rules for
comparing Debian versions are defined in the L<Debian Policy Manual>.

=cut

sub deb_ver_cmp {
    my ( $ver1, $ver2 ) = @_;

    return $AptPkg::Config::_config->system->versioning->compare( $ver1,
        $ver2 );
}

=back

=head1 SEE ALSO

=over

=item AptPkg::Config

=item Dpkg::Version

=back

=head1 COPYRIGHT & LICENSE

=over 4

=item Copyright (C) 2009 Damyan Ivanov <dmn@debian.org>

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

1;
