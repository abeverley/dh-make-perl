package Debian::Dependencies;

use strict;
use warnings;

use AptPkg::Config;
use Debian::Dependency;

use overload '""'   => \&_stringify,
             '+'    => \&_add,
             'eq'   => \&_eq;

=head1 NAME

Debian::Dependencies -- a list of Debian::Dependency objects

=head1 SYNOPSIS

    my $dl = Debian::Dependencies->new('perl, libfoo-perl (>= 3.4)');
    print $dl->[1]->ver;      # 3.4
    print $dl->[1];           # libfoo-perl (>= 3.4)
    print $dl;                # perl, libfoo-perl (>= 3.4)

    $dl += 'libbar-perl';
    print $dl;                # perl, libfoo-perl (>= 3.4), libbar-perl

    print Debian::Dependencies->new('perl') + 'libfoo-bar-perl';
                              # simple 'sum'

    print Debian::Dependencies->new('perl')
          + Debian::Dependencies->new('libfoo, libbar');
                              # add (concatenate) two lists

    print Debian::Dependencies->new('perl')
          + Debian::Dependency->new('foo');
                              # add depeendency to a list

=head1 DESCRIPTION

Debian::Dependencies a list of Debian::Dependency objects, with automatic
construction and stringification.

Objects of this class are blessed array references. You can safely treat them
as arrayrefs, as long as the elements you put in them are instances of the
L<Debian::Dependency> class.

When used in string context, Debian::Dependencies converts itself into a
comma-delimitted list of dependencies, suitable for dependency fields of
F<debian/control> files.

=head2 CLASS METHODS

=over 4

=item new(dependency-string)

Constructs a new L<Debian::Dependencies> object. Accepts one scalar argument,
which is parsed and turned into an arrayref of L<Debian::Dependency> objects.
Each dependency should be delimitted by a comma and optional space. The exact
regular expression is C</\s*,\s*/>.

=cut

sub new {
    my ( $class, $val ) = @_;

    my $self = bless [], ref($class)||$class;

    if ( defined($val) ) {
        @{$self}
            = map( Debian::Dependency->new($_), split( /\s*,\s*/, $val ) );
    }

    return $self;
}

sub _stringify {
    my $self = shift;

    return join( ', ', @$self );
}

sub _add {
    my $left = shift;
    my $right = shift;
    my $mode = shift;

    $right = $left->new($right) unless ref($right);
    $right = [ $right ] if $right->isa('Debian::Dependency');

    if ( defined $mode ) {      # $a + $b
        return bless [ @$left, @$right ], ref($left);
    }
    else {                      # $a += $b;
        push @$left, @$right;
        $left;
    }
}

sub _eq {
    my( $left, $right ) = @_;

    # force stringification
    return "$left" eq "$right";
}

=back

=head2 OBJECT METHODS

=over 4

=item add( I<dependency> )

Adds I<dependency> to the list of dependencies. No check is made if
I<dependency> is already part of dependencies. I<dependency> can be eitherr an
instance of the L<Debian::Dependency> class, or a string (in which case it is
converted to an instance of the L<Debian::Dependency> class).

=cut

sub add {
    my( $self, $dep ) = @_;

    $dep = Debian::Dependency->new($dep)
        unless ref($dep);

    $self += $dep;
}

=item remove( I<dependency>, ... )
=item remove( I<dependencies>, ... )

Removes a dependency from the list of dependencies. Instances of
L<Debian::Dependency> and L<Debian::Dependencies> classes are supported as
arguments.

Any non-reference arguments are coerced to instances of L<Debian::Dependencies>
class.

Only dependencies that are subset of the given dependencies are removed:

    my $deps = Debian::Dependencies->new('foo (>= 1.2), bar');
    $deps->remove('foo, bar (>= 2.0)');
    print $deps;    # bar

=cut

sub remove {
    my( $self, @deps ) = @_;

    for my $deps(@deps) {
        $deps = Debian::Dependencies->new($deps)
            unless ref($deps);

        for my $dep(@$deps) {
            @$self = grep { ! $dep->satisfies($_) } @$self;
        }
    }
}

=item prune()

Reduces the list of dependencies by removing duplicate or covering ones. The
resulting list is also sorted by package name.

For example, if you have libppi-perl, libppi-perl (>= 3.0), libarm-perl,
libalpa-perl, libarm-perl (>= 2), calling C<prune> will leave you with
libalpa-perl, libarm-perl (>= 2), libppi-perl (>= 3.0)

=cut

sub prune(@) {
    my $self = shift;
    my %deps;
    for (@$self) {
        my $p = $_->pkg;
        my $v = $_->ver;
        if ( exists $deps{$p} ) {
            my $cur_ver = $deps{$p}->ver;

            # replace the present dependency unless it also satisfies the new
            # one
            $deps{$p} = $_
                unless $deps{$p}->satisfies($_);
        }
        else {
            $deps{$p} = $_;
        }

    }

    @$self = map( $deps{$_}, sort( keys(%deps) ) );
}

=back

=cut

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
