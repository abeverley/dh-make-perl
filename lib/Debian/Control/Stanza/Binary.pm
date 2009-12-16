=head1 NAME

Debian::Control::Stanza::Binary - binary stanza of Debian source package control file

=head1 SYNOPSIS

    my $src = Debian::Control::Stanza::Binary->new(\%data);
    print $src;                         # auto-stringification
    print $src->Depends;                # Debian::Dependencies object

=head1 DESCRIPTION

Debian::Control::Stanza::Binary can be used for representation and manipulation
of C<Package:> stanza of Debian source package control files in an
object-oriented way. Converts itself to a textual representation in string
context.

=head1 FIELDS

The supported fields for binary stanzas are listed below. For more information
about each field's meaning, consult the section named C<Source package control
files -- debian/control> of the Debian Policy Manual at
L<http://www.debian.org/doc/debian-policy/>

Note that real control fields may contain dashes in their names. These are
replaced with underscores.

=over

=item Package

=item Architecture

=item Section

=item Priority

=item Essential

=item Depends

=item Recommends

=item Suggests

=item Enhances

=item Replaces

=item Pre_Depends

=item Conflicts

=item Provides

=item Description

=back

C<Depends>, C<Conflicts>, C<Recommends>, C<Suggests>, C<Enhances>, C<Replaces>, 
and C<Pre_Depends> fields are converted to objects of L<Debian::Dependencies> 
class upon construction.

=cut

package Debian::Control::Stanza::Binary;

use strict;

use base 'Debian::Control::Stanza';

use constant fields => qw(
    Package Architecture Section Priority Essential Depends Recommends Suggests
    Enhances Replaces Pre_Depends Conflicts Provides Description
);

=head1 CONSTRUCTOR

=over

=item new

=item new( { field => value, ... } )

Creates a new L<Debian::Control::Stanza::Binary> object and optionally
initializes it with the supplied data.

=back

=head1 SEE ALSO

Debian::Control::Stanza::Source inherits most of its functionality from
L<Debian::Control::Stanza>

=head1 COPYRIGHT & LICENSE

Copyright (C) 2009 Damyan Ivanov L<dmn@debian.org>

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License version 2 as published by the Free
Software Foundation.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE.

=cut

1;
