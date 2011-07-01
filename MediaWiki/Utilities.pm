use strict;
use warnings;
use utf8; # ä
binmode STDOUT, ':utf8';
binmode STDERR, ':utf8';

package MediaWiki::Utilities;

use Regexp::Common qw(URI);

use Text::Util;


# TODO
#   rename? actually we perform actions on MediaWiki markup (look for a good namespace)
#   think about optimizations -- does it make sense to have references instead of scalars?
#   this module cries for unit tests
#   reuse regular expressions among functions

use base 'Exporter';
our @EXPORT = qw{
    remove_HTML_comments
    lang_abbr
    remove_categories
    remove_headlines
    remove_headline_markup
    remove_images
    remove_interwiki_links
    remove_math_markup
    remove_mediawiki_emphasis
    remove_mediawiki_links
    remove_mediawiki_directives
    remove_paran_pairs
    remove_personendaten_structure
    remove_tables
    remove_templates
    remove_unnecessary_whitespace
    mediawiki2plaintext
};
# TODO: export only what is actually needed outside
our @EXPORT_OK = qw{ remove_parantheses extract_abstract};


# TODO: rename
my @LANGUAGES = qw(
	ahd lat dt engl jap mhd
	bzw
	op
);


# Thresholds for extract_abstract:
my $ABSTRACT_MIN_CHARACTERS = 250;
my $ABSTRACT_MAX_CHARACTERS = 450;
#my $ABSTRACT_WARN_CHARACTERS = 100;

# TODO: test
sub extract_abstract {
	my ($text) = @_;

	# get positions of the dots in the text
	my $dotindex = -1;
	my @dotindex;		
	DOT:
	for my $i (0 .. 14) {
		$dotindex = index($text, '.', $dotindex + 1);
		if ($dotindex != -1) {
			if (! lang_abbr($text, $dotindex) ) {
				push @dotindex, $dotindex;
			}
		} else {
			last DOT;
		}
	}

	my $abstract;

	# find position of a good full stop
	my $position;
	undef $position;
	POS:
	for my $i (0 .. 14) {
		last POS if !defined $dotindex[$i];

		if ($dotindex[$i] > $ABSTRACT_MIN_CHARACTERS) {
			if ($dotindex[$i] < $ABSTRACT_MAX_CHARACTERS) {
				$position = $dotindex[$i];
			}
			else {
				last POS;
			}
		}
	}
	
	if (defined $position) {
		$abstract = substr($text, 0, $position + 1);
	}
	else {
		$abstract = substr($text, 0, $ABSTRACT_MAX_CHARACTERS - 50);
		$abstract =~ s/(\s+\S+)$//gmxi; # remove (possible) rest of word plus whitespace characters from the end
	}
	
	return $abstract;
}

