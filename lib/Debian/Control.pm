# The C<Control> class represent debian/control file of a single Debian
# source package
#
# SYNOPSIS
#
#   my $c = Control->read($file);   # construct from file
#   my $c = Control->new(\%data);   # construct anew with optional data
#   $c->write($file);               # write to file
#   print $c->source->{Package};
#   print for @{ $c->source->{Build-Depends} };  # arrayref of Dep objects
#   $c->binary->{'libfoo-perl'}{Description} = "Foo Perl module\n"
#                                            . " Foo makes this and that";
#
package Debian::Control;

use base 'Class::Accessor';

__PACKAGE__->mk_accessors( qw( source binary _parser ) );

use Parse::DebControl;

sub new {
    my $class = shift;

    my $self = $class->SUPER::new(@_);

    $self->_parser( Parse::DebControl->new );

    $self->binary( {} );
}

sub read {
    my ( $self, $file ) = @_;

    my $stanzas = $self->_parser->parse_file( $file,
        { useTieIxHash => 1, verbMultiLine => 1 } );

    for (@$stanzas) {
        if ( $_->{Source} ) {
            $self->source($_);
        }
        elsif ( $_->{Package} ) {
            $self->binary->{ $_->{Package} } = $_;
        }
        else {
            die "Got control stanza with neither Source nor Package field\n";
        }
    }
}

sub write {
    my ( $self, $file ) = @_;

    $self->_parser->write_file( $file,
        $self->source,
        values %{ $self->binary } );
}

1;
