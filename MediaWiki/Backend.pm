package MediaWiki::Backend;
# copyright notice is at the bottom
use utf8; # ä
use 5.10.0;
use Moose;

=head1 NAME

MediaWiki::Backend - Access MediaWiki data stored in a MySQL database

=head1 VERSION

Version 0.0.6

=cut

use version; our $VERSION = qv('0.0.6');

=head1 SYNOPSIS

    use MediaWiki::Backend;

=head1 DESCRIPTION

TODO

optimize if necessary, test on different setups, think whether al those croaks are necessary ...

=cut

use Carp;
use DBI;
use Encode;
use Graph;

has 'host'               => (is => 'ro', isa => 'Str', required => 1);
has 'user'               => (is => 'ro', isa => 'Str', required => 1);
has 'password'           => (is => 'ro', isa => 'Str', required => 1);
has 'database'           => (is => 'ro', isa => 'Str', required => 1);
has 'prefix'             => (is => 'ro', isa => 'Str', default => '');
has 'namespace'          => (is => 'ro', isa => 'Int', default => 0); # TODO: is this really useful?
has 'category_namespace' => (is => 'ro', isa => 'Int', default => 14);
has 'template_namespace' => (is => 'ro', isa => 'Int', default => 10);
has 'verbose'            => (is => 'rw', isa => 'Int', default => 0);
has 'encoding'           => (is => 'ro', isa => 'Str', default => 'iso-8859-1'); # encoding of the strings in the wiki DB, except (maybe) for the text table
has 'db_handle'          => (is => 'rw', isa => 'Object'); # TODO: use a builder?
has 'error_page_id'      => (is => 'rw', isa => 'ArrayRef[Str]', default => sub { [] });

sub init_db_handle {
    my ($self) = @_;

    my $database = $self->database();
    if (!defined $database) {
        croak 'database not defined';
    } # TODO: remove?
    my $db_host  = $self->host();
    if (!defined $db_host) {
        croak 'host not defined';
    } # TODO: remove?

    # initialize database connection
    my $db_handle = DBI->connect("dbi:mysql:$database:$db_host", $self->user(), $self->password())
      or croak 'Could not connect to database: ' . "'" . DBI->errstr . "'";
    $db_handle->{RaiseError} = 1;

    $self->db_handle($db_handle);
}

# TODO: abstract over queries and put them into a hash ...
sub get_latest_revision {
    my ($self, $page_id) = @_;

    say STDERR "Getting latest revision of $page_id ..." if $self->verbose() > 1;

    my $db_handle = $self->db_handle();
    my $db_prefix = $self->prefix();
    my $get_stmt  = $db_handle->prepare(
					qq[
                                           SELECT old_text, old_flags
                                           FROM ${db_prefix}text
                                           WHERE old_id = (SELECT rev_text_id
                                                           FROM ${db_prefix}revision
                                                           WHERE rev_id = (SELECT MAX(rev_id)
                                                                           FROM ${db_prefix}revision
                                                                           WHERE rev_page=?))
                                        ]
				       );
    $get_stmt->execute($page_id);
    my $text     = '';
    my $flags    = '';
    my $encoding = $self->encoding;
    if (my @row = $get_stmt->fetchrow_array) {
    	($text, $flags) = @row;
	if ($flags ~~ /utf-8/) {
	    $encoding = 'utf8';
	}
    	croak 'Error! No text' if !defined $text;
    }
    else {
	$self->could_not_get_page_id($page_id);
    }

    $text = Encode::decode($encoding, $text);
    return $text;
}

sub get_random_page_id {
    my ($self) = @_;

    my $db_handle = $self->db_handle();
    my $db_prefix = $self->prefix();
    my $get_stmt  = $db_handle->prepare(qq[
        SELECT page_id
        FROM ${db_prefix}page
        WHERE page_namespace=?
        ORDER BY RAND()
        LIMIT 1
    ]);
    say STDERR $get_stmt->{Statement} if $self->verbose > 2;
    $get_stmt->execute($self->namespace());
    my $page_id;
    if (my @row = $get_stmt->fetchrow_array) {
    	($page_id) = @row;
    	croak 'Error! No page ID' if !defined $page_id;
    }
    else {
    	croak 'Could not get random page ID in namespace ' . $self->namespace;
    }

    say STDERR "page ID $page_id" if $self->verbose > 1;
    return $page_id;
}

