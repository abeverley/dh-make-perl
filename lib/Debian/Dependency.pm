package Debian::Dependency;

use strict;
use warnings;

=head1 NAME

Debian::Dependency -- dependency relationship between Debian packages

=head1 SYNOPSIS

   my $d = Dep->new( 'perl' );             # simple dependency
   my $d = Dep->new('perl (>= 5.10)');     # also parses a single argument
   my $d = Dep->new( 'perl', '5.10' );     # dependency with a version
   my $d = Dep->new( 'perl', '>=', '5.10' );
                               # dependency with version and relation
   print $d->pkg;  # 'perl'
   print $d->ver;  # '5.10

                                   # for people who like to type much
   my $d = Dep->new( { pkg => 'perl', ver => '5.10' } );

   # stringification
   print "$d"      # 'perl (>= 5.10)'

   # parsing lists
   my @list = Dep->parse_list( 'perl (>= 5.10), libc (>= 2.7)' );
   print $list[0]->ver;    # '5.10'

                                                       # <= relationship
   my @list = Dep->parse_list( 'perl (<= 5.11)' );     # UNSUPPORTED

=cut

use base qw(Class::Accessor);
__PACKAGE__->mk_accessors(qw( pkg ver rel ));

use overload
    '""'    => \&_stringify;
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

sub parse {
    my ( $class, $str ) = @_;

    if ( $str =~ m{
            ^               # start from the beginning
            ([^\(\s]+)      # package name - no paren, no space
            \s*             # oprional space
            (?:             # version is optional
                \(          # opening paren
                    (       # various relations 
                        <<
                      | <=
                      | ==
                      | >=
                      | >>
                    )
                    \s*     # optional space
                    (.+)    # version
                \)          # closing paren
            )?
            $}x             # done
    )
    {
        return $class->new( {
            pkg => $1,
            ( ( defined($2) and defined($3) )
               ? ( rel => $2, ver => $3 )
               : ()
            )
        } );
    }
    else {
        die "Unable to parse '$str'";
    }
}

sub parse_list {
    my $class = shift;
    my @list = split( /\s*,\s*/, shift );

    for( @list ) {
        if ( /(^S+)\s(.+)$/ ) {
            my ( $pkg, $ver ) = ( $1, $2 );
            $ver =~ s/^>=\s*//
                or die "$_: only '>=' relationships are supported";
            $_ = $class->new( $pkg, $ver );
        }
        else {
            $_ = $class->new($_);
        }
    }

    return @list;
}

1;

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
