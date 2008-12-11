package DhMakePerl::PodParser;

use base qw(Pod::Parser);

sub set_names {
    my ( $parser, @names ) = @_;
    foreach my $n (@names) {
        $parser->{_deb_}->{$n} = undef;
    }
}

sub get {
    my ( $parser, $name ) = @_;
    $parser->{_deb_}->{$name};
}

sub cleanup {
    my $parser = shift;
    delete $parser->{_current_};
    foreach my $k ( keys %{ $parser->{_deb_} } ) {
        $parser->{_deb_}->{$k} = undef;
    }
}

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

sub add_text {
    my ( $parser, $paragraph, $line_num ) = @_;
    return unless exists $parser->{_current_};
    return if ( $line_num - $parser->{_lineno_} > 15 );
    $paragraph =~ s/^\s+//s;
    $paragraph =~ s/\s+$//s;
    $paragraph = $parser->interpolate( $paragraph, $line_num );
    $parser->{_deb_}->{ $parser->{_current_} } .= "\n\n" . $paragraph;

    #print "GOTT: $paragraph'\n";
}

sub verbatim { shift->add_text(@_) }

sub textblock { shift->add_text(@_) }

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