# for compatibility with CMS::MediaWiki
sub getPage {
    my ($self, %arg) = @_;

    my $page_name = $arg{title};
    if (exists $arg{section}) {
	carp 'The "section" argument is currently not supported';
    }

    my $page_id         = $self->get_page_id($page_name);
    my $page_sourcecode = $self->get_latest_revision($page_id);

    my @lines = split /\n/, $page_sourcecode;
    return \@lines;
}

sub get_page_id {
    my ($self, $page_name) = @_;

    my $namespace = $self->namespace();
    $page_name = $self->my_encode($page_name);

    # TODO: resolve more namespaces (get the data from the wiki ...)
    if ($page_name ~~ /^(?:Template|Vorlage):(.*)$/) {
	$page_name = $1;
	$namespace = $self->template_namespace;
    }

    $page_name = whitespace_to_underscore_and_capitalize_start($page_name);

    my $db_handle = $self->db_handle();
    my $db_prefix = $self->prefix();
    my $get_stmt  = $db_handle->prepare(
					"SELECT page_id FROM ${db_prefix}page WHERE page_title=? AND page_namespace=?"
				       );
    say STDERR $get_stmt->{Statement} if $self->verbose > 2;
    $get_stmt->execute($page_name, $namespace);
    my $page_id;
    if (my @row = $get_stmt->fetchrow_array) {
    	($page_id) = @row;
    	croak 'Error! No page ID' if !defined $page_id;
    }
    else {
	$self->could_not_get_page_name($page_name, $namespace);
    }

    print "page ID $page_id\n" if $self->verbose() > 1;
    return $page_id;
}

sub get_direct_subcategories {
    my ($self, $category_name) = @_;

    $category_name = $self->my_encode($category_name);
    $category_name = whitespace_to_underscore_and_capitalize_start($category_name);
    say STDERR "Get direct subcategories for '$category_name'" if $self->verbose > 1;

    my $db_handle = $self->db_handle();
    my $db_prefix = $self->prefix();
    my $get_stmt  = $db_handle->prepare(
        "select page_id, page_title from ${db_prefix}categorylinks, ${db_prefix}page where cl_to=? and cl_from = page_id and page_namespace=?"
    );
    say STDERR $get_stmt->{Statement} if $self->verbose > 2;
    $get_stmt->execute($category_name, $self->category_namespace());
    my %subcategory_id = ();
    while (my @row = $get_stmt->fetchrow_array) {
    	my ($subcategory_id, $subcategory_name) = @row;
    	croak 'Error! No subcategory ID'   if !defined $subcategory_id;
    	croak 'Error! No subcategory name' if !defined $subcategory_name;

	$subcategory_name = $self->my_decode($subcategory_name);
    	$subcategory_id{$subcategory_name} = $subcategory_id;
    }
    return \%subcategory_id;
}

sub get_all_subcategories {
    my ($self, $category_name) = @_;

    say STDERR "Get all subcategories for '$category_name'" if $self->verbose > 1;

    my $subcategory_id_ref = $self->get_direct_subcategories($category_name);

    my %subcategory_to_visit = %$subcategory_id_ref;
    my %visited_subcategory  = ();
    while (scalar keys %subcategory_to_visit > 0) {
        foreach my $name (keys %subcategory_to_visit) {
            $visited_subcategory{$name} = $subcategory_to_visit{$name};
            delete $subcategory_to_visit{$name};
            my $new_subcategory_id_ref = $self->get_direct_subcategories($name);
            foreach my $new_name (keys %$new_subcategory_id_ref) {
                if (!exists $visited_subcategory{$new_name} && !exists $subcategory_to_visit{$new_name}) {
                    $subcategory_to_visit{$new_name} = $new_subcategory_id_ref->{$new_name};
                }
            }
        }
    }

    return \%visited_subcategory;
}

