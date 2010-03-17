package Debian::Rules;

=head1 NAME

Debian::Rules - handy manipulation of debian/rules

=head1 SYNOPSIS

    my $r = Debian::Rules->new('debian/rules');

    my $r = Debian::Rules->new( { filename => 'debian/rules' } );

    $r->is_dh7tiny && print "Using the latest and greatest\n";
    $r->is_quiltified && print "quilt rules the rules\n";

    # file contents changed externally
    $r->parse;

    $r->add_quilt;
    $r->drop_quilt;


=head1 DESCRIPTION

Some times, one needs to know whether F<debian/rules> uses the L<debhelper(1)>
7 tiny variant, or whether it is integrated with L<quilt(1)>. Debian::Rules
provides facilities to check this, as well as adding/removing quilt
integration.

=head1 CONSTRUCTOR

C<new> is the standard L<Class::Accessor> constructor, with the exception that
if only one, non-reference argument is provided, it is treated as a value for
the L<filename> field.

=head1 FIELDS

=over

=item filename

Contains the file name of the rules file.

=item lines

Reference to a tied (via <Tie::File>) array pointing to the rules file. Initialized by L</new>.

=back

=cut

use base 'Class::Accessor';
use Tie::File;

__PACKAGE__->mk_accessors(
    qw(filename lines _is_dh7tiny _is_quiltified _parsed));

sub new {
    my $class = shift;

    my @params = @_;

    # allow single argument to be treated as filename
    @params = { filename => $params[0] }
        if @params == 1 and not ref( $params[0] );

    my $self = $class->SUPER::new(@params);

    $self->filename or die "'filename' is mandatory";

    my @lines;
    tie @lines, Tie::File, $self->filename;

    $self->lines( \@lines );

    return $self;
}

=head1 METHODS

=over

=item parse

Parses the rules file and stores its findings for later use. Called
automatically by L<is_dh7tiny> and L<is_quiltified>. The result of the parsing
is cached and subsequent calls to C<is_XXX> use the cache. To force cache
refresh (for eample if the contents of the file have been changed), call
C<parse> again.

=cut

sub parse {
    my $self = shift;

    $self->_is_dh7tiny(0);
    $self->_is_quiltified(0);

    for ( my $i = 1; $i < @{ $self->lines }; $i++ ) {
        if (    $self->lines->[$i] eq '%:'
            and $i + 1 < @{ $self->lines }
            and $self->lines->[ $i + 1 ] =~ /^\tdh .*\$\@/ )
        {
            $self->_is_dh7tiny(1);

            if ( $self->lines->[ $i + 1 ] =~ /--with[ =]quilt/ ) {
                $self->_is_quiltified(1);
                last;
            }
        }
    }

    $self->_parsed(1);
}

=item is_dh7tiny

Returns true if the contents of the rules file seem to use the so called
I<tiny> variant offerred by debhelper 7. Tiny rules are detected by the
presense of the following two lines:

    %:
            dh $@

(any options on the C<dh> command line ignored).

=cut

sub is_dh7tiny {
    my $self = shift;

    $self->parse unless $self->_parsed;

    return $self->_is_dh7tiny;
}

=item is_quiltified

Returns true if the contents of the rules file indicate that L<quilt(1)> is
used. Various styles of C<quilt> integration are detected:

=over

=item dh --with=quilt

=item F<quilt.make> with C<< $(QUILT_STAMPFN) >> and C<unpatch> targets.

=back

=cut

sub is_quiltified {
    my $self = shift;

    $self->parse unless $self->_parsed;

    return $self->_is_quiltified;
}

=item add_quilt

Integrates L<quilt(1)> into the rules. For debhelper 7 I<tiny> rules (as
determined by L</is_dh7tiny>) C<--with=quilt> is added to every C<dh>
invocation. For the more traditional variant, quilt is integrated vua
F<quilt.make> and its C<< $(QUILT_STAMPFN) >> and C<unpatch> targets.

=cut

sub add_quilt {
    my $self = shift;

    return if $self->is_quiltified;

    my $lines = $self->lines;

    if ( $self->is_dh7tiny) {
        for (@$lines) {

            # add --with=quilt to every dh call
            s/(?<=\s)dh /dh --with=quilt /
                unless /--with[= ]quilt/;    # unless it is already there
        }
    }
    else {

        # non-dh7tiny
        splice @$lines, 1, 0,
            ( '', 'include /usr/share/quilt/quilt.make' )
            unless grep /quilt\.make/, @$lines;

        push @$lines,
            '',
            'override_dh_auto_configure: $(QUILT_STAMPFN)',
            "\tdh_auto_configure"
            unless grep /QUILT_STAMPFN/, @$lines;

        push @$lines, '', 'override_dh_auto_clean: unpatch',
            "\tdh_auto_clean"
            unless grep /override_dh_auto_clean:.*unpatch/, @$lines;
    }
}

