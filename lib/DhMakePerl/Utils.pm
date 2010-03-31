package DhMakePerl::Utils;

=head1 NAME

DhMakePerl::Utils - helper routined for dh-make-perl and alike

=head1 SYNOPSIS

    use DhMakePerl::Utils qw(is_core_module);

    my $v = is_core_module('Test::More', '1.002');

=cut

our @EXPORT_OK = qw( find_cpan_module is_core_module );

use base Exporter;

use Module::CoreList ();

=head1 FUNCTIONS

None of he following functions is exported by default.

=over

=item find_cpan_module

Returns CPAN::Module object that corresponds to the supplied argument. Returns
undef if no module is found by CPAN.

=cut

sub find_cpan_module {
    my( $name ) = @_;

    my $mod;

    # expand() returns a list of matching items when called in list
    # context, so after retrieving it, we try to match exactly what
    # the user asked for. Specially important when there are
    # different modules which only differ in case.
    #
    # This Closes: #451838
    my @mod = CPAN::Shell->expand( 'Module', '/^' . $name . '$/' );

    foreach (@mod) {
        my $file = $_->cpan_file();
        $file =~ s#.*/##;          # remove directory
        $file =~ s/(.*)-.*/$1/;    # remove version and extension
        $file =~ s/-/::/g;         # convert dashes to colons
        if ( $file eq $name ) {
            $mod = $_;
            last;
        }
    }
    $mod = shift @mod unless ($mod);

    return $mod;
}

=item is_core_module I<module>, I<version>

Returns the version of the C<perl> package containing the given I<module> (at
least version I<version>).

Returns C<undef> if I<module> is not a core module.

=cut

sub is_core_module {
    my ( $module, $ver ) = @_;

    my $v = Module::CoreList->first_release($module, $ver);   # 5.009002

    return unless defined $v;

    $v = version->new($v);                              # v5.9.2
    ( $v = $v->normal ) =~ s/^v//;                      # "5.9.2"

    return $v;
}

=back

=head1 COPYRIGHT & LICENSE

=over

=item Copyright (C) 2008, 2009, 2010 Damyan Ivanov <dmn@debian.org>

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

1; # End of DhMakePerl
