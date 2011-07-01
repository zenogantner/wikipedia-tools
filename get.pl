#!/usr/bin/perl

# Get article from local MediaWiki database
#
# Copyright (c) 2008, 2009 by Zeno Gantner <zeno.gantner@gmail.com>
# Licensed under the terms of GNU GPL 3 or later

use strict;
use warnings;
use utf8; # ä
use 5.10.1;

use Carp;
use English; $OUTPUT_AUTOFLUSH = 1;
use Getopt::Long;

use MediaWiki::Backend;
use MediaWiki::Backend::Defaults;
use Text::Util;

my $debug     = 0;
my $verbose   = 0;
my $namespace = 0;

GetOptions(
	   'help'        => \(my $help        = 0),
	   'debug+'      => \$debug,
	   'verbose+'    => \$verbose,
	   'check'       => \(my $check),
	   'database=s'  => \(my $database    = ''),
	   'db-prefix=s' => \(my $db_prefix   = ''),
	   'host=s'      => \(my $db_host            = $WP_DB_HOST),
	   'user=s'      => \(my $db_user            = $WP_DB_USER),
	   'password=s'  => \(my $db_password        = $WP_DB_PASSWORD),
	   'language=s'  => \(my $language    = 'de'),
	   'category'    => \(my $category    = 0),
	   'page-id'     => \(my $page_id     = 0),
	   'names'       => \(my $show_names  = 0),
	   'random'      => \(my $random      = 0),
	   'separator'   => \(my $separator   = 0),
	   'hypernyms'   => \(my $include_hypernyms = 0),  # TODO implement
	   'show-id'     => \(my $show_id = 0),
	   'all'         => \(my $all_subcategories  = 0), # TODO: make sure it is used in conjunction with --category
	  ) or usage(-1);

if ($help) {
    usage(0);
}

my $argument = shift;

if ($language && !$database) {
    $database = $language . 'wiki';
}

my $wp = MediaWiki::Backend->new(
    host      => $db_host,
    user      => $db_user,
    password  => $db_password,
    database  => $database,
    prefix    => $db_prefix,
    namespace => $namespace,
);
$wp->init_db_handle();

if ($random) {
    $argument = ''; # TODO check whether this really works
}

if (defined $argument) {
    my @page_ids = ();

    if ($category) {
	my @category_names = ($argument);
	if ($all_subcategories) {
	    my $category_id_ref = $wp->get_all_subcategories($argument);
	    push @category_names, keys %$category_id_ref;
	}
	foreach my $category_name (@category_names) {
	    push @page_ids, @{$wp->get_category_page_ids($category_name)};
	}
	# remove duplicates
	my %page_id_hash = map { $_, 1 } @page_ids;
	@page_ids = keys %page_id_hash;
    }
    elsif ($page_id) {
        push @page_ids, $argument;
    }
    elsif ($random) {
        push @page_ids, $wp->get_random_page_id();
    }
    else {
        $argument =~ s{[ ]}{_}xmsg;
        push @page_ids, $wp->get_page_id($argument);
    }

    PAGE_ID:
    foreach my $page_id (@page_ids) {
	if ($show_id) {
	    say $page_id;
	    next PAGE_ID;
	}

        my $text = $wp->get_latest_revision($page_id);

        say '>>>>START ARTICLE<<<<' if $separator;
        if (!$check) {
            $text = remove_categories($text);
            $text = remove_interwiki_links($text);
            say $text;
        }
        else {
            $text = remove_categories($text);
            $text = remove_interwiki_links($text);

            if (length $text < 20) {
                say "Page with ID $page_id is very short: >>>>$text<<<<";
            }
            else {
                say "Length: " . (length $text);
                say ">>>>$text<<<<";
            }
        }
        say '>>>>END ARTICLE<<<<' if $separator;
    }
}
else {
    usage(-1);
}


# TODO: move the cleaning procedures into a module
# also in WDG::Extractor::Util --> combine that!
sub remove_categories {
    my ($text) = @_;

    my $no_brackets         = qr/[^\[\]]/;
    my $no_brackets_no_pipe = qr/[^\[\]|]/;

    $text =~ s/\[\[
                (?:Kategorie|Category):          # TODO: other languages
                ($no_brackets_no_pipe+)
                (?:\|($no_brackets_no_pipe*))?
                \]\]
              //xg;

    return trim($text);
}

sub remove_interwiki_links {
    my ($text) = @_;

	my $no_brackets         = qr/[^\[\]]/;
	my $no_brackets_no_pipe = qr/[^\[\]|]/;

    $text =~ s/\[\[
                (?:\w{2,3}|simple|bat-smg|nds-nl|be-x-old|zh-yue|map-bms|zh-min-nan|fiu-vro|roa-rup):   # TODO: create this from a list
                ($no_brackets_no_pipe+)
                \]\]
              //xg;

    $text =~ s/
              \{\{
              Link
              \s
              FA
              \|
              (?:\w{2,3}|simple)
               \}\}
             //xg;

    return trim($text);
}

sub usage {
    my ($return_code) = @_;

    print << "END";
Get article from local MediaWiki database

usage: $PROGRAM_NAME [OPTIONS] article|category|page_id

    --help                              display this usage information
    --verbose                           increment verbosity level by one
    --debug                             increment debug level by one
    --check
    --host=HOST                         name or IP address of the database server, default: '$WP_DB_HOST'
    --user=USER                         database user name, default: '$WP_DB_USER'
    --password=PW                       database password, default: '$WP_DB_PASSWORD'
    --db-prefix=PREFIX
    --language=LANG
    --category                          interpret parameter as category name
    --page-id                           interpret parameter as page ID
    --names
    --random                            get random wiki page
    --separator                         separate different articles
    --hypernyms                         (not implemented yet)
    --show-id                           show only page IDs, not the page text
    --all
END
    exit $return_code;
}

