package Debian::Dependency;

use strict;
use warnings;

use AptPkg::Config;

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
             '+'  => \&_add,
             '<=>'  => \&_compare;

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

our %rel_order = (
    '<<'    => -2,
    '<='    => -1,
    '='     => 0,
    '>='    => +1,
    '>>'    => +2,
);

sub _compare {
    my( $left, $right ) = @_;

    my $res = $left->pkg cmp $right->pkg;

    return $res if $res != 0;

    return -1 if not defined( $left->ver ) and defined( $right->ver );
    return +1 if defined( $left->ver ) and not defined( $right->ver );

    return 0 unless $left->ver; # both have no version

    $res = $AptPkg::Config::_config->system->versioning->compare(
        $left->ver, $right->ver,
    );

    return $res if $res != 0;

    # same versions, compare relations
    return $rel_order{ $left->rel } <=> $rel_order{ $right->rel };
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

=head1 METHODS

=over

=item satisfies($dep)

Returns true if I<$dep> states a dependency that is already covered by this
instance. In other words, if this method returns true, any package satisfying
the dependency of this instance will also satisfy I<$dep> ($dep is redundant in
dependency lsits where this instance is already present).

I<$dep> can be either an instance of the L<Debian::Dependency> class, or a
plain string.

    my $dep  = Debian::Dependency->new('foo (>= 2)');
    print $dep->satisfies('foo') ? 'yes' : 'no';             # no
    print $dep->satisfies('bar') ? 'yes' : 'no';             # no
    print $dep->satisfies('foo (>= 2.1)') ? 'yes' : 'no';    # yes

=cut

sub satisfies {
    my( $self, $dep ) = @_;

    $dep = Debian::Dependency->new($dep)
        unless ref($dep);

    # different package?
    return 0 unless $self->pkg eq $dep->pkg;

    # $dep has no relation?
    return 1 unless $dep->rel;

    # $dep has relation, but we don't?
    return 0 if not $self->rel;

    # from this point below both $dep and we have relation (and version)
    my $cmpver = $AptPkg::Config::_config->system->versioning->compare(
        $self->ver, $dep->ver,
    );

    if( $self->rel eq '>>' ) {
        # >> 4 satisfies also >> 3
        return 1 if $dep->rel eq '>>'
            and $cmpver >= 0;

        # >> 4 satisfies >= 3 and >= 4
        return 1 if $dep->rel eq '>='
            and $cmpver >= 0;

        # >> 4 can't satisfy =, <= and << relations
        return 0;
    }
    elsif( $self->rel eq '>=' ) {
        # >= 4 satisfies >= 3
        return 1 if $dep->rel eq '>='
            and $cmpver >= 0;

        # >= 4 satisvies >> 3, but not >> 4
        return 1 if $dep->rel eq '>>'
            and $cmpver > 0;

        # >= 4 can't satosfy =, <= and << relations
    }
    elsif( $self->rel eq '=' ) {
        return 1 if $dep->rel eq '='
            and $cmpver == 0;

        # = 4 also satisfies >= 3 and >= 4
        return 1 if $dep->rel eq '>='
            and $cmpver >= 0;

        # = 4 satisfies >> 3, but not >> 4
        return 1 if $dep->rel eq '>>'
            and $cmpver > 0;

        # = 4 satisfies <= 4 and <= 5
        return 1 if $dep->rel eq '<='
            and $cmpver <= 0;

        # = 4 satisfies << 5, but not << 4
        return 1 if $dep->rel eq '<<'
            and $cmpver < 0;

        # other cases mean 'no'
        return 0;
    }
    elsif( $self->rel eq '<=' ) {
        # <= 4 satisfies <= 5
        return 1 if $dep->rel eq '<='
            and $cmpver <= 0;

        # <= 4 satisfies << 5, but not << 4
        return 1 if $dep->rel eq '<<'
            and $cmpver < 0;

        # <= 4 can't satisfy =, >= and >>
        return 0;
    }
    elsif( $self->rel eq '<<' ) {
        # << 4 satisfies << 5
        return 1 if $dep->rel eq '<<'
            and $cmpver <= 0;

        # << 4 satisfies <= 5 and <= 4
        return 1 if $dep->rel eq '<='
            and $cmpver <= 0;

        # << 4 can't satisfy =, >= and >>
        return 0;
    }
    else {
        croak "Should not happen: $self satisfies $dep?";
    }
}

=back

=head1 SEE ALSO

L<Debian::Dependencies>

=head1 AUTHOR

=over 4

=item Damyan Ivanov <dmn@debian.org>

=back

=head1 COPYRIGHT & LICENSE

=over 4

=item Copyright (C) 2008,2009 Damyan Ivanov <dmn@debian.org>

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
