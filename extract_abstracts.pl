#!/usr/bin/perl

=head1 NAME

extract_abstracts.pl -- quick and dirty abstract extractor derived from
mwimport -- quick and dirty mediawiki importer

=head1 SYNOPSIS

cat pages.xml | extract_abstracts.pl [-s N|--skip=N] [-l LANG|--language=LANG]

=cut

use strict;
use warnings;
use encoding 'utf8'; #ä

use Getopt::Long;
use Pod::Usage;
use Carp;

use lib "$ENV{HOME}/software/mediawiki-tools/";
use MediaWiki::Utilities qw{ extract_abstract remove_HTML_comments mediawiki2plaintext};

my ($cnt_rev, %namespace, $ns_pattern);
my $page_counter = 0;
my $abstract_counter = 0;
#my $committed = 0;
my $skip = 0;
my $no_action = 0;

## set this to 1 to match "mwdumper --format=sql:1.5" as close as possible
#sub Compat() { 0 }

sub textify($) {
  my $l;
  for ($_[0]) {
    if (defined $_) {
      s/&quot;/"/ig;
      s/&lt;/</ig;
      s/&gt;/>/ig;
      /&(?!amp;)(.*?;)/ and die "textify: does not know &$1";
      s/&amp;/&/ig;
      $l = length $_;
      s/\\/\\\\/g;
      s/\n/\\n/g;
      s/'/\\'/ig;
#      Compat and s/"/\\"/ig;
      $_ = "'$_'";
    } else {
      $l = 0;
      $_ = "''";
    }
  }
  return $l;
}

sub getline()
{
  $_ = <>;
  defined $_ or die "eof at line $.\n";
}

sub ignore_elt($)
{
  m|^\s*<$_[0]>.*?</$_[0]>\n$| or die "expected $_[0] element in line $.\n";
  getline;
}

sub simple_elt($$)
{
  if (m|^\s*<$_[0]\s*/>\n$|) {
    $_[1]{$_[0]} = '';
  } elsif (m|^\s*<$_[0]>(.*?)</$_[0]>\n$|) {
    $_[1]{$_[0]} = $1;
  } else {
    die "expected $_[0] element in line $.\n";
  }
  getline;
}

sub simple_opt_elt($$)
{
  if (m|^\s*<$_[0]\s*/>\n$|) {
    $_[1]{$_[0]} = '';
  } elsif (m|^\s*<$_[0]>(.*?)</$_[0]>\n$|) {
    $_[1]{$_[0]} = $1;
  } else {
    return;
  }
  getline;
}

sub opening_tag($)
{
  m|^\s*<$_[0]>\n$| or die "expected $_[0] element in line $.\n";
  getline;
}

sub closing_tag($)
{
  m|^\s*</$_[0]>\n$| or die "$_[0]: expected closing tag in line $.\n";
  getline;
}

sub si_nss_namespace()
{
  m|^\s*<namespace key="(-?\d+)"\s*/>()\n|
    or m|^\s*<namespace key="(-?\d+)">(.*?)</namespace>\n|
    or die "expected namespace element in line $.\n";
  $namespace{$2} = $1;
  getline;
}

sub si_namespaces() {
  opening_tag('namespaces');
  eval {
    while (1) {
      si_nss_namespace;
    }
  };
  # note: $@ is always defined
  $@ =~ /^expected namespace element / or die "namespaces: $@";
  $ns_pattern = '^('.join('|',map { quotemeta } keys %namespace).'):';
  closing_tag('namespaces');
}


sub siteinfo() {
  opening_tag('siteinfo');
  eval {
    my %site;
    simple_elt sitename => \%site;
    simple_elt base => \%site;
    simple_elt generator => \%site;
    $site{generator} =~ /^MediaWiki 1.9alpha$/ or warn "siteinfo: untested ",
      "generator '$site{generator}', expect trouble ahead\n";
    simple_elt case => \%site;
    si_namespaces;
    print "-- MediaWiki XML dump converted to SQL by mwimport

-- Site: $site{sitename}
-- URL: $site{base}
-- Generator: $site{generator}
-- Case: $site{case}
--
-- Namespaces:
",map { "-- $namespace{$_}: $_\n" }
  sort { $namespace{$a} <=> $namespace{$b} } keys %namespace;
  };
  $@ and die "siteinfo: $@";
  closing_tag("siteinfo");
}

sub pg_rv_contributor($)
{
  opening_tag "contributor";
  my %c;
  eval {
    simple_elt username => \%c;
    simple_elt id => \%c;
    $_[0]{contrib_user} = $c{username};
    $_[0]{contrib_id}   = $c{id};
  };
  if ($@) {
    $@ =~ /^expected username element / or die "contributor: $@";
    eval {
      simple_elt ip => \%c;
      $_[0]{contrib_user} = $c{ip};
    };
    $@ and die "contributor: $@";
  }
  closing_tag "contributor";
}

