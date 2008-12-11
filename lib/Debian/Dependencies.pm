package Debian::Dependencies;

use strict;
use warnings;

use Debian::Dependency;

use overload '""'   => \&stringify;

=head1 NAME

Debian::Dependencies -- a list of Debian::Dependency objects

=head1 SYNOPSIS

    my $dl = Debian::Dependencies->new('perl, libfoo-perl (>= 3.4)');
    print $dl->[1]->ver;      # 3.4
    print $dl->[1];           # libfoo-perl (>= 3.4)
    print $dl;                # perl, libfoo-perl (>= 3.4)

=head1 DESCRIPTION

Debian::Dependencies a list of Debian::Dependency objects, with automatic
construction and stringification.

Objects of this class are blessed array references. You can safely treat them
as arrayrefs, as long as the elements you put in them are instances of the
Debian::Dependency class.

When used in string context, Debian::Dependencies converts itself into a
comma-delimitted list of dependencies, suitable for dependency fields of
F<debian/control> files.

=head2 CLASS METHODS

=over 4

=item new(dependency-string)

Constructs a new Debian::Dependencies object. Accepts one scalar argument,
which is parsed and turned into an arrayref of Debian::Dependency objects.

=cut

sub new {
    my ( $class, $val ) = @_;

    my $self = bless [], $class;

    if ( defined($val) ) {
        @{$self} = map(
            Debian::Dependency->new($_),
            split( /\s*,\s*/, $val ) );
    }

    return $self;
}

=back

=head2 OBJECT METHODS

=over 4

XXX TO BE FILLED

=back

=cut

sub stringify {
    my $self = shift;

    return join( ', ', @$self );
}

1;

=head1 SEE ALSO

L<Debian::Dependency>

=head1 AUTHOR

=over 4

=item Damyan Ivanov <dmn@debian.org>

=back

=head1 COPYRIGHT & LICENSE

=over 4

=item Copyright (C) 2008 Damyan Ivanov <dmn@debian.org>

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
