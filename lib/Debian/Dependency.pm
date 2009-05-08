package Debian::Dependency;

use strict;
use warnings;

=head1 NAME

Debian::Dependency -- dependency relationship between Debian packages

=head1 SYNOPSIS

                                    # simple dependency
   my $d = Debian::Dependency->new( 'perl' );
                                    # also parses a single argument
   my $d = Debian::Dependency->new('perl (>= 5.10)');
                                    # dependency with a version
   my $d = Debian::Dependency->new( 'perl', '5.10' );
                                    # dependency with version and relation
   my $d = Debian::Dependency->new( 'perl', '>=', '5.10' );

   print $d->pkg;  # 'perl'
   print $d->ver;  # '5.10

                                    # for people who like to type much
   my $d = Debian::Dependency->new( { pkg => 'perl', ver => '5.10' } );

   # stringification
   print "$d"      # 'perl (>= 5.10)'

   # 'adding'
   $deps = $dep1 + $dep2;
   $deps = $dep1 + 'foo (>= 1.23)'

=cut

use base qw(Class::Accessor);
__PACKAGE__->mk_accessors(qw( pkg ver rel ));

use Carp;

use overload '""' => \&_stringify,
             '+'  => \&_add;

=head2 CLASS_METHODS

=over 4

=item new()

=item new( { pkg => 'package', rel => '>=', ver => '1.9' } )

Construct new instance. If a reference is passed as an argument, it must be a
hashref and is passed to L<Class::Accessor>.

If a single argument is given, the construction is passed to the C<parse>
constructor.

Two arguments are interpreted as package name and version. The relation is
assumed to be '>='.

Three arguments are interpreted as package name, relation and version.

=cut

sub new {
    my $class = shift;
    $class = ref($class) if ref($class);

    return $class->SUPER::new(@_) if ref( $_[0] );

    return $class->parse( $_[0] )
        if @_ == 1;

    return $class->SUPER::new( { pkg => $_[0], rel => '>=', ver => $_[1] } )
        if @_ == 2;

    return $class->SUPER::new( { pkg => $_[0], rel => $_[1], ver => $_[2] } )
        if @_ == 3;

    die "Unsupported number of arguments";
}

sub _stringify {
    my $self = shift;

    return (
          $self->ver
        ? $self->pkg . ' (' . $self->rel . ' ' . $self->ver . ')'
        : $self->pkg
    );
}

sub _add {
    my $left = shift;
    my $right = shift;
    my $mode = shift;

    confess "cannot += Dependency. put Dependencies instance on the left instead" unless defined($mode);

    return bless( [ $left ], 'Debian::Dependencies' ) + $right;
}

=item parse()

Takes a single string argument and parses it.

Examples:

=over

=item perl

=item perl (>= 5.8)

=item libversion-perl (<< 3.4)

=back

=cut

sub parse {
    my ( $class, $str ) = @_;

    if ($str =~ m{
            ^               # start from the beginning
            ([^\(\s]+)      # package name - no paren, no space
            \s*             # oprional space
            (?:             # version is optional
                \(          # opening paren
                    (       # various relations 
                        <<
                      | <=
                      | =
                      | >=
                      | >>
                    )
                    \s*     # optional space
                    (.+)    # version
                \)          # closing paren
            )?
            $}x    # done
        )
    {
        return $class->new(
            {   pkg => $1,
                (     ( defined($2) and defined($3) )
                    ? ( rel => $2, ver => $3 )
                    : ()
                )
            }
        );
    }
    else {
        die "Unable to parse '$str'";
    }
}

1;

=back

=head2 FIELDS

=over

=item pkg

Contains the name of the package that is depended upon

=item rel

Contains the relation of the dependency. May be any of '<<', '<=', '=', '>='
or '>>'. Default is '>='.

=item ver

Contains the version of the package the dependency is about.

=back

C<rel> and C<ver> are either both present or both missing.

Examples

    print $dep->pkg;
    $dep->ver('3.4');

=head1 SEE ALSO

L<Debian::Dependencies>

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
