# List of Debian::Dependencyp objects
# Overrides the stringification operator so that one can use
# Debian::Dependencies and a string, consisting of list of dependencies
# interchangably
#
# my $dl = Debian::Dependencies->new('perl, libfoo-perl (>= 3.4)');
# print $dl->[1]->ver;      # 3.4
# print $dl->[1];           # libfoo-perl (>= 3.4)
# print $dl;                # perl, libfoo-perl (>= 3.4)

package Debian::Dependencies;
use strict;
use warnings;
use Debian::Dependency;

use overload
    '""'   => \&stringify;

sub new {
    my ( $class, $val ) = @_;

    my $self = bless [], $class;

    if ( defined($val) ) {
        @{$self} = map(
            Debian::Dependency->new($_),
            split( /\s*,\s*/, $val ) );
    }
}

sub stringify {
    my $self = shift;

    return join( ', ', @$self );
}

1;