# TODO: test
# TODO: maybe use something from the Modulhandbuch code instead ...
sub mediawiki2plaintext {
	my ($text, $arg_ref) = @_;

	my $remove_headlines = 0;
	if (defined $arg_ref) {
		$remove_headlines = defined $arg_ref->{remove_headlines} ? $arg_ref->{remove_headlines} : 0;
	}

	$text = remove_images($text);
	$text = remove_templates($text);

	# TODO: move this up?
	if ($remove_headlines) {
		$text = remove_headline_markup($text);
	} else {
		$text = remove_headlines($text);
	}

	$text = remove_tables($text);

	$text = remove_categories($text);
	$text = remove_interwiki_links($text);
	$text = remove_mediawiki_links($text); # TODO: rename? we don't remove the links completely

	$text = remove_mediawiki_emphasis($text);
	$text = remove_mediawiki_directives($text);

	# cleanup
	$text =~ s/\([;,]/(/g;          # '(,' -> '(', '(;' -> '(')
	$text = remove_paran_pairs($text);
	$text = remove_unnecessary_whitespace($text); # TODO: this may not be always the best, but for abstracts it is OK
	
	return $text;
}

# TODO: test
sub remove_math_markup {
	my ($text) = @_;

	$text = remove_parantheses($text, '<math>', '</math>');

	return $text;
}

# TODO: test
# watch out! Images have to be removed from the text before this function can be called
# TODO: ignore images and templates
sub remove_mediawiki_links {
	my ($text) = @_;

	$text =~ s/\[\[             # start
		   (?:[^\[\[|]+\|)?  # maybe a link target
	           ([^\[\]]+)       # keep the caption
		   \]\]             # end
		 /$1/gmxs;
	# TODO: more sophisticated?

	$text =~ s/\[$RE{URI}\s*([^\]]*)\]/$1/gmxs;

	$text =~ s/$RE{URI}//gmxs;

	return $text;
}

# TODO: test
sub remove_mediawiki_emphasis {
	my ($text) = @_;

	$text =~ s/'''//gmxi;
	$text =~ s/''//gmxi;

	return $text;
}

# TODO: test
sub remove_mediawiki_directives {
	my ($text) = @_;

	$text =~ s/__NO_TOC__//g;

	return $text;
}


# TODO: test
# TODO: Variant that keeps MediaWiki layout semantics
#       also export it, don't use it in every subroutine here
#       the non-MediaWiki-specific version should be in another Module
#       is there an alternative in CPAN?
sub remove_unnecessary_whitespace {
	my ($text) = @_;

	# look a certain interpunctation marks
	$text =~ s/\s([,.!?:])/$1/gmxs;
	$text =~ s/\(\s/(/gmxs;
	
	# TODO: think about what happens to newlines ...
	$text =~ s/\s+/ /gmxs;	# remove double whitespace
	$text =~ s/\A\s//gmxs;   # remove leading
	$text =~ s/\s\z//gmxs;   #    and trailing whitespaces

	return $text;
}

# TODO: test
sub remove_headlines {
	my ($text) = @_;

	my $start = qr{ \n?^ }xms;

	$text =~ s/ $start =====[^=]+=====//gxms;
	$text =~ s/ $start ====[^=]+====//gxms;
	$text =~ s/ $start ===[^=]+===//gxms;
	$text =~ s/ $start ==[^=]+==//gxms;
	$text =~ s/ $start =[^=]+=//gxms;

	return $text;
}

# TODO: test
sub remove_headline_markup {
	my ($text) = @_;
	# TODO: specify different levels

	my $middle_part = qr{ \s*(\b[^=]+\b)\s* }xms; # actually, using \b is quite dangerous ...

	$text =~ s/^===== $middle_part =====/$1/gxms;
	$text =~ s/^==== $middle_part ====/$1/gxms;
	$text =~ s/^=== $middle_part ===/$1/gxms;
	$text =~ s/^== $middle_part ==/$1/gxms;
	$text =~ s/^= $middle_part =/$1/gxms;

	return $text;
}

#sub remove_HTML_comments {
	#my ($text) = @_;

	#$text =~ s/<!--.*-->//gmxi;

	#return $text;
#	return '';
#}

# TODO: test
sub remove_templates {
	my ($text) = @_;

	$text = remove_parantheses($text, '{{', '}}');

	return $text;
}

# TODO: test
sub remove_tables {
	my ($text) = @_;

	$text = remove_parantheses($text, '{|', '|}');

	return $text;
}


# TODO: i18n, test
sub remove_images {
	my ($text) = @_;

# TODO: think about lower case bild:

	$text =~ s/<gallery>//g; # recursively??
	$text =~ s/<\/gallery>//g;

	$text =~ s/\[\[[Ii]mage:/[[Bild:/g;
	$text =~ s/\[\[bild:/[[Bild:/g;

	$text = remove_parantheses($text, '[[', ']]', '[[Bild:');
# what about the other writings? image:??

	return $text;
}

# TODO: test
sub remove_paran_pairs {
	my ($text) = @_;

	$text =~ s/\[\]//g;
	$text =~ s/\(\)//g;
	$text =~ s/\{\}//g;

	return $text;
}

# TODO: test
# TODO: rename
# parameters:
#   $text      - the text
#   $open_par  - opening paranthesis
#   $close_par - closing paranthesis
#   $starter   - first opening paranthesis (could be different from the opening paranthesis)
sub remove_parantheses {
	my ($text, $open_par, $close_par, $starter) = @_;

	if (!defined $text) {
		die "t\n";
	}
	if (!defined $open_par) {
		die "o\n";
	}
	if (!defined $close_par) {
		die "c\n";
	}
	if (!defined $starter) {
		$starter = $open_par;
	}

	if ($open_par eq $close_par) {
		die "remove_parantheses will not work if open_par==close_par: '$open_par'\n";
	}
	if (($open_par eq '') || ($starter eq '')) {
		die "remove_parantheses: empty parantheses are not allowed: '$open_par' or '$starter'\n";
	}

	my $starter_length = length($starter);
	my $open_length    = length($open_par);
	my $close_length   = length($close_par);

	my $depth = 0;       # current depth; shall never be negative
	my $current_pos = 0; # current position in the text; shall never decrease besides after deletion
	my $rm_start;        # starting positin of the area to be deleted

	# TODO: always add length of parans to current_pos

	LOOP:
	while (1) {

		#print "\ndepth $depth, pos $current_pos\n";

		# case 1
		if ($depth == 0) {
			# Look for starter paranthesis
			my $starter_pos = index($text, $starter, $current_pos);
			# case 1.1
			#print "1.1\n";
			if ($starter_pos != -1) {
				$depth++;
				$current_pos = $starter_pos + $starter_length;
				$rm_start = $starter_pos;
			}
			# case 1.2: nothing found			
			else {
				#print "1.2\n";
				last LOOP;
			}
		}
		# case 2
		else {
			#print "2\n";
			# Look for normal opening and closing parantheses
			my $open_pos  = index($text, $open_par, $current_pos);
			my $close_pos = index($text, $close_par, $current_pos);
			#print "open_pos  = index('$text', '$open_par', $current_pos) = $open_pos\n";
			#print "close_pos = index('$text', '$close_par', $current_pos) = $close_pos\n";
			# case 2.1: nothing found
			if ($open_pos == -1 && $close_pos == -1) {
				#print "2.1\n";
				last LOOP;
				# (parantheses did not close - there is nothing we can delete)
			}
			# case 2.2: found opening paranthesis
			elsif ($close_pos == -1 || ($open_pos < $close_pos && $open_pos != -1)) {
				#print "2.2\n";
				$depth++;
				$current_pos = $open_pos + $open_length;
			}
			# case 2.3: found closing paranthesis
			else {
				#print "2.3\n";
				$depth--;
				$current_pos = $close_pos + $close_length;
				# case 2.3.1
				if ($depth == 0) {
					#print "2.3.1\n";
					# delete identified area
					my $rm_length = $close_pos - $rm_start + $close_length;
					my $rm_end = $rm_start + $rm_length;
					#print "text = substr('$text', $rm_start, $rm_length)\n";
					my $deleted_text = substr($text, $rm_start, $rm_length);
					#print "deleted: '$deleted_text'\n";
					$text = substr($text, 0, $rm_start) . substr($text, $rm_end);
					#print "text: '$text'\n";
					# reset current position to the start of the deleted area
					$current_pos = $rm_start;
				}
				# case 2.3.2
				else {
					# do nothing
					#print "2.3.2\n";
				}
			}
		}


	}

	return $text;
}

# TODO: move this into a separate module
our @CATEGORY_PREFIXES = qw{Category Kategorie};

our $OPEN_BRACKETS  = qr/\[\[/;
our $CLOSE_BRACKETS = qr/\]\]/;
our $NO_BRACKETS    = qr/[^\[\]]/;

# also in WDG::Extractor::Util --> combine that!
sub remove_categories {
    my ($text) = @_;

    foreach my $category_prefix (@CATEGORY_PREFIXES) {
        $text =~ s/$OPEN_BRACKETS $category_prefix: $NO_BRACKETS+ $CLOSE_BRACKETS//gxms;
    }

    $text =~ s/\{\{DEFAULTSORT:[^\n]+\}\}//xms;

    return trim($text);
}

# TODO: move this into a separate module
# all as of Nov 26, 2008, see http://de.wikipedia.org/wiki/Wikipedia:Sprachen
our @LONG_LANGUAGE_IDS = qw{
    bat-smg
    be-x-old
    cbk-zam
    fiu-vro
    map-bms
    nds-nl
    roa-rup
    roa-tara
    simple
    zh-classical
    zh-min-nan
    zh-yue
};
our $LONG_LANGUAGE_IDS = join '|', @LONG_LANGUAGE_IDS;

sub remove_interwiki_links {
    my ($text) = @_;

    $text =~ s/$OPEN_BRACKETS
               (?:\w{2,3}|$LONG_LANGUAGE_IDS):
               $NO_BRACKETS+
               $CLOSE_BRACKETS
              //gxms;

    return trim($text);
}

# TODO: test
sub remove_personendaten_structure {
    my ($text) = @_;

    $text =~ s/
                \{\{Personendaten \s*
                \| \s* NAME= (.+)
            \| ALTERNATIVNAMEN= (.*) \s*
            \| KURZBESCHREIBUNG= (.*) \s*
            \| GEBURTSDATUM= (.*) \s*
            \| GEBURTSORT= (.*) \s*
            \| STERBEDATUM= (.*) \s*
            \| STERBEORT= (.*) \s*
            \}\}                
            /$1 $2 $3 $4 $5 $6/xms;

    return trim($text);
}

# TODO rename to dot abbr.
#      internationalize
#      Patterns like "20. Jahrhundert"
#      This has nothing to do with MediaWiki and thus should be moved out
sub lang_abbr {
	my ($text, $dotindex) = @_;

	foreach my $lang (@LANGUAGES) {
		my $pos = rindex($text, $lang, $dotindex);
		#print "pos: $pos dot: $dotindex lang: $lang\n";
		if ($pos == $dotindex - length($lang)) {
			return 1;
		}
	}

	return 0;
}

1;
