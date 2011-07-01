#!/usr/bin/perl

# Extract all articles of one category, store them in the archive directory and generate a list of article IDs
#
# Copyright (c) 2008, 2009 by Zeno Gantner <zeno.gantner@gmail.com>
# Licensed under the terms of GNU GPL 3 or later

# TODO: make sure umlauts work from the command line

use strict;
use warnings;
use utf8; # ä
binmode STDOUT, ':utf8';
binmode STDERR, ':utf8';
use 5.10.1;

use Carp;
use Encode;
use English; $OUTPUT_AUTOFLUSH = 1;
use Error qw(:try);
use File::Slurp;
use Getopt::Long;

use MediaWiki::Utilities;
use MediaWiki::Backend;
use MediaWiki::Backend::Defaults;
use Text::Util;

my $LANGUAGE                                   = 'de';
my $DEFAULT_MINIMUM_NUMBER_OF_CATEGORY_MEMBERS = 1;

my @filters = (
    \&remove_categories,
    \&remove_interwiki_links,
    \&remove_personendaten_structure,
);

my $debug   = 0;
my $verbose = 0;

my $main_namespace = 0;

GetOptions(
	   'help'            => \(my $help               = 0),
	   'debug+'          => \$debug,
	   'verbose+'        => \$verbose,
	   'host=s'          => \(my $db_host            = $WP_DB_HOST),
	   'database=s'      => \(my $database           = ''),
	   'user=s'          => \(my $db_user            = $WP_DB_USER),
	   'password=s'      => \(my $db_password        = $WP_DB_PASSWORD),
	   'db-prefix=s'     => \(my $db_prefix          = ''),
	   'language=s'      => \(my $language           = $LANGUAGE),
	   'dir=s'           => \(my $directory          = '.'),
	   'cat-namespace=i' => \(my $category_namespace = 14),
	   'subcat'          => \(my $get_subcategories  = 0),
	   'min-members=i'   => \(my $minimum_number_of_category_members = $DEFAULT_MINIMUM_NUMBER_OF_CATEGORY_MEMBERS),
	   'category-file=s' => \(my $category_file      = ''),
	   'write-articles!' => \(my $write_articles     = 1),
	  ) or usage(-1);

usage(0) if $help;


my @categories = @ARGV;
my %categories = map { $_ => 1 } @categories;

if ($language && !$database) {
    $database = $language . 'wiki';
}

my $wp = MediaWiki::Backend->new(
				 host      => $db_host,
				 user      => $db_user,
				 password  => $db_password,
				 database  => $database,
				 prefix    => $db_prefix,
				 namespace => $main_namespace,
				);
$wp->init_db_handle();

if ($get_subcategories) {
    print STDERR "Getting subcategory information ... " if $verbose;
    foreach my $category (@categories) {
        my $subcategory_id_ref = $wp->get_all_subcategories($category);
        foreach my $subcategory (keys %$subcategory_id_ref) {
	    $categories{$subcategory} = 1;
	}
    }
    my $num_subcats = (scalar keys %categories) - (scalar @ARGV);
    say STDERR "done ($num_subcats)." if $verbose;
}

my %categories_by_page_id = ();
my $category_counter      = 0;

CATEGORY:
foreach my $category (sort keys %categories) {
    if ($category =~ /\//xms) {
	say STDERR "ignore category '$category'";
	next CATEGORY;
    }

    my @page_ids = @{$wp->get_category_page_ids($category)};
    my $number_of_positive_examples = scalar @page_ids;
    print STDERR "$category ($number_of_positive_examples) ... ";

    if ($number_of_positive_examples < $minimum_number_of_category_members) {
        say STDERR "skipped category '$category': not enough members";
        next CATEGORY;
    }

    $category_counter++;

    write_file(
	       "$directory/categories/$category",
	       {binmode => ':utf8', err_mode => 'croak'},
	       (join "\n", @page_ids)
	      );
    foreach my $page_id (@page_ids) {
	  if (exists $categories_by_page_id{$page_id}) {
	      push @{$categories_by_page_id{$page_id}}, $category;
	  }
	  else {
	      $categories_by_page_id{$page_id} = [$category];
	  }
    }
    print STDERR "\n";
}
say STDERR "$category_counter categories.";

if ($write_articles) {
    say STDERR 'Getting page texts ...';
    my $page_counter = 0;
  PAGE:
    foreach my $page_id (sort keys %categories_by_page_id) {
	my $text =
	  try {
	      return $wp->get_latest_revision($page_id);
	  }
          catch Error with {
	      say STDERR "Could not get page '$page_id' -- check your database!";
	      return '';
	  };

	next PAGE if $text eq '';

	# clean article source code
	foreach my $filter_coderef(@filters) {
	    $text = &$filter_coderef($text);
	}

	# write article text
	write_file(
		   "$directory/articles/$page_id.txt",
		   {binmode => ':utf8', err_mode => 'croak'},
		   $text
		  );
	# write category mappings for article
	write_file(
		   "$directory/category_mappings/$page_id.cats",
		   {binmode => ':utf8', err_mode => 'croak'},
		   (join "\n", @{$categories_by_page_id{$page_id}})
		  );

	# report to STDERR
	say   STDERR $page_id if $verbose > 1;
	print STDERR '.'      if ($verbose == 1) and ($page_counter % 50 == 1);

	$page_counter++;
    }
    say STDERR "Wrote $page_counter pages";
}

# save categories_by_page_id to one file
if ($category_file) {
    open(my $FH, '>:encoding(utf8)', $category_file) or croak "$! $category_file";
    foreach my $page_id (keys %categories_by_page_id) {
	foreach my $category (@{$categories_by_page_id{$page_id}}) {
	    say $FH "$page_id\t$category";
	}
    }
}

$wp->report_errors();


sub usage {
    my ($return_code) = @_;

print << "END";
Extract all articles of one category and store them in a directory

usage: $PROGRAM_NAME [OPTIONS] category1 category2 ...

    --help                              display this usage information
    --verbose                           increment verbosity level by one
    --debug                             increment debug level by one
    --host=HOST                         default '$WP_DB_HOST'
    --database=DB                       default '${language}wiki'
    --user=USER                         default '$WP_DB_USER'
    --password=PW                       default '$WP_DB_PASSWORD'
    --db-prefix=PREFIX                  default ''
    --language=LANG                     default '$LANGUAGE'
    --dir=DIRECTORY                     store the articles in DIRECTORY (default is .)
    --cat-namespace=I                   the integer I is the ID of the category namespace
    --subcat                            also extract subcategories of the given categories
    --category-file=FILE                save category information to FILE (default ''))
    --min-members=I                     default $DEFAULT_MINIMUM_NUMBER_OF_CATEGORY_MEMBERS
    --no-write-articles                 don't write article texts to disk
END
    exit $return_code;
}
