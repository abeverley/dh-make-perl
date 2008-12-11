package DhMakePerl::PodParser;

use strict;
use warnings;

use base qw(Pod::Parser);

=head1 NAME

DhMakePerl::PodParser - internal helper module for DhMakePerl

=head1 SYNOPSIS

DhMakePerl::PodParser is used by DhMakePerl to extract some
information from the module-to-be-packaged. It subclasses from
L<Pod::Parser> - Please refer to it for further documentation.

=head1 METHODS

=over

=item set_names

Defines the names of the sections that should be fetched from the POD

=cut

sub set_names {
    my ( $parser, @names ) = @_;
    foreach my $n (@names) {
        $parser->{_deb_}->{$n} = undef;
    }
}

=item get

Gets the contents for the specified POD section
    
=cut

sub get {
    my ( $parser, $name ) = @_;
    $parser->{_deb_}->{$name};
}

=item cleanup

Empties the information held by the parser object
    
=cut

sub cleanup {
    my $parser = shift;
    delete $parser->{_current_};
    foreach my $k ( keys %{ $parser->{_deb_} } ) {
        $parser->{_deb_}->{$k} = undef;
    }
}

=item command

Implemented as base class requires it. Gets each of the POD's commands
(sections), and defines how it should react to each of them. In this
particular implementation, it basically filters out anything except
for the C<=head> sections defined in C<set_names>

=cut

sub command {
    my ( $parser, $command, $paragraph, $line_num ) = @_;
    $paragraph =~ s/\s+$//s;
    if ( $command =~ /head/ && exists( $parser->{_deb_}->{$paragraph} ) ) {
        $parser->{_current_} = $paragraph;
        $parser->{_lineno_}  = $line_num;
    }
    else {
        delete $parser->{_current_};
    }

    #print "GOT: $command -> $paragraph\n";
}

=item add_text

Hands back the text it received as it ocurred in the input stream (see
the base class' documentation for C<verbatim>, C<textblock>,
C<interior_sequence>)

=cut

sub add_text {
    my ( $parser, $paragraph, $line_num ) = @_;
    return unless exists $parser->{_current_};
    return if ( $line_num - $parser->{_lineno_} > 15 );
    $paragraph =~ s/^\s+//s;
    $paragraph =~ s/\s+$//s;
    $paragraph = $parser->interpolate( $paragraph, $line_num );
    $parser->{_deb_}->{ $parser->{_current_} } .= "\n\n" . $paragraph;

    #print "GOT: $paragraph'\n";
}

=item verbatim

Implemented as base class requires it - Just passes its arguments to
add_text

=cut

sub verbatim { shift->add_text(@_) }

=item textblock

Implemented as the base class requires it - Just passes its arguments
to add_text

=cut

sub textblock { shift->add_text(@_) }

=item interior_sequence

Implemented as the base class requires it - Translates common POD
escaped entities into their text representation.

=cut

sub interior_sequence {
    my ( $parser, $seq_command, $seq_argument ) = @_;
    if ( $seq_command eq 'E' ) {
        my %map = ( 'gt' => '>', 'lt' => '<', 'sol' => '/', 'verbar' => '|' );
        return $map{$seq_argument} if exists $map{$seq_argument};
        return chr($seq_argument) if ( $seq_argument =~ /^\d+$/ );

        # html names...
    }
    return $seq_argument;
}

1;

=back

=head1 AUTHOR

=over 4

=item Paolo Molaro

=back

=head1 COPYRIGHT & LICENSE

=over 4

=item Copyright (C) 2001, Paolo Molaro <lupus@debian.org>

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
