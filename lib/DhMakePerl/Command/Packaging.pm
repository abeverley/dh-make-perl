package DhMakePerl::Command::Packaging;

use strict;
use warnings;

=head1 NAME

DhMakePerl::Command::Packaging - common routines for 'make' and 'refresh' dh-make-perl commands

=cut

use base 'DhMakePerl';

__PACKAGE__->mk_accessors(
    qw( start_dir main_dir debian_dir
        meta perlname author
        version rules docs examples copyright
        control
    )
);

use Array::Unique;
use Carp qw(confess);
use CPAN ();
use Cwd qw( getcwd );
use Debian::Control::FromCPAN;
use Debian::Dependencies;
use Debian::Rules;
use DhMakePerl::PodParser ();
use File::Basename qw(basename dirname);
use File::Find qw(find);
use File::Path ();
use File::Spec::Functions qw(catfile catpath splitpath);
use Parse::DebianChangelog;
use Text::Wrap qw(fill);
use User::pwent;

use constant debstdversion => '3.8.4';

our %DEFAULTS = (
    start_dir => getcwd(),
);

sub new {
    my $class = shift;
    $class = ref($class) if ref($class);

    my $self = $class->SUPER::new(@_);

    while( my( $k, $v ) = each %DEFAULTS ) {
        $self->$k($v) unless defined $self->$k;
    }

    $self->cfg or die "cfg is mandatory";

    my @docs;
    tie @docs, 'Array::Unique';

    $self->docs( \@docs );

    my @examples;
    tie @examples, 'Array::Unique';

    $self->examples( \@examples );

    $self->control( Debian::Control::FromCPAN->new )
        unless $self->control;

    return $self;
}

=head1 METHODS

=over

=item main_file(file_name)

Constructs a file name relative to the main source directory, L</main_dir>

=cut

sub main_file {
    my( $self, $file ) = @_;

    catfile( $self->main_dir, $file );
}

=item debian_file(file_name)

Constructs a file name relative to the debian/ subdurectory of the main source
directory.

=cut

sub debian_file {
    my( $self, $file ) = @_;

    catfile( $self->main_file('debian'), $file );
}

sub makefile_pl {
    my ($self) = @_;

    return $self->main_file('Makefile.PL');
}

sub get_developer {
    my $self = shift;

    my $email = $self->cfg->email;

    my ( $user, $pwnam, $name, $mailh );
    $user = $ENV{LOGNAME} || $ENV{USER};
    $pwnam = getpwuid($<);
    die "Cannot determine current user\n" unless $pwnam;
    if ( defined $ENV{DEBFULLNAME} ) {
        $name = $ENV{DEBFULLNAME};
    }
    else {
        $name = $pwnam->gecos;
        $name =~ s/,.*//;
    }
    $user ||= $pwnam->name;
    $name ||= $user;
    $email ||= ( $ENV{DEBEMAIL} || $ENV{EMAIL} );
    unless ($email) {
        chomp( $mailh = `cat /etc/mailname` );
        $email = $user . '@' . $mailh;
    }

    $email =~ s/^(.*)\s+<(.*)>$/$2/;

    return "$name <$email>";
}