sub pg_rv_comment($)
{
  if (m|^\s*<comment\s*/>\s*\n|) {
    getline;
  } elsif (s|^\s*<comment>([^<]*)||g) {
    while (1) {
      $_[0]{comment} .= $1;
      last if $_;
      getline;
      s|^([^<]*)||;
    }
    closing_tag "comment";
  } else {
    return;
  }
}

sub pg_rv_text($)
{
  if (m|^\s*<text xml:space="preserve"\s*/>\s*\n|) {
    $_[0]{text} = '';
    getline;
  } elsif (s|^\s*<text xml:space="preserve">([^<]*)||g) {
    while (1) {
      $_[0]{text} .= $1;
      last if $_;
      getline;
      s|^([^<]*)||;
    }
    closing_tag "text";
  } else {
    die "expected text element in line $.\n";
  }
}

sub pg_revision($) {
  my $rev = {};
  opening_tag "revision";
  eval {
    my %revision;
    simple_elt id => $rev;
    simple_elt timestamp => $rev;
    pg_rv_contributor $rev;
    simple_opt_elt minor => $rev;
    pg_rv_comment $rev;
    pg_rv_text $rev;
  };
  $@ and die "revision: $@";
  push @{$_[0]{rev}}, $rev;
  closing_tag "revision";
}


sub page($) {

	#print "call to page!\n";

	opening_tag 'page';
	my %page;
	eval {
		simple_elt title => \%page;
		simple_elt id => \%page;
		simple_opt_elt restrictions => \%page;
		pg_revision \%page;
	};
  	if ($@) {
		die "page: $@";
	}
	closing_tag 'page';

	my $ns;
	if ($page{title} =~ s/$ns_pattern//o) {
		$ns = $namespace{$1};
	} else {
		$ns = 0;
	}

	# TODO: filter namespaces

	$page{title} =~ y/ /_/; # check what is happening here ... TODO

	$page{redirect} = $page{rev}[0]{text} =~ /^#REDIRECT /i ? 1 : 0;


	if ($skip) {
		--$skip;
	}
	else {
		$page{id} =~ /^\d+$/
			or warn "page '$page{title}': bogus id '$page{id}'\n";

		foreach (@{$page{rev}}) { # TODO: get rid of this loop
			$$_{id} =~ /^\d+$/
				or warn "page '$page{title}': ignoring bogus revision id '$$_{id}'\n",
				next;
      
			if ($page{redirect} ) {
			#	$_[0] .= "-- Ignore redirect '$page{title}'\n";
			#	# TODO: count redirects??
			}
			elsif ($ns != 0) {
			#	$_[0] .= "-- Ignore namespace $ns '$page{title}'\n";
			}
			elsif ($no_action == 0) {

				# create abstract:
				my $plaintext = remove_HTML_comments($$_{text});
				$plaintext = mediawiki2plaintext($plaintext);
				my $abstract = extract_abstract($plaintext);
				textify $abstract;

				textify $page{title};
      
				$_[0] .= 'REPLACE INTO wikipedia.TagAbstract (TagID, Abstract) '
					. "VALUES ((SELECT (ID) FROM Tag WHERE BINARY Text=$page{title}), $abstract);\n";

				++$abstract_counter;
  			}
			++$page_counter;
		}
	}
}

my $start = time;

sub stats() {
	my $s = time - $start;
	$s ||= 1; # ???
	printf STDERR "%9d pages (%7.3f/s) %9d abstracts (%7.3f/s) in %d seconds\n",
	$page_counter, $page_counter/$s, $abstract_counter, $abstract_counter/$s, $s;
}


sub flush($) {
	$_[0] or return;
	$_[0] =~ s/,\n?$//;
 
	print $_[0];

	$_[0] = ''; 
}

sub terminate {
  print STDERR "terminated by SIG$_[0]\n";
  exit 1;
}

my $schema_ver = '0.3';
my $schema_loc = "http://www.mediawiki.org/xml/export-$schema_ver/";
my $schema     = "http://www.mediawiki.org/xml/export-$schema_ver.xsd";
my $language   = 'en'; 

my $help;
GetOptions(
	'skip=i'     => \$skip,
	'language=s' => \$language,
    'help'       => \$help,
	'no-action'  => \$no_action,
) or pod2usage(2);
$help and pod2usage(1);

getline;
$_ eq qq(<mediawiki xmlns="$schema_loc").
  qq( xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance").
  qq( xsi:schemaLocation="$schema_loc $schema" version="$schema_ver").
  qq( xml:lang="$language">\n) or die "unknown schema or invalid first line\n";
getline;
$SIG{TERM} = $SIG{INT} = \&terminate;
siteinfo();
my $text = '';
eval {
	while (1) {
		page $text;
#		if (length $text > 512*1024) {
			flush $text;
#		}
		
		if ($page_counter % 1000 == 0 && $page_counter > 0) {
			stats();
		}
	}
};
flush $text;
stats;
m|</mediawiki>| or die "mediawiki: expected closing tag in line $.\n";

=head1 COPYRIGHT

Copyright 2007 by Robert Bihlmeyer

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

You may also redistribute and/or modify this software under the terms
of the GNU Free Documentation License without invariant sections, and
without front-cover or back-cover texts.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