sub get_all_subcategories_graph {
    my ($self, $category_name) = @_;

    my $subcategory_id_ref = $self->get_direct_subcategories($category_name);

    my $graph = Graph->new(directed => 1);
    $graph->add_vertex($category_name);

    my %subcategory_to_visit = %$subcategory_id_ref;
    my %visited_subcategory  = ();
    foreach my $direct_subcategory_name (keys %subcategory_to_visit) {
        $graph->add_edge($direct_subcategory_name => $category_name);
    }
    while (scalar keys %subcategory_to_visit > 0) {
        foreach my $name (keys %subcategory_to_visit) {
            $visited_subcategory{$name} = $subcategory_to_visit{$name};
            delete $subcategory_to_visit{$name};
            my $new_subcategory_id_ref = $self->get_direct_subcategories($name);
            foreach my $new_name (keys %$new_subcategory_id_ref) {
                $graph->add_edge($new_name => $name);
                if (!exists $visited_subcategory{$new_name} && !exists $subcategory_to_visit{$new_name}) {
                    $subcategory_to_visit{$new_name} = $new_subcategory_id_ref->{$new_name};
                }
            }
        }
    }
    return $graph;
}

sub get_number_of_pages_in_category {
    # TODO: could be queried directly ...
    my ($self, $category_name) = @_;

    my $page_ids_ref = $self->get_category_page_ids($category_name);

    return scalar @$page_ids_ref;
}

sub get_category_page_ids {
    my ($self, $category_name) = @_;

    $category_name = $self->my_encode($category_name);
    $category_name = whitespace_to_underscore_and_capitalize_start($category_name);

    my $db_handle = $self->db_handle();
    my $db_prefix = $self->prefix();
    my $get_stmt  = $db_handle->prepare(qq[
        SELECT cl.cl_from
        FROM ${db_prefix}categorylinks AS cl, ${db_prefix}page AS p
        WHERE cl.cl_to=? AND cl.cl_from=p.page_id AND page_namespace=?
    ]);
    say STDERR $get_stmt->{Statement} if $self->verbose > 2;
    $get_stmt->execute($category_name, $self->namespace());

    my @page_ids = ();
    foreach my $row_ref (@{$get_stmt->fetchall_arrayref}) {
        push @page_ids, ($row_ref->[0]);
    }
    return \@page_ids;
}

sub report_errors {
    my ($self) = @_;

    $self->report_page_id_errors();
}

sub report_page_id_errors {
    my ($self) = @_;

    my $number_of_errors = scalar @{$self->error_page_id};

    if ($number_of_errors) {
	say STDERR "Could not get $number_of_errors pages.";
	say STDERR (join ', ', @{$self->error_page_id});
    }
}

sub could_not_get_page_id {
    my ($self, $page_id) = @_;

    carp "Could not get text for page with ID '$page_id'";
    push @{$self->error_page_id()}, $page_id;
}

sub could_not_get_page_name {
    my ($self, $page_name, $namespace) = @_;

    carp "Could not get page ID for '$page_name' in namespace $namespace";
}

# TODO: maybe move somewhere else ...
sub whitespace_to_underscore_and_capitalize_start {
    my ($string) = @_;

    $string =~ s{\s}{_}g;
    return ucfirst $string;
}

sub my_encode {
    my ($self, $text) = @_;

    if (utf8::is_utf8($text)) {
	$text = Encode::encode($self->encoding, $text);
    }

    return $text;
}

sub my_decode {
    my ($self, $text) = @_;

    if (! utf8::is_utf8($text)) {
	$text = Encode::decode($self->encoding, $text);
    }

    return $text;
}

=head1 AUTHOR

Zeno Gantner <zeno.gantner@gmail.com> is the author.

=head1 ACKNOWLEDGEMENTS


=head1 BUGS

none

=head1 TODO

=over 4

=back

=head1 COPYRIGHT & LICENSE

 Copyright (c) 2008, 2009 Zeno Gantner

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

no Moose; 1; # end of MediaWiki::Backend