sub fill_maintainer {
    my $self = shift;

    my $src = $self->control->source;
    my $maint = $self->get_developer;

    if ( $self->cfg->pkg_perl ) {
        my $pkg_perl_maint
            = "Debian Perl Group <pkg-perl-maintainers\@lists.alioth.debian.org>";
        unless ( ( $src->Maintainer // '' ) eq $pkg_perl_maint ) {
            my $old_maint = $src->Maintainer;
            $src->Maintainer($pkg_perl_maint);
            $src->Uploaders->add($old_maint) if $old_maint;
        }

        $src->Uploaders->add($maint);
    }
    else {
        $src->Maintainer($maint);
    }
}

sub process_meta {
    my ($self) = @_;

    my $file = $self->main_file('META.yml');

    # META.yml non-existent?
    unless ( -f $file ) {
        $self->meta({});
        return;
    }

    # Command line option nometa causes this function not to be run
    if( $self->cfg->nometa ) {
        $self->meta({});
        return;
    }

    my $yaml;

    # YAML::LoadFile dies when it cannot properly parse a file - catch it in
    # an eval, and if it dies, return -again- just an empty hashref.
    eval { $yaml = YAML::LoadFile($file); };
    if ($@) {
        print "Error parsing $file - Ignoring it.\n";
        print "Please notify module upstream maintainer.\n";
        $yaml = {};
    }

    if (ref $yaml ne 'HASH') {
        print "$file does not contain a hash - Ignoring it\n";
        $yaml = {};
    }

    # Returns a simple hashref with all the keys/values defined in META.yml
    $self->meta($yaml);
}

sub set_package_name {
    my $self = shift;

    my $pkgname = lc $self->perlname;
    $pkgname = 'lib' . $pkgname unless $pkgname =~ /^lib/;
    $pkgname .= '-perl';

    # ensure policy compliant names and versions (from Joeyh)...
    $pkgname =~ s/[^-.+a-zA-Z0-9]+/-/g;

    $self->control->source->Source($pkgname)
        unless $self->control->source->Source;

    $self->control->binary->Push( $pkgname =>
            Debian::Control::Stanza::Binary->new( { Package => $pkgname } ) )
        unless $self->control->binary->FETCH($pkgname);
}

sub pkgname {
    @_ == 1 or die 'Syntax: $obj->pkgname()';

    my $self = shift;

    my $pkg = $self->control->binary->Values(0)->Package;

    defined($pkg) and $pkg ne ''
        or confess "called before set_package_name()";

    return $pkg;
}

sub srcname {
    @_ == 1 or die 'Syntax: $obj->srcname()';

    my $self = shift;

    my $pkg = $self->control->source->Source;

    defined($pkg) and $pkg ne ''
        or confess "called before set_package_name()";

    return $pkg;
}

sub get_wnpp {
    my ( $self, $package ) = @_;

    return undef unless $self->cfg->network;

    my $wnpp = Debian::WNPP::Query->new(
        { cache_file => catfile( $self->cfg->home_dir, 'wnpp.cache' ) } );
    my @bugs = $wnpp->bugs_for_package($package);
    return $bugs[0];
}

sub extract_basic {
    my ($self) = @_;

    $self->extract_name_ver();

    my $src = $self->control->source;
    my $bin = $self->control->binary->Values(0);

    $src->Section('perl') unless defined $src->Section;
    $src->Priority('optional') unless defined $src->Priority;

    $bin->Architecture('all');
    find( sub { $self->check_for_xs }, $self->main_dir );

    printf(
        "Found: %s %s (%s arch=%s)\n",
        $self->perlname, $self->version,
        $self->pkgname,  $bin->Architecture
    ) if $self->cfg->verbose;
    $self->debian_dir( $self->main_file('debian') );

    find(
        sub {
            return if $File::Find::name =~ $self->cfg->exclude;

            if (/\.(pm|pod)$/) {
                $self->extract_desc($_)
                    unless $bin->short_description and $bin->long_description;
                $self->extract_basic_copyright($_)
                    unless $self->author and $self->copyright;
            }
        },
        $self->main_dir
    );
}

sub extract_name_ver {
    my ($self) = @_;

    my ( $name, $ver );

    if ( defined $self->meta->{name} and defined $self->meta->{version} ) {
        $name = $self->meta->{name};
        $ver  = $self->meta->{version};
        if ( $ver =~ s/^v// ) {    # v4.43.43?
            $ver =~ s/\.(\d\d\d)(\d\d\d)/.$1.$2/;    # 2.003004 -> 2.003.004
            $ver =~ s/\.0+/./g;                      # 2.003.004 -> 2.3.4
        }
    }
    else {
        $self->extract_name_ver_from_makefile( $self->makefile_pl );
        $name = $self->perlname;
        $ver  = $self->version;
    }

    # final sanitazing of name and version
    $ver =~ s/[^-.+a-zA-Z0-9]+/-/g;
    $ver = "0$ver" unless $ver =~ /^\d/;

    $name =~ s/::/-/g;

    $self->perlname($name);
    $self->version($ver);

    $self->set_package_name;
}

sub extract_name_ver_from_makefile {
    my ( $self, $makefile ) = @_;
    my ( $file, $name, $ver, $vfrom, $dir );

    {
        local $/ = undef;
        my $fh = $self->_file_r($makefile);
        $file = $fh->getline;
    }

    # Replace q[quotes] by "quotes"
    $file =~ s/q\[(.+)]/'$1'/g;

    # Get the name
    if ($file =~ /([\'\"]?)
	    DISTNAME\1\s*
	    (=>|,)
	    \s*
	    ([\'\"]?)
	    (\S+)\3/xs
        )
    {

        # Regular MakeMaker
        $name = $4;
    }
    elsif (
        $file =~ /([\'\"]?)
		 NAME\1\s*
		 (=>|,)
		 \s*
		 ([\'\"]?)
		 (\S+)\3/xs
        )
    {

        # Regular MakeMaker
        $name = $4;
    }
    elsif (
        $file =~ m{
                        name
                         \s*
                         \(?                    # Optional open paren
                             ([\'\"]?)          # Optional open quote
                                 (\S+)          # Quoted name
                             \1                 # Optional close quote
                         \)?                    # Optional close paren
                         \s*;
                 }xs
        )
    {

        # Module::Install syntax
        $name = $2;
    }
    $name =~ s/,.*$//;

    # band aid: need to find a solution also for build in directories
    # warn "name is $name (cpan name: $self->cfg->cpan)\n";
    $name = $self->cfg->cpan     if ( $name eq '__PACKAGE__' && $self->cfg->cpan );
    $name = $self->cfg->cpanplus if ( $name eq '__PACKAGE__' && $self->cfg->cpanplus );

    # Get the version
    if ( defined $self->cfg->version ) {

        # Explicitly specified
        $ver = $self->cfg->version;

    }
    elsif ( $file =~ /([\'\"]?)VERSION\1\s*(=>|,)\s*([\'\"]?)(\S+)\3/s ) {

        # Regular MakeMaker
        $ver = $4;

        # Where is the version taken from?
        $vfrom = $4
            if $file
                =~ /([\'\"]?)VERSION_FROM\1\s*(=>|,)\s*([\'\"]?)(\S+)\3/s;

    }
    elsif ( $file =~ /([\'\"]?)VERSION_FROM\1\s*(=>|,)\s*([\'\"]?)(\S+)\3/s )
    {

        # Regular MakeMaker pointing to where the version is taken from
        $vfrom = $4;

    }
    elsif ( 
        $file =~ m{
            \bversion\b\s*                  # The word version
            \(?\s*                          # Optional open-parens
            (['"]?)                         # Optional quotes
            ([\d_.]+)                       # The actual version.
            \1                              # Optional close-quotes
            \s*\)?                          # Optional close-parens.
        }sx 
    ) {

        # Module::Install
        $ver = $2;
    }

    $dir = dirname($makefile) || './';

    for ( ( $name, $ver ) ) {
        next unless defined;
        next unless /^\$/;

        # decode simple vars
        s/(\$\w+).*/$1/;
        if ( $file =~ /\Q$_\E\s*=\s*([\'\"]?)(\S+)\1\s*;/ ) {
            $_ = $2;
        }
    }

    unless ( defined $ver ) {
        local $/ = "\n";

        # apply the method used by makemaker
        if (    defined $dir
            and defined $vfrom
            and -f "$dir/$vfrom"
            and -r "$dir/$vfrom" )
        {
            my $fh = $self->_file_r("$dir/$vfrom");
            while ( my $lin = $fh->getline ) {
                if ( $lin =~ /([\$*])(([\w\:\']*)\bVERSION)\b.*\=/ ) {
                    no strict;

                    #warn "ver: $lin";
                    $ver = ( eval $lin )[0];
                    last;
                }
            }
            $fh->close;
        }
        else {
            if ( $self->mod_cpan_version ) {
                $ver = $self->mod_cpan_version;
                warn "Cannot use internal module data to gather the "
                    . "version; using cpan_version\n";
            }
            else {
                die "Cannot use internal module data to gather the "
                    . "version; use --cpan or --version\n";
            }
        }
    }

    $self->perlname($name);
    $self->version($ver);

    $self->set_package_name;

    if ( defined($vfrom) ) {
        $self->extract_desc("$dir/$vfrom");
        $self->extract_basic_copyright("$dir/$vfrom");
    }
}

sub extract_desc {
    my ( $self, $file ) = @_;

    my $bin = $self->control->binary->Values(0);
    my $desc = $bin->short_description;

    $desc and return;

    return unless -f $file;
    my ( $parser, $modulename );
    $parser = new DhMakePerl::PodParser;
    $parser->set_names(qw(NAME DESCRIPTION DETAILS));
    $parser->parse_from_file($file);
    if ( $desc ) {

        # No-op - We already have it, probably from the command line

    }
    elsif ( $self->meta->{abstract} ) {

        # Get it from META.yml
        $desc = $self->meta->{abstract};

    }
    elsif ( my $my_desc = $parser->get('NAME') ) {

        # Parse it, fix it, send it!
        $my_desc =~ s/^\s*\S+\s+-\s+//s;
        $my_desc =~ s/^\s+//s;
        $my_desc =~ s/\s+$//s;
        $my_desc =~ s/^([^\s])/ $1/mg;
        $my_desc =~ s/\n.*$//s;
        $desc = $my_desc;
    }

    # Replace linefeeds (not followed by a space) in short description with
    # spaces
    $desc =~ s/\n(?=\S)/ /gs;
    $desc =~ s/^\s+//;      # strip leading spaces
    $bin->short_description($desc);

    my $long_desc;
    unless ( $bin->long_description ) {
        $long_desc 
            = $parser->get('DESCRIPTION')
            || $parser->get('DETAILS')
            || '';
        ( $modulename = $self->perlname ) =~ s/-/::/g;
        $long_desc =~ s/This module/$modulename/;

        local ($Text::Wrap::columns) = 78;
        $long_desc = fill( "", "", $long_desc );
    }

    if ( defined($long_desc) ) {
        $long_desc =~ s/^[\s\n]+//s;
        $long_desc =~ s/\s+$//s;
        $long_desc =~ s/^\t/ /mg;
        $long_desc =~ s/\r//g;
        $long_desc = '(no description was found)' if $long_desc eq '';

        $bin->long_description(
            "$long_desc\n\nThis description was automagically extracted from the module by dh-make-perl.\n"
        );
    }

    $parser->cleanup;
}

sub check_for_xs {
    my ($self) = @_;

    # we need the relative path here. Otherwise the check will give bogus
    # results if the working dir matches the pattern
    my $rel_path = substr( $File::Find::name, length( $self->main_dir ) );
    ( $rel_path !~ m{/(?:examples?|samples|eg|t|docs?)/} )
            and
    ( !$self->cfg->exclude or $rel_path !~ $self->cfg->exclude )
        && /\.(xs|c|cpp|cxx)$/i
        && do {
        $self->control->binary->Values(0)->Architecture('any');
        };
}

sub extract_basic_copyright {
    my ( $self, $file ) = @_;

    for my $f ( map( $self->main_file($_), qw(LICENSE LICENCE COPYING) ) ) {
        if ( -f $f ) {
            my $fh = $self->_file_r($f);
            $self->copyright( join( '', $fh->getlines ) );
        }
    }

    if ( defined($file) ) {
        my ( $parser, $modulename );
        $parser = new DhMakePerl::PodParser;
        return unless -f $file;
        $parser->set_names(qw(COPYRIGHT AUTHOR AUTHORS));
        $parser->parse_from_file($file);

        $self->copyright( $parser->get('COPYRIGHT')
                || $parser->get('LICENSE')
                || $parser->get('COPYRIGHT & LICENSE') )
            unless $self->copyright;

        if ( !$self->author ) {
            if ( ref $self->meta->{author} ) {

                # Does the author information appear in META.yml?
                $self->author( join( ', ', @{ $self->meta->{author} } ) );
            }
            else {

                # Get it from the POD - and clean up
                # trailing/preceding spaces!
                my $a = $parser->get('AUTHOR') || $parser->get('AUTHORS');
                $a =~ s/^\s*(\S.*\S)\s*$/$1/gs if $a;
                $self->author($a);
            }
        }

        $parser->cleanup;
    }
}

sub extract_docs {
    my ( $self ) = @_;

    my $dir = $self->main_dir;

    $dir .= '/' unless $dir =~ m(/$);
    find(
        {   preprocess => sub {
                my $bn = basename $File::Find::dir;
                return ()
                    if $bn eq '.svn-base'
                        or $bn eq '.svn'
                        or $bn eq '.git';

                return @_;
            },
            wanted => sub {
                push(
                    @{ $self->docs },
                    substr( $File::Find::name, length($dir) )
                    )
                    if (
                        /^\b(README|TODO|BUGS|NEWS|ANNOUNCE)\b/i
                    and !/\.(pod|pm)$/
                    and ( !$self->cfg->exclude
                        or $File::Find::name !~ $self->cfg->exclude )
                    and !/\.svn-base$/
                    and $File::Find::name
                    !~ m{debian/README\.(?:source|[Dd]ebian)}
                    );
            },
        },
        $dir
    );
}

sub extract_examples {
    my ( $self ) = @_;

    my $dir = $self->main_dir;

    $dir .= '/' unless $dir =~ m{/$};
    find(
        sub {
            return if $_ eq '.';  # skip the directory itself
            my $exampleguess = substr( $File::Find::name, length($dir) );
            push( @{ $self->examples },
                ( -d $exampleguess ? $exampleguess . '/*' : $exampleguess ) )
                if ( /^(examples?|eg|samples?)$/i
                and ( !$self->cfg->exclude or $File::Find::name !~ $self->cfg->exclude )
                );
        },
        $dir
    );
}

sub create_rules {
    my ( $self ) = @_;

    my $file = $self->debian_file('rules');

    $self->rules( Debian::Rules->new($file) );

    if ( $self->rules->is_dh7tiny ) {
        print "$file already uses DH7 tiny rules\n"
            if $self->cfg->verbose;
        return;
    }

    $self->backup_file($file);

    my $rulesname = 'rules.dh7.tiny';

    for my $source (
        catfile( $self->cfg->home_dir, $rulesname ),
        catfile( $self->cfg->data_dir, $rulesname )
    ) {
        if ( -e $source ) {
            print "Using rules: $source\n" if $self->cfg->verbose;
            $self->rules->read($source);
            last;
        };
    }
    $self->rules->write;
    chmod( 0755, $file ) or die "chmod($file): $!";
}

sub create_compat {
    my ( $self, $file ) = @_;

    my $fh = $self->_file_w($file);
    $fh->print( $self->cfg->dh, "\n" );
    $fh->close;
}

sub update_file_list( $ % ) {
    my ( $self, %p ) = @_;

    my $pkgname = $self->pkgname;

    while ( my ( $file, $new_content ) = each %p ) {
        next unless @$new_content;
        # pkgname.foo file
        my $pkg_file = $self->debian_file("$pkgname.$file");
        my %uniq_content;
        my @existing_content;

        # if a package.foo exists read its values first
        if ( -r $pkg_file ) {
            my $fh                = $self->_file_r($pkg_file);
            @existing_content = $fh->getlines;
            chomp(@existing_content);

            # make list of files for package.foo unique
            $uniq_content{$_} = 1 for @existing_content;
        }

        $uniq_content{$_} = 1 for @$new_content;

        # write package.foo file with unique entries
        open F, '>', $pkg_file or die $!;
        for ( @existing_content, @$new_content ) {

            # we have the unique hash
            # we delete from it each printed line
            # so if a line is not in the hash, this means we have already
            # printed it
            next unless exists $uniq_content{$_};

            delete $uniq_content{$_};
            print F "$_\n";
        }
        close F;
    }
}

sub create_copyright {
    my ( $self, $filename ) = @_;

    my ( $fh, %fields, @res, @incomplete, $year );
    $fh = $self->_file_w($filename);

    # In case author string pawns more than one line, indent them all.
    my $cprt_author = $self->author || '(information incomplete)';
    $cprt_author =~ s/\n/\n    /gs;
    $cprt_author =~ s/^\s*$/    ./gm;

    push @res, "Format-Specification: http://svn.debian.org/wsvn/dep/web/deps/dep5.mdwn?op=file&rev=135";

    # Header section
    %fields = (
        Name       => $self->perlname,
        Maintainer => $cprt_author,
        Source     => $self->upsurl
    );
    for my $key ( keys %fields ) {
        my $full = "$key";
        if ( $fields{$key} ) {
            push @res, "$full: $fields{$key}";
        }
        else {
            push @incomplete, "Could not get the information for $full";
        }
    }
    push( @res,
        "DISCLAIMER: This copyright info was automatically extracted ",
        " from the perl module. It may not be accurate, so you better ",
        " check the module sources in order to ensure the module for its ",
        " inclusion in Debian or for general legal information. Please, ",
        " if licensing information is incorrectly generated, file a bug ",
        " on dh-make-perl.",
        " NOTE: Don't forget to remove this disclaimer once you are happy",
        " with this file." );
    push @res, '';

    # Files section - We cannot "parse" the module's licensing
    # information for anything besides general information.
    push @res, 'Files: *';

    # Absence of author should have already been reported in the
    # Header section
    push @res, "Copyright: $cprt_author";

    # This is far from foolproof, but usually works with most
    # boilerplate-generated modules.
    #
    # We go over the most common combinations only

    my ( %texts, %licenses );
    %texts = (
        'Artistic' =>
            " This program is free software; you can redistribute it and/or modify\n"
            . " it under the terms of the Artistic License, which comes with Perl.\n"
            . " .\n"
            . " On Debian GNU/Linux systems, the complete text of the Artistic License\n"
            . " can be found in `/usr/share/common-licenses/Artistic'",
        'GPL-1+' =>
            " This program is free software; you can redistribute it and/or modify\n"
            . " it under the terms of the GNU General Public License as published by\n"
            . " the Free Software Foundation; either version 1, or (at your option)\n"
            . " any later version.\n"
            . " .\n"
            . " On Debian GNU/Linux systems, the complete text of the GNU General\n"
            . " Public License can be found in `/usr/share/common-licenses/GPL'",
        'GPL-2' =>
            " This program is free software; you can redistribute it and/or modify\n"
            . " it under the terms of the GNU General Public License as published by\n"
            . " the Free Software Foundation; version 2 dated June, 1991.\n"
            . " .\n"
            . " On Debian GNU/Linux systems, the complete text of version 2 of the GNU\n"
            . " General Public License can be found in `/usr/share/common-licenses/GPL-2'",
        'GPL-2+' =>
            " This program is free software; you can redistribute it and/or modify\n"
            . " it under the terms of the GNU General Public License as published by\n"
            . " the Free Software Foundation; version 2 dated June, 1991, or (at your\n"
            . " option) any later version.\n"
            . " .\n"
            . " On Debian GNU/Linux systems, the complete text of version 2 of the GNU\n"
            . " General Public License can be found in `/usr/share/common-licenses/GPL-2'",
        'GPL-3' =>
            " This program is free software; you can redistribute it and/or modify\n"
            . " it under the terms of the GNU General Public License as published by\n"
            . " the Free Software Foundation; version 3 dated June, 2007.\n"
            . " .\n"
            . " On Debian GNU/Linux systems, the complete text of version 3 of the GNU\n"
            . " General Public License can be found in `/usr/share/common-licenses/GPL-3'",
        'GPL-3+' =>
            " This program is free software; you can redistribute it and/or modify\n"
            . " it under the terms of the GNU General Public License as published by\n"
            . " the Free Software Foundation; version 3 dated June, 2007, or (at your\n"
            . " option) any later version\n"
            . " .\n"
            . " On Debian GNU/Linux systems, the complete text of version 3 of the GNU\n"
            . " General Public License can be found in `/usr/share/common-licenses/GPL-3'",
        'Apache-2.0' =>
            " Licensed under the Apache License, Version 2.0 (the \"License\");\n"
            . " you may not use this file except in compliance with the License.\n"
            . " You may obtain a copy of the License at\n"
            . "     http://www.apache.org/licenses/LICENSE-2.0\n"
            . " Unless required by applicable law or agreed to in writing, software\n"
            . " distributed under the License is distributed on an \"AS IS\" BASIS,\n"
            . " WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.\n"
            . " See the License for the specific language governing permissions and\n"
            . " limitations under the License.\n"
            . " .\n"
            . " On Debian GNU/Linux systems, the complete text of the Apache License,\n"
            . " Version 2.0 can be found in `/usr/share/common-licenses/Apache-2.0'",
        'unparsable' =>
            " No known license could be automatically determined for this module.\n"
            . " If this module conforms to a commonly used license, please report this\n"
            . " as a bug in dh-make-perl. In any case, please find the proper license\n"
            . " and fix this file!"
    );

    if ( $self->meta->{license} or $self->copyright ) {
        my $mangle_cprt;

        # Pre-mangle the copyright information for the common similar cases
        $mangle_cprt = $self->copyright || '';    # avoid warning
        $mangle_cprt =~ s/GENERAL PUBLIC LICENSE/GPL/g;

        # Of course, more licenses (i.e. LGPL, BSD-like, Public
        # Domain, etc.) could be added... Feel free to do so. Keep in
        # mind that many licenses are not meant to be used as
        # templates (i.e. you must add the author name and some
        # information within the licensing text as such).
        if (   $self->meta->{license} and $self->meta->{license} =~ /perl/i
            or $mangle_cprt =~ /terms\s*as\s*Perl\s*itself/is )
        {
            $licenses{'GPL-1+'}   = 1;
            $licenses{'Artistic'} = 1;
        }
        else {
            if ( $mangle_cprt =~ /[^L]GPL/ ) {
                if ( $mangle_cprt =~ /GPL.*version\s*1.*later\s+version/is ) {
                    $licenses{'GPL-1+'} = 1;
                }
                elsif (
                    $mangle_cprt =~ /GPL.*version\s*2.*later\s+version/is )
                {
                    $licenses{'GPL-2+'} = 1;
                }
                elsif ( $mangle_cprt =~ /GPL.*version\s*2/is ) {
                    $licenses{'GPL-2'} = 1;
                }
                elsif (
                    $mangle_cprt =~ /GPL.*version\s*3.*later\s+version/is )
                {
                    $licenses{'GPL-3+'} = 1;
                }
                elsif ( $mangle_cprt =~ /GPL.*version\s*3/is ) {
                    $licenses{'GPL-3'} = 1;
                }
            }

            if ( $mangle_cprt =~ /Artistic\s*License/is ) {
                $licenses{'Artistic'} = 1;
            }

            if ( $mangle_cprt =~ /Apache\s*License.*2\.0/is ) {
                $licenses{'Apache-2.0'} = 1;
            }

            # Other licenses?

            if ( !keys(%licenses) ) {
                $licenses{unparsable} = 1;
                push( @incomplete,
                    "Licensing information is present, but cannot be parsed"
                );
            }
        }

        push @res, "License: " . join( ' or ', keys %licenses );

    }
    else {
        push @res,        "License: ";
        push @incomplete, 'No licensing information found';
    }

    # debian/* files information - We default to the module being
    # licensed as the superset of the module and Perl itself.
    $licenses{'Artistic'} = $licenses{'GPL-1+'} = 1;
    $year = (localtime)[5] + 1900;
    push( @res, "", "Files: debian/*" );
    if ( $self->cfg->command eq 'refresh' ) {
        my @from_changelog
            = $self->copyright_from_changelog( $self->get_developer, $year );
        $from_changelog[0] = "Copyright:" . $from_changelog[0];
        push @res, @from_changelog;
    }
    else {
        push @res, "Copyright: $year, " . $self->get_developer;
    }
    push @res, "License: " . join( ' or ', keys %licenses );

    map { $texts{$_} && push( @res, '', "License: $_", $texts{$_} ) }
        keys %licenses;

    $fh->print( join( "\n", @res, '' ) );
    $fh->close;

    $self->_warn_incomplete_copyright( join( "\n", @incomplete ) )
        if @incomplete;
}

sub upsurl {
    my $self = shift;
    return sprintf( "http://search.cpan.org/dist/%s/", $self->perlname );
}

sub copyright_from_changelog {
    my ( $self, $firstmaint, $firstyear ) = @_;
    my %maintainers = ();
    @{ $maintainers{$firstmaint} } = ($firstyear);
    my $chglog = Parse::DebianChangelog->init(
        { infile => $self->debian_file('changelog') } );
    foreach ( $chglog->data() ) {
        my $person      = $_->Maintainer;
        my $date        = $_->Date;
        my @date_pieces = split( " ", $date );
        my $year        = $date_pieces[3];
        if ( defined( $maintainers{$person} ) ) {
            push @{ $maintainers{$person} }, $year;
            @{ $maintainers{$person} } = sort( @{ $maintainers{$person} } );
        }
        else {
            @{ $maintainers{$person} } = ($year);
        }
    }
    my @strings;
    foreach my $maint_name ( keys %maintainers ) {
        my $str = " ";
        my %uniq = map { $_ => 0 } @{ $maintainers{$maint_name} };
        foreach ( sort keys %uniq ) {
            $str .= $_;
            $str .= ", ";
        }
        $str .= $maint_name;
        push @strings, $str;
    }
    @strings = sort @strings;
    return @strings;
}

sub _warn_incomplete_copyright {
    my $self = shift;

    print '*' x 10, '
Copyright information incomplete!

Upstream copyright information could not be automatically determined.

If you are building this package for your personal use, you might disregard
this information; however, if you intend to upload this package to Debian
(or in general, if you plan on distributing it), you must look into the
complete copyright information.

The causes for this warning are:
', @_, "\n";
}

sub write_source_format {
    my ( $self, $path ) = @_;

    my ( $vol, $dir, $file ) = splitpath($path);
    $dir = catpath( $vol, $dir );

    if ( $self->cfg->source_format eq '1.0' ) {
        # this is the default, remove debian/source
        File::Path::rmtree($dir);
    }
    else {
        # make sure the directory exists
        File::Path::mkpath($dir) unless -d $dir;

        my $fh = $self->_file_w($path);
        $fh->print( $self->cfg->source_format, "\n" );
        $fh->close;
    }
}

sub module_build {
    my $self = shift;

    # dehbelper prefers Makefile.PL over Build.PL unless the former is a
    # Module::Build::Compat wrapper
    return 'Module-Build' if $self->makefile_pl_is_MBC;

    return 'MakeMaker' if -e $self->makefile_pl;

    return ( -f $self->main_file('Build.PL') ) ? "Module-Build" : "MakeMaker";
}

=item explained_dependency I<$reason>, I<$dependencies>, I<@dependencies>

Adds the list of dependencies to I<$dependencies> and shows I<$reason> if in
verbose mode.

Used to both bump a dependency ant tell the user why.

I<$dependencies> is an instance of L<Debian::Dependencies> class, and
I<@dependencies> is a list of L<Debian::Dependency> instances or strings.

The message printed looks like C<< $reason needs @dependencies >>.

=cut

sub explained_dependency {
    my ( $self, $reason, $deps, @to_add ) = @_;

    $deps->add(@to_add);

    warn sprintf( "%s needs %s\n", $reason, join( ', ', @to_add ) );
}

=item configure_cpan

Configure CPAN module. It is safe to call this method more than once, it will
do nothing if CPAN is already configured.

=cut

sub configure_cpan {
    my $self = shift;

    return if $CPAN::Config_loaded;

    CPAN::Config->load( be_silent => not $self->cfg->verbose );

    unshift( @{ $CPAN::Config->{'urllist'} }, $self->cfg->cpan_mirror )
        if $self->cfg->cpan_mirror;

    $CPAN::Config->{'build_dir'}         = $ENV{'HOME'} . "/.cpan/build";
    $CPAN::Config->{'cpan_home'}         = $ENV{'HOME'} . "/.cpan/";
    $CPAN::Config->{'histfile'}          = $ENV{'HOME'} . "/.cpan/history";
    $CPAN::Config->{'keep_source_where'} = $ENV{'HOME'} . "/.cpan/source";
    $CPAN::Config->{'tar_verbosity'}     = $self->cfg->verbose ? 'v' : '';
    $CPAN::Config->{'load_module_verbosity'}
        = $self->cfg->verbose ? 'verbose' : 'silent';
}

=item discover_dependencies

Just a wrapper around $self->control->discover_dependencies which provides the
right parameters to it.

=cut

sub discover_dependencies {
    my $self = shift;

    if ( my $apt_contents = $self->get_apt_contents ) {

        my $wnpp_query
            = Debian::WNPP::Query->new(
            { cache_file => catfile( $self->cfg->home_dir, 'wnpp.cache' ) } )
            if $self->cfg->network;

        # control->discover_dependencies needs configured CPAN
        $self->configure_cpan;

        $self->control->discover_dependencies(
            {   dir          => $self->main_dir,
                verbose      => $self->cfg->verbose,
                apt_contents => $self->apt_contents,
                require_deps => $self->cfg->requiredeps,
                wnpp_query   => $wnpp_query,
                intrusive    => $self->cfg->intrusive,
            }
        );
    }
    else {
        warn "No APT contents can be loaded.\n";
        warn "Please install 'apt-file' package and run 'apt-file update'\n";
        warn "as root.\n";
        warn "Dependencies not updated.\n";
    }
}

=item discover_utility_deps

Determines whether a certain version of L<debhelper(1)> or L<quilt(1)> is
needed by the build process.

The following special cases are detected:

=over

=item Module::AutoInstall

If L<Module::AutoInstall> is discovered in L<inc/>, debhelper dependency is
raised to 7.2.13.

=item dh --with=quilt

C<dh --with=quilt> needs debhelper 7.0.8 and quilt 0.46-7.

=item dh --with=bash-completion

C<dh --with=bash-completion> needs debhelper 7.0.8 and bash-completion 1:1.0-3.

=item quilt.make

If F</usr/share/quilt/quilt.make> is included in F<debian/rules>, a
build-dependency on C<quilt> is added.

=item dhebhelper override targets

Targets named C<override_dh_...> are supported by debhelper since 7.0.50

=item Makefile.PL created by Module::Build::Compat

Building such packages requires debhelper 7.0.17 (see
L<http://bugs.debian.org/496157>) =back

=item Module::Build

The proper build-dependency in this case is

    perl (>= 5.10 ) | libmodule-build-perl

=back

=cut

sub discover_utility_deps {
    my ( $self, $control ) = @_;

    my $deps  = $control->source->Build_Depends;

    # remove any existing dependencies
    $deps->remove( 'quilt', 'debhelper' );

    # start with the minimum
    $deps->add( Debian::Dependency->new( 'debhelper', $self->cfg->dh ) );

    if ( $control->binary->Values(0)->Architecture eq 'all' ) {
        $control->source->Build_Depends_Indep->add('perl');
    }
    else {
        $deps->add('perl');
    }

    $self->explained_dependency( 'Module::AutoInstall', $deps,
        'debhelper (>= 7.2.13)' )
        if -e catfile( $self->main_dir, qw( inc Module AutoInstall.pm ) );

    for ( @{ $self->rules->lines } ) {
        $self->explained_dependency( 'dh --with', $deps,
            'debhelper (>= 7.0.8)' )
            if /dh\s+.*--with/;

        $self->explained_dependency(
            'dh --with=quilt',
            $deps, 'quilt (>= 0.46-7)',
        ) if /dh\s+.*--with[= ]quilt/;

        $self->explained_dependency(
            'dh -with=bash-completion',
            $deps,
            'bash-completion (>= 1:1.0-3)'
        ) if (/dh\s+.*--with[= ]bash[-_]completion/);

        $self->explained_dependency( 'override_dh_* target',
            $deps, 'debhelper (>= 7.0.50)' )
            if /^override_dh_/;

        $self->explained_dependency( 'quilt.make', $deps, 'quilt' )
            if m{^include /usr/share/quilt/quilt.make};

        $self->explained_dependency( 'dh* --max-parallel',
            $deps, 'debhelper (>= 7.4.4)' )
            if /dh.* --max-parallel/;
    }

    if (    -e $self->main_file('Makefile.PL')
        and -e $self->main_file('Build.PL') )
    {
        $self->explained_dependency(
            'Compatibility Makefile.PL',
            $deps,
            'debhelper (>= 7.0.17)',
            'perl (>= 5.10) | libmodule-build-perl'
        ) if $self->makefile_pl_is_MBC;
    }

    # there are old packages that still build-depend on libmodule-build-perl
    # Since M::B is part of perl 5.10, the build-dependency needs correction
    if ( $self->module_build eq 'Module-Build' ) {
        $deps->remove('libmodule-build-perl');
        $self->explained_dependency( 'Module::Build', $deps,
            'perl (>= 5.10) | libmodule-build-perl' );
    }

    # some mandatory dependencies
    my $bin_deps = $control->binary->Values(0)->Depends;
    $bin_deps += '${shlibs:Depends}'
        if $self->control->binary->Values(0)->Architecture eq 'any';
    $bin_deps += '${misc:Depends}, ${perl:Depends}';
}

=item makefile_pl_is_MBC

Checks if F<Makefile.PL> is a compatibility wrapper around Build.PL provided by
Module::Build::Compat.

=cut

sub makefile_pl_is_MBC
{
    my $self = shift;

    my $mf = $self->makefile_pl;

    return undef unless -e $mf;

    my $fh = $self->_file_r($mf);

    while( defined( $_ = <$fh> ) ) {
        if ( /^[^#"]*Module::Build::Compat/ ) {
            return 1;
        }
    }

    return 0;
}

=item backup_file(file_name)

Creates a backup copy of the specified file by adding C<.bak> to its name. If
the backup already exists, it is overwritten.

Does nothing unless the C<backups> option is set.

=cut

sub backup_file {
    my( $self, $file ) = @_;

    if ( $self->cfg->backups ) {
        warn "W: overwriting $file.bak\n"
            if -e "$file.bak" and $self->cfg->verbose;
        rename( $file, "$file.bak" );
    }
}

=back

=cut

sub _file_r {
    my ( $self, $filename ) = @_;

    my $fh = IO::File->new( $filename, 'r' )
        or die "Cannot open $filename: $!\n";
    return $fh;
}

sub _file_w {
    my ( $self, $filename ) = @_;

    my $fh = IO::File->new( $filename, 'w' )
        or die "Cannot open $filename: $!\n";
    return $fh;
}

=head1 COPYRIGHT & LICENSE

=over 4

=item Copyright (C) 2000, 2001 Paolo Molaro <lupus@debian.org>

=item Copyright (C) 2002, 2003, 2008 Ivan Kohler <ivan-debian@420.am>

=item Copyright (C) 2003, 2004 Marc 'HE' Brockschmidt <he@debian.org>

=item Copyright (C) 2005-2007 Gunnar Wolf <gwolf@debian.org>

=item Copyright (C) 2006 Frank Lichtenheld <djpig@debian.org>

=item Copyright (C) 2007-2010 Gregor Herrmann <gregoa@debian.org>

=item Copyright (C) 2007-2010 Damyan Ivanov <dmn@debian.org>

=item Copyright (C) 2008, Roberto C. Sanchez <roberto@connexer.com>

=item Copyright (C) 2009-2010, Salvatore Bonaccorso <salvatore.bonaccorso@gmail.com>

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
