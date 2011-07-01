#!/usr/bin/perl

# Get subcategories of a given category
#
# Copyright (c) 2009 by Zeno Gantner <zeno.gantner@gmail.com>
# Licensed under the terms of GNU GPL 3 or later

# TODO: make sure umlauts work from the command line

use strict;
use warnings;
use utf8; # ä
binmode STDIN,  ':utf8';
binmode STDOUT, ':utf8';
binmode STDERR, ':utf8';
use open OUT => ':utf8';
use 5.10.0;

use Carp;
use English; $OUTPUT_AUTOFLUSH = 1;
use Getopt::Long;

use MediaWiki::Backend;
use MediaWiki::Backend::Defaults;

my $debug   = 0;
my $verbose = 0;

my $LANGUAGE                                   = 'de'; # TODO: move those into a module?
my $DEFAULT_MINIMUM_NUMBER_OF_CATEGORY_MEMBERS = 1;

GetOptions(
	   'help'            => \(my $help               = 0),
	   'debug+'          => \$debug,
	   'verbose+'        => \$verbose,
	   'database=s'      => \(my $database           = ''),
	   'db-prefix=s'     => \(my $db_prefix          = ''),
	   'host=s'          => \(my $db_host            = $WP_DB_HOST),
	   'user=s'          => \(my $db_user            = $WP_DB_USER),
	   'password=s'      => \(my $db_password        = $WP_DB_PASSWORD),
	   'language=s'      => \(my $language           = $LANGUAGE),
	   'cat-namespace=i' => \(my $category_namespace = 14),
	   'all'             => \(my $all_subcategories  = 0),
	   'show-id!'        => \(my $show_id            = 1),
	   'show-name!'      => \(my $show_name          = 1),
	   'category-file=s' => \(my $category_filename  = ''),
	   'min-members=i'   => \(my $minimum_number_of_category_members = $DEFAULT_MINIMUM_NUMBER_OF_CATEGORY_MEMBERS),
	  ) or usage(-1);

if ($help) {
    usage(0);
}

my $top_category = shift;
if (! defined $top_category) {
    say STDERR 'Category not defined.';
    usage(-1);
}

if ($language && !$database) {
    $database = $language . 'wiki';
}

my $wp = MediaWiki::Backend->new(
				 host                => $db_host,
				 user                => $db_user,
				 password            => $db_password,
				 database            => $database,
				 prefix              => $db_prefix,
				 category_namesspace => $category_namespace,
				 verbose             => $verbose,
);
$wp->init_db_handle();

if (! utf8::is_utf8($top_category)) {
    eval {
	$top_category = Encode::decode_utf8($top_category, Encode::FB_CROAK);
    }; # question: why the hell is the command line input _NOT_ marked as utf8?
}
say $top_category;
my $subcategory_id_ref = $all_subcategories
  ? $wp->get_all_subcategories($top_category)
  : $wp->get_direct_subcategories($top_category);
foreach my $name (sort keys %$subcategory_id_ref) {
    if ($show_id && $show_name) {
	say "$subcategory_id_ref->{$name}\t$name";
    }
    elsif ($show_id) {
	say $subcategory_id_ref->{$name};
    }
    elsif ($show_name) {
	say $name;
    }
    else {
	croak 'please select either ID or name to be shown';
    }
}

if ($category_filename) {
    open my $CATEGORY_FILE, '>', $category_filename
      or croak "Could not open file '$category_filename' for writing: '$ERRNO'";

    my $graph = $wp->get_all_subcategories_graph($top_category);
    my @interior_vertices = sort $graph->interior_vertices();
    my @leaf_vertices     = sort $graph->source_vertices();

#    say $CATEGORY_FILE 'dag? '      . ($graph->is_dag() ? 'yes' : 'no');
#    say $CATEGORY_FILE 'leaves: '   . (join ' ', @leaf_vertices);
#    say $CATEGORY_FILE 'root: '     . (join ' ', $graph->sink_vertices);
#    say $CATEGORY_FILE 'interior: ' . (join ' ', @interior_vertices);
#    say $CATEGORY_FILE 'number: '   . scalar @interior_vertices + scalar @leaf_vertices + 1;

    # add explicit LEAF categories for each inner node
    foreach my $interior_vertex (sort ($top_category, @interior_vertices)) {
	my $new_vertex = "${interior_vertex}_LEAF";
	$graph->add_edge($new_vertex => $interior_vertex);
    }

    # delete top category (it is not a valid label for our learning problem)
    $graph->delete_vertex($top_category);

    # give out all supercategories
  CATEGORY:
    foreach my $category (sort $graph->vertices()) {
	my $my_category = $category;
           $my_category =~ s/_LEAF$//;
	my $number_of_category_members = $wp->get_number_of_pages_in_category($my_category);
	next CATEGORY if $number_of_category_members < $minimum_number_of_category_members;

	my @successors = sort $graph->all_successors($category);
	say $CATEGORY_FILE $category . ': ' . (join ' ', @successors);
    }
    close $CATEGORY_FILE;
}

sub usage {
    my ($return_code) = @_;

    print << "END";
Get subcategories of a given category

usage: $PROGRAM_NAME [OPTIONS] category

    --help                              display this usage information
    --verbose                           increment verbosity level by one
    --debug                             increment debug level by one
    --database=DB                       name of the database
    --host=HOST                         name or IP address of the database server, default '$WP_DB_HOST'
    --user=USER                         database user name, default '$WP_DB_USER'
    --password=PW                       database password, default '$WP_DB_PASSWORD'
    --db-prefix=PREFIX                  prefix of the database table names
    --language=LANG                     language, default '$LANGUAGE'
    --all
    --no-show-name
    --no-show-id
    --category-file=FILENAME
    --min-members=I                     default $DEFAULT_MINIMUM_NUMBER_OF_CATEGORY_MEMBERS; only in combination with --category-file
END
    exit $return_code;
}