=item drop_quilt

Removes L<quilt(1)> integration. Both debhelper 7 I<tiny> style (C<dh
--with=quilt>) and traditional (C<< $(QUILT_STAMPFN >> and C<unpatch>)
approaches are detected and removed.

=cut

sub drop_quilt {
    my $self = shift;

    my $lines = $self->lines;

    # look for the quilt include line and remove it and the previous empty one
    for ( my $i = 1; $i < @$lines; $i++ ) {
        if ( $lines->[$i] eq 'include /usr/share/quilt/quilt.make' ) {
            splice @$lines, $i, 1;

            # collapse two sequencial empty lines
            # NOTE: this won't work if the include statement was the last line
            # in the rules, but this is highly unlikely
            splice( @$lines, $i, 1 )
                if $i < @$lines
                    and $lines->[$i] eq ''
                    and $lines->[ $i - 1 ] eq '';

            last;
        }
    }

    # remove the QUILT_STAMPFN dependency override
    for ( my $i = 1; $i < @$lines; $i++ ) {
        if (    $lines->[$i] eq ''
            and $lines->[ $i + 1 ] eq
            'override_dh_auto_configure: $(QUILT_STAMPFN)'
            and $lines->[ $i + 2 ] eq "\tdh_auto_configure"
            and $lines->[ $i + 3 ] eq '' )
        {
            splice @$lines, $i, 3;
            last;
        }
    }

   # also remove $(QUILT_STAMPFN) as a target dependency
   # note that the override_dh_auto_configure is handled above because in that
   # case the whole makefile snipped is to be removed
   # Here we deal with the more generic cases
    for ( my $i = 1; $i < @$lines; $i++ ) {
        $lines->[$i] =~ s{
            ^                               # at the beginning of the line
            ([^\s:]+):                      # target name, followed by a colon
            (.*)                            # any other dependencies
            \$\(QUILT_STAMPFN\)             # followed by $(QUILT_STAMPFN)
        }{$1:$2}x;
    }

    # remove unpatch dependency in clean
    for ( my $i = 1; $i < @$lines; $i++ ) {
        if (    $lines->[$i] eq 'override_dh_auto_clean: unpatch'
            and $lines->[ $i + 1 ] eq "\tdh_auto_clean"
            and ( $i + 2 > $#$lines or $lines->[ $i + 2 ] !~ /^\t/ ) )
        {
            splice @$lines, $i, 2;

            # At this point there may be an extra empty line left.
            # Remove an empty line after the removed target
            # Or any trailing empty line (if the target was at EOF)
            if ( $i > $#$lines ) {
                $#$lines-- if $lines->[-1] eq '';   # trim trailing empty line
            }
            elsif ( $lines->[$i] eq '' ) {
                splice( @$lines, $i, 1 );
            }

            last;
        }
    }

    # similarly to the $(QUILT_STAMPFN) stripping, here we process a general
    # ependency on the 'unpatch' rule
    for ( my $i = 1; $i < @$lines; $i++ ) {
        $lines->[$i] =~ s{
            ^                               # at the beginning of the line
            ([^\s:]+):                      # target name, followed by a colon
            (.*)                            # any other dependencies
            unpatch                         # followed by 'unpatch'
        }{$1:$2}x;
    }

    # drop --with=quilt from dh command line
    for (@$lines) {
        s/dh (.*)--with[= ]quilt\s*/dh $1/g;
    }
}

=item copy_from I<filename>

Replaces the current rules content with the content of I<filename>.

=cut

sub copy_from {
    my ( $self, $filename ) = @_;

    my $fh;
    open( $fh, '<', $filename ) or die "open($filename): $!";
    @{ $self->lines } = ();
    while( defined( $_ = <$fh> ) ) {
        push @{ $self->lines }, $_;
    }
    $self->_parsed(0);

    ( tied @{ $self->lines } )->flush;
}

=back

=head1 COPYRIGHT & LICENSE

=over

=item Copyright (C) 2009, 2010 Damyan Ivanov <dmn@debian.org>

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
