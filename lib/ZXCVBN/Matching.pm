#!/usr/bin/perl

use 5.006;
use feature 'unicode_strings';
use strict;
use warnings;

package ZXCVBN::Matching;

use ZXCVBN::Scoring;
use ZXCVBN::AdjacencyGraphs;
use ZXCVBN::FrequencyLists;
use boolean qw();

sub build_ranked_dict(\@) {
	my($p_ordered_list) = @_;
	
	my %result = ();
	
	my $i = 1;
	foreach my $word (@{$p_ordered_list}) {
		$result{$word} = $i;
		$i++;
	}
	
	return \%result;
}


{

my %RANKED_DICTIONARIES = ();

sub add_frequency_lists(\%;\%) {
	my($p_frequency_lists,$p_RANKED_DICTIONARIES) = @_;
	
	$p_RANKED_DICTIONARIES = \%RANKED_DICTIONARIES  unless(ref($p_RANKED_DICTIONARIES) eq 'HASH');
	
	@{$p_RANKED_DICTIONARIES}{keys(%{$p_frequency_lists})} = map { build_ranked_dict(@{$_}) } values(%{$p_frequency_lists});
}

sub get_default_ranked_dictionaries() {
	if(scalar(keys(%RANKED_DICTIONARIES)) == 0) {
		add_frequency_lists(%ZXCVBN::FrequencyLists::FREQUENCY_LISTS,%RANKED_DICTIONARIES);
	}
	
	# Return a copy, not the original!
	my %rethash = %RANKED_DICTIONARIES;
	return \%rethash;
}

}


my %GRAPHS = %ZXCVBN::AdjacenyGraphs::ADJACENCY_GRAPHS;

my %L33T_TABLE = (
    'a' => ['4', '@'],
    'b' => ['8'],
    'c' => ['(', '{', '[', '<'],
    'e' => ['3'],
    'g' => ['6', '9'],
    'i' => ['1', '!', '|'],
    'l' => ['1', '|', '7'],
    'o' => ['0'],
    's' => ['$', '5'],
    't' => ['+', '7'],
    'x' => ['%'],
    'z' => ['2'],
);

my %REGEXEN = (
    'recent_year' => qr/19\d\d|200\d|201\d/,
);

use constant DATE_MAX_YEAR => 2050;
use constant DATE_MIN_YEAR => 1000;
my %DATE_SPLITS = (
    4 => [  # for length-4 strings, eg 1191 or 9111, two ways to split:
        [1, 2],  # 1 1 91 (2nd split starts at index 1, 3rd at index 2)
        [2, 3],  # 91 1 1
    ],
    5 => [
        [1, 3],  # 1 11 91
        [2, 3],  # 11 1 91
    ],
    6 => [
        [1, 2],  # 1 1 1991
        [2, 4],  # 11 11 91
        [4, 5],  # 1991 1 1
    ],
    7 => [
        [1, 3],  # 1 11 1991
        [2, 3],  # 11 1 1991
        [4, 5],  # 1991 1 11
        [4, 6],  # 1991 11 1
    ],
    8 => [
        [2, 4],  # 11 11 1991
        [4, 6],  # 1991 11 11
    ],
);

sub omnimatch($;\%);

sub dictionary_match_unsorted($;\%) {
	my($password,$_ranked_dictionaries) = @_;
	
	$_ranked_dictionaries = get_default_ranked_dictionaries()  unless(ref($_ranked_dictionaries) eq 'HASH');
	
	my @matches = ();
	my $length = length($password);
	my $last = $length - 1;
	my $password_lower = lc($password);
	while(my($dictionary_name,$p_ranked_dict) = each(%{$_ranked_dictionaries})) {
		foreach my $i  (0..$last) {
			foreach my $j  ($i..$last) {
				my $word = substr($password_lower,$i,$j-$i+1);
				if(exists($p_ranked_dict->{$word})) {
					my $rank = $p_ranked_dict->{$word};
					push(@matches,{
						'pattern' => 'dictionary',
						'i' => $i,
						'j' => $j,
						'token' => substr($password,$i,$j-$i+1),
						'matched_word' => $word,
						'rank' => $rank,
						'dictionary_name' => $dictionary_name,
						'reversed' => boolean::false,
						'l33t' => boolean::false
					});
				}
			}
		}
	}
	
	return \@matches;
}

sub _sort_match(\@) {
	my($p_matches)=@_;
	
	my @sorted_matches = sort { $a->{'i'} == $b->{'i'} ? $a->{'j'} <=> $b->{'j'} : $a->{'i'} <=> $b->{'i'}  } @{$p_matches};
	
	return \@sorted_matches;
}
	
=head2 dictionary_match

dictionary match (common passwords, english, last names, etc)
=cut
sub dictionary_match($;\%) {
	my($password,$_ranked_dictionaries) = @_;
	
	$_ranked_dictionaries = get_default_ranked_dictionaries()  unless(ref($_ranked_dictionaries) eq 'HASH');
	
	my $p_matches = dictionary_match_unsorted($password,%{$_ranked_dictionaries});
	
	return _sort_match(@{$p_matches});
}


sub reverse_dictionary_match_unsorted($;\%) {
	my($password,$_ranked_dictionaries) = @_;
	
	my $reversed_password = reverse($password);
	
	$_ranked_dictionaries = get_default_ranked_dictionaries()  unless(ref($_ranked_dictionaries) eq 'HASH');
	
	my $p_matches = dictionary_match_unsorted($reversed_password,%{$_ranked_dictionaries});
	
	foreach my $p_match (@{$p_matches}) {
		$p_match->{'token'} = reverse($p_match->{'token'});
		$p_match->{'reversed'} = boolean::true;
		my $rev_i = length($password) - 1 - $p_match->{'j'};
		$p_match->{'j'} = length($password) - 1 - $p_match->{'i'};
		$p_match->{'i'} = $rev_i;
	}
	
	return $p_matches;
}

sub reverse_dictionary_match($;\%) {
	my($password,$_ranked_dictionaries) = @_;
	
	$_ranked_dictionaries = get_default_ranked_dictionaries()  unless(ref($_ranked_dictionaries) eq 'HASH');
	
	my $p_matches = reverse_dictionary_match_unsorted($password,%{$_ranked_dictionaries});
	
	return _sort_match(@{$p_matches});
}


sub relevant_l33t_subtable($\%) {
	my($password,$p_table) = @_;
	
	my %password_chars = map { $_ => 1 } split(//,$password);
	
	my %subtable = ();
	while(my($letter,$p_subs) = each(%{$p_table})) {
		my @relevant_subs = grep { exists($password_chars{$_}) } @{$p_subs};
		if(scalar(@relevant_subs) > 0) {
			$subtable{$letter} = \@relevant_subs;
		}
	}
	
	return \%subtable;
}

sub _dedup(\@) {
	my($p_subs) = @_;
	
	my @deduped = ();
	my %members = ();
	foreach my $p_sub (@{$p_subs}) {
		my @assoc = map { [$_->[1],$_->[0]] } @{$p_sub};
		my @assoc_sorted = sort { $a->[0] eq $b->[0] ? $a->[1] cmp $b->[1] : $a->[0] cmp $b->[0] } @assoc;
		
		my $label = join('-',map { join(',',@{$_}) } @assoc_sorted);
		unless(exists($members{$label})) {
			$members{$label} = boolean::true;
			push(@deduped,$p_sub);
		}
	}
	
	return \@deduped;
}

sub _helper(\@\@\%);

sub _helper(\@\@\%) {
	my($p_keys,$p_subs,$p_table) = @_;
	
	return $p_subs  if(scalar(@{$p_keys})==0);
	
	my($first_key,@rest_keys) = @{$p_keys};
	my @next_subs = ();
	foreach my $l33t_chr (split(//,@{$p_table->{$first_key}})) {
		foreach my $p_sub (@{$p_subs}) {
			my $dup_l33t_index = -1;
			my $i = 0;
			foreach my $p_sub_i (@{$p_sub}) {
				if(substr($p_sub_i,0,1) eq $l33t_chr) {
					$dup_l33t_index = $i;
					last;
				}
				$i++;
			}
			if($dup_l33t_index == -1) {
				my @sub_extension = @{$p_sub};
				push(@sub_extension,[$l33t_chr, $first_key]);
				push(@next_subs,\@sub_extension);
			} else {
				my @sub_alternative = @{$p_sub};
				splice(@sub_alternative,$dup_l33t_index,1);
				push(@sub_alternative,[$l33t_chr, $first_key]);
				push(@next_subs,$p_sub);
				push(@next_subs,\@sub_alternative);
			}
		}
	}
	
	$p_subs = _dedup(@next_subs);
	return _helper(@rest_keys,@{$p_subs},%{$p_table});
}

sub enumerate_l33t_subs(\%) {
	my($p_table) = @_;
	my @keys = keys(%{$p_table});
	my @subs = ( [] );
	
	print STDERR "DEBUG BEFORE0\n";
	my $p_subs = _helper(@keys,@subs,%{$p_table});
	print STDERR "DEBUG AFTER0\n";
	# convert from assoc lists to dicts
	my @sub_dicts = ();
	foreach my $p_sub (@{$p_subs}) {
		my %sub_dict = map { $_->[0] => $_->[1] } @{$p_sub};
		push(@sub_dicts,\%sub_dict);
	}
	
	return \@sub_dicts;
}

sub translate($\%) {
	my($string,$p_chr_map) = @_;
	
	my $chars = '';
	foreach my $char (split(//,$string)) {
		$chars .= exists($p_chr_map->{$char}) ? $p_chr_map->{$char} : $char;
	}
	
	return $chars;
}

sub l33t_match_unsorted($;\%\%) {
	my($password,$_ranked_dictionaries,$_l33t_table) = @_;
	
	$_ranked_dictionaries = get_default_ranked_dictionaries()  unless(ref($_ranked_dictionaries) eq 'HASH');
	$_l33t_table = \%L33T_TABLE  unless(ref($_l33t_table) eq 'HASH');
	
	my @matches = ();
	
	print STDERR "DEBUG BEFORE\n";
	my $p_lsubs = enumerate_l33t_subs(%{relevant_l33t_subtable($password,%{$_l33t_table})});
	print STDERR "DEBUG AFTER\n";
	foreach my $p_lsub (@{$p_lsubs}) {
		last  if(scalar(keys(%{$p_lsub}))==0);
		
		my $subbed_password = translate($password,%{$p_lsub});
		my $p_dict_matches = dictionary_match_unsorted($subbed_password,%{$_ranked_dictionaries});
		foreach my $p_match (@{$p_dict_matches}) {
			# Skip too short matches
			next  if($p_match->{'j'} <= $p_match->{'i'});
			
			my $token = substr($password,$p_match->{'i'},$p_match->{'j'} - $p_match->{'i'} + 1);
			# only return the matches that contain an actual substitution
			next  if(lc($token) eq $p_match->{'matched_word'});
			
			# subset of mappings in sub that are in use for this match
			my %match_sub = ();
			while(my($subbed_chr,$chr) = each(%{$p_lsub})) {
				$match_sub{$subbed_chr} = $chr  if(index($token,$subbed_chr) != -1);
			}
			$p_match->{'l33t'} = boolean::true;
			$p_match->{'token'} = $token;
			$p_match->{'sub'} = \%match_sub;
			$p_match->{'sub_display'} = join(', ',map { $_ . ' -> '.$match_sub{$_} } sort(keys(%match_sub)));
			push(@matches,$p_match);
		}
	}
	
	return \@matches;
}

sub l33t_match($;\%\%) {
	my($password,$_ranked_dictionaries,$_l33t_table) = @_;
	
	$_ranked_dictionaries = get_default_ranked_dictionaries()  unless(ref($_ranked_dictionaries) eq 'HASH');
	$_l33t_table = \%L33T_TABLE  unless(ref($_l33t_table) eq 'HASH');
	
	my $p_matches = l33t_match_unsorted($password,%{$_ranked_dictionaries},%{$_l33t_table});
	
	return _sort_match(@{$p_matches});
}


my $greedy = qr/(.+)\g{1}+/;
my $lazy = qr/(.+?)\g{1}+/;
my $lazy_anchored = qr/^(.+?)\g{1}+$/;
=head2 repeat_match

repeats (aaa, abcabcabc) and sequences (abcdef)
=cut
sub repeat_match_unsorted($;\%) {
	my($password,$_ranked_dictionaries) = @_;
	
	$_ranked_dictionaries = get_default_ranked_dictionaries()  unless(ref($_ranked_dictionaries) eq 'HASH');
	
	my @matches = ();
	my $last_index = 0;
	while($last_index < length($password)) {
		my $subpassword = substr($password,$last_index);
		if($subpassword =~ $greedy) {
			my $base_token;
			
			my $greedy_match0 = substr($subpassword,$-[0],$+[0] - $-[0]);
			my $greedy_i = $last_index + $-[0];
			my $greedy_j = $last_index + $+[0] - 1;
			my $i = undef;
			my $j = undef;
			my $match0 = undef;
			if($subpassword =~ $lazy) {
				my $lazy_match0 = substr($subpassword,$-[0],$+[0] - $-[0]);
				my $lazy_match1 = $1;
				my $lazy_i = $last_index + $-[0];
				my $lazy_j = $last_index + $+[0] - 1;
				
				if(length($greedy_match0) > length($lazy_match0)) {
					# greedy beats lazy for 'aabaab'
					#   greedy: [aabaab, aab]
					#   lazy:   [aa,     a]
					$match0 = $greedy_match0;
					$i = $greedy_i;
					$j = $greedy_j;
					
					# greedy's repeated string might itself be repeated, eg.
					# aabaab in aabaabaabaab.
					# run an anchored lazy match on greedy's repeated string
					# to find the shortest repeated string
					if($match0 =~ $lazy_anchored) {
						$base_token = $1;
					}
				} else {
					$match0 = $lazy_match0;
					$i = $lazy_i;
					$j = $lazy_j;
					$base_token = $lazy_match1;
				}
			}
			
			# recursively match and score the base string
			my $p_base_analysis = ZXCVBN::Scoring::most_guessable_match_sequence(
				$base_token,
				@{omnimatch_unsorted($base_token,%{$_ranked_dictionaries})}
			);
			my $base_matches = $p_base_analysis->{'sequence'};
			my $base_guesses = $p_base_analysis->{'guesses'};
			push(@matches,{
				'pattern'	=>	'repeat',
				'i'	=>	$i,
				'j'	=>	$j,
				'token'	=>	$match0,
				'base_token'	=>	$base_token,
				'base_guesses'	=>	$base_guesses,
				'base_matches'	=>	$base_matches,
				'repeat_count'	=>	length($match0) / length($base_token)
			});
			$last_index = $j + 1;
		} else {
			last;
		}
	}
	
	use Data::Dumper;
	print Dumper(\@matches),"\n";
	
	return \@matches;
}

sub repeat_match($;\%) {
	my($password,$_ranked_dictionaries) = @_;
	
	$_ranked_dictionaries = get_default_ranked_dictionaries()  unless(ref($_ranked_dictionaries) eq 'HASH');
	
	my $p_matches = repeat_match_unsorted($password,%{$_ranked_dictionaries});
	
	return _sort_match(@{$p_matches});
}

my $SHIFTED_RX = qr/[~!@#\$%^&*()_+QWERTYUIOP{}|ASDFGHJKL:"ZXCVBNM<>?]/;
sub spatial_match_helper($\%$) {
	my($password,$p_graph,$graph_name) = @_;
	
	my @matches = ();
	my $i = 0;
	my $length_password = length($password);
	my $length_password_1 = $length_password - 1;
	while($i < $length_password_1) {
		my $j = $i + 1;
		my $last_direction = undef;
		my $turns = 0;
		my $shifted_count = undef;
		if($graph_name ~~ ['qwerty','dvorak'] && substr($password,$i,1) =~ $SHIFTED_RX) {
			# initial character is shifted
			$shifted_count = 1;
		} else {
			$shifted_count = 0;
		}
		
		while(1) {
			my $prev_char = substr($password, $j - 1, 1);
			my $found = boolean::false;
			my $found_direction = -1;
			my $cur_direction = -1;
			my $adjacents = (exists($p_graph->{$prev_char}) && defined($p_graph->{$prev_char})) ? $p_graph->{$prev_char} : [];
			# consider growing pattern by one character if j hasn't gone
			# over the edge.
			if($j < $length_password) {
				my $cur_char = substr($password,$j,1);
				foreach my $adj (@{$adjacents}) {
					$cur_direction ++;
					if(defined($adj) && index($adj,$cur_char)!=-1) {
						$found = boolean::true;
						$found_direction = $cur_direction;
						if(index($adj,$cur_char)==1) {
							# index 1 in the adjacency means the key is shifted,
							# 0 means unshifted: A vs a, % vs 5, etc.
							# for example, 'q' is adjacent to the entry '2@'.
							# @ is shifted w/ index 1, 2 is unshifted.
							$shifted_count++;
						}
						if($last_direction!=$found_direction) {
							# adding a turn is correct even in the initial case
							# when last_direction is null:
							# every spatial pattern starts with a turn.
							$turns++;
							$last_direction = $found_direction;
						}
						last;
					}
				}
			}
			# if the current pattern continued, extend j and try to grow again
			if($found) {
				$j++;
			} else {
				# otherwise push the pattern discovered so far, if any...
				if(($j-$i) > 2) {	# don't consider length 1 or 2 chains.
					push(@matches,{
						'pattern'	=>	'spatial',
						'i'	=>	$i,
						'j'	=>	$j - 1,
						'token'	=>	substr($password,$i,$j-$i),
						'graph'	=>	$graph_name,
						'turns'	=>	$turns,
						'shifted_count'	=>	$shifted_count
					});
				}
				# ...and then start a new search for the rest of the password.
				$i = $j;
				last;
			}
		}
	}
	
	return \@matches;
}

sub spatial_match_unsorted($;\%\%) {
	my($password,$_ranked_dictionaries,$_graphs) = @_;
	
	$_ranked_dictionaries = get_default_ranked_dictionaries()  unless(ref($_ranked_dictionaries) eq 'HASH');
	$_graphs = \%GRAPHS  unless(ref($_graphs) eq 'HASH');
	
	my @matches = ();
	while(my($graph_name,$p_graph) = each(%{$_graphs})) {
		push(@matches,@{spatial_match_helper($password,%{$p_graph},$graph_name)});
	}
	
	return \@matches;
}

sub spatial_match($;\%\%) {
	my($password,$_ranked_dictionaries,$_graphs) = @_;
	
	$_ranked_dictionaries = get_default_ranked_dictionaries()  unless(ref($_ranked_dictionaries) eq 'HASH');
	$_graphs = \%GRAPHS  unless(ref($_graphs) eq 'HASH');
	
	my $p_matches = spatial_match_unsorted($password,%{$_ranked_dictionaries},%{$_graphs});
	
	return _sort_match(@{$p_matches});
}

use constant MAX_DELTA	=>	5;

sub _update($$$\@$) {
	my($i, $j, $delta, $p_result,$password) = @_;
	
	if(($j - $i) > 1 || (defined($delta) && abs($delta) == 1)) {
		my $absdelta = abs($delta);
		if(0 < $absdelta && $absdelta <= MAX_DELTA ) {
			my $token = substr($password,$i,$j - $i +1);
			my $sequence_name = undef;
			my $sequence_space = undef;
			if($token =~ /^[a-z]+$/) {
				$sequence_name = 'lower';
				$sequence_space = 26;
			} elsif($token =~ /^[A-Z]+$/) {
				$sequence_name = 'upper';
				$sequence_space = 26;
			} elsif($token =~ /^\d+$/) {
				$sequence_name = 'digits';
				$sequence_space = 10;
			} else {
				$sequence_name = 'unicode';
				$sequence_space = 26;
			}
			push(@{$p_result},{
				'pattern'	=>	'sequence',
				'i'	=>	$i,
				'j'	=>	$j,
				'token'	=>	$token,
				'sequence_name'	=>	$sequence_name,
				'sequence_space'	=>	$sequence_space,
				'ascending'	=>	($delta > 0)
			});
		}
	}
}

=head2 sequence_match

Identifies sequences by looking for repeated differences in unicode codepoint.
this allows skipping, such as 9753, and also matches some extended unicode sequences
such as Greek and Cyrillic alphabets.

for example, consider the input 'abcdb975zy'

password: a   b   c   d   b    9   7   5   z   y
index:    0   1   2   3   4    5   6   7   8   9
delta:      1   1   1  -2  -41  -2  -2  69   1

expected result:
[(i, j, delta), ...] = [(0, 3, 1), (5, 7, -2), (8, 9, 1)]
=cut
sub sequence_match_unsorted($\%) {
	my($password,$_ranked_dictionaries) = @_;
	
	$_ranked_dictionaries = get_default_ranked_dictionaries()  unless(ref($_ranked_dictionaries) eq 'HASH');
	
	my @result = ();
	
	if(length($password) > 1) {
		return \@result;
		
		my $i = 0;
		my $last_delta = undef;
		
		foreach my $k (1..length($password)-1) {
			my $delta = ord(substr($password,$k,1)) - ord(substr($password,$k-1,1));
			unless(defined($last_delta)) {
				$last_delta = $delta;
			}
			if($delta == $last_delta) {
				next;
			}
			my $j = $k - 1;
			_update($i,$j,$last_delta,@result,$password);
			$i = $j;
			$last_delta = $delta;
		}
		_update($i,length($password)-1,$last_delta,@result,$password);
	}
	
	return \@result;
}

sub sequence_match($\%) {
	my($password,$_ranked_dictionaries) = @_;
	
	$_ranked_dictionaries = get_default_ranked_dictionaries()  unless(ref($_ranked_dictionaries) eq 'HASH');
	
	my $p_matches = sequence_match_unsorted($password,%{$_ranked_dictionaries});
	
	return _sort_match(@{$p_matches});
}


sub regex_match_unsorted($\%\%) {
	my($password,$_ranked_dictionaries,$_regexen) = @_;
	
	$_ranked_dictionaries = get_default_ranked_dictionaries()  unless(ref($_ranked_dictionaries) eq 'HASH');
	$_regexen = \%REGEXEN  unless(ref($_regexen) eq 'HASH');
	
	my @matches = ();
	while(my($name,$regex) = each(%{$_regexen})) {
		while($password =~ /$regex/g) {
			push(@matches,{
				'pattern'	=>	'regex',
				'token'	=>	$&,
				'i'	=>	length($`),
				'j'	=>	length($`) + length($&) -1,
				'regex_name'	=>	$name,
				# This differs from the original implementation
				'regex_match'	=>	$&
			});
		}
	}
	
	return \@matches;
}

sub regex_match($\%\%) {
	my($password,$_ranked_dictionaries,$_regexen) = @_;
	
	$_ranked_dictionaries = get_default_ranked_dictionaries()  unless(ref($_ranked_dictionaries) eq 'HASH');
	$_regexen = \%REGEXEN  unless(ref($_regexen) eq 'HASH');

	my $p_matches = regex_match_unsorted($password,%{$_ranked_dictionaries},%{$_regexen});
	
	return _sort_match(@{$p_matches});
}


=head2 _filter_fun

matches now contains all valid date strings in a way that is tricky to
capture with regexes only. while thorough, it will contain some
unintuitive noise:

'2015_06_04', in addition to matching 2015_06_04, will also contain
5(!) other date matches: 15_06_04, 5_06_04, ..., even 2015
(matched as 5/1/2020)

to reduce noise, remove date matches that are strict substrings of others
=cut
sub _filter_fun(\%\@) {
	my($p_match,$p_matches) = @_;
	
	my $is_submatch = boolean::false;
	
	foreach my $p_other (@{$p_matches}) {
		if($p_match != $p_other) {
			if($p_other->{'i'} <= $p_match->{'i'} && $p_other->{'j'} >= $p_match->{'j'}) {
				$is_submatch = boolean::true;
				last;
			}
		}
	}
	
	return ! $is_submatch;
}


sub map_ints_to_dm(\@) {
	my($p_ints) = @_;
	
	my @reverse_p_ints = reverse(@{$p_ints});
	foreach my $d_m ($p_ints, \@reverse_p_ints) {
		use Data::Dumper;
		print STDERR "JARL",Dumper($d_m),"\n";
		my($d,$m) = @{$d_m};
		if(1 <= $d && $d <= 31 && 1 <= $m && $m <= 12) {
			return {
				'day'	=>	$d,
				'month'	=>	$m
			};
		}
	}
	
	# default case
	return undef;
}

sub two_to_four_digit_year($) {
	my($year) = @_;
	if($year > 99) {
		return $year;
	} elsif($year > 50) {
		# 87 -> 1987
		return $year + 1900;
	} else {
		# 15 -> 2015
		return $year + 2000;
	}
}

=head2 map_ints_to_dmy

given a 3-tuple, discard if:
  middle int is over 31 (for all dmy formats, years are never allowed in
  the middle)
  middle int is zero
  any int is over the max allowable year
  any int is over two digits but under the min allowable year
  2 ints are over 31, the max allowable day
  2 ints are zero
  all ints are over 12, the max allowable month
=cut
sub map_ints_to_dmy(@) {
	my(@ints) = @_;
	
	if($ints[1] > 31 || $ints[1] <= 0) {
		return;
	}
	
	my $over_12 = 0;
	my $over_31 = 0;
	my $under_1 = 0;
	foreach my $int (@ints) {
		if((99 < $int && $int < DATE_MIN_YEAR) || $int > DATE_MAX_YEAR) {
			return;
		}
		if($int > 31) {
			$over_31++;
		}
		if($int > 12) {
			$over_12++;
		}
		if($int <= 0) {
			$under_1++;
		}
	}
	if($over_31 >= 2 || $over_12 == 3 || $under_1 >= 2) {
		return;
	}

	# first look for a four digit year: yyyy + daymonth or daymonth + yyyy
	my @possible_four_digit_splits = (
		[$ints[2], @ints[0..2]],
		[$ints[0], @ints[1..3]],
	);
	foreach my $y_rest (@possible_four_digit_splits) {
		my($y,@rest) = @{$y_rest};
		if(DATE_MIN_YEAR <= $y && $y <= DATE_MAX_YEAR) {
			my $p_dm = map_ints_to_dm(@rest);
			if(defined($p_dm)) {
				return {
					'year'	=>	$y,
					'month'	=>	$p_dm->{'month'},
					'day'	=>	$p_dm->{'day'}
				};
			} else {
				# for a candidate that includes a four-digit year,
				# when the remaining ints don't match to a day and month,
				# it is not a date.
				return;
			}
		}
	}
	
	# given no four-digit year, two digit years are the most flexible int to
	# match, so try to parse a day-month out of ints[0..1] or ints[1..0]
	foreach my $y_rest (@possible_four_digit_splits) {
		my($y,@rest) = @{$y_rest};
		my $p_dm = map_ints_to_dm(@rest);
		if(defined($p_dm)) {
			$y = two_to_four_digit_year($y);
			return {
				'year'	=>	$y,
				'month'	=>	$p_dm->{'month'},
				'day'	=>	$p_dm->{'day'}
			};
		}
	}
	
	# default case
	return undef;
}





my $maybe_date_no_separator = qr/^\d{4,8}$/;
my $maybe_date_with_separator = qr/^(\d{1,4})([\s\/\\_.-])(\d{1,2})\g{2}(\d{1,4})$/;

sub _metric(\%) {
	my($p_candidate) = @_;
	
	return abs($p_candidate->{'year'} - ZXCVBN::Scoring::REFERENCE_YEAR);
}

=head2 date_match

a "date" is recognized as:
  any 3-tuple that starts or ends with a 2- or 4-digit year,
  with 2 or 0 separator chars (1.1.91 or 1191),
  maybe zero-padded (01-01-91 vs 1-1-91),
  a month between 1 and 12,
  a day between 1 and 31.

note: this isn't true date parsing in that "feb 31st" is allowed,
this doesn't check for leap years, etc.

recipe:
start with regex to find maybe-dates, then attempt to map the integers
onto month-day-year to filter the maybe-dates into dates.
finally, remove matches that are substrings of other matches to reduce noise.

note: instead of using a lazy or greedy regex to find many dates over the full string,
this uses a ^...$ regex against every substring of the password -- less performant but leads
to every possible date match.
=cut
sub date_match_unsorted($\%) {
	my($password,$_ranked_dictionaries) = @_;
	
	$_ranked_dictionaries = get_default_ranked_dictionaries()  unless(ref($_ranked_dictionaries) eq 'HASH');
	
	my @matches = ();
	
	# dates without separators are between length 4 '1191' and 8 '11111991'
	foreach my $i (0..(length($password)-4)) {
		foreach my $j (($i+3)..($i+7)) {
			if($j >= length($password)) {
				last;
			}
			
			my $token = substr($password,$i,$j-$i+1);
			unless($token =~ $maybe_date_no_separator) {
				next;
			}
			my @candidates = ();
			foreach my $k_l (@{$DATE_SPLITS{length($token)}}) {
				my($k,$l) = @{$k_l};
				
				my $dmy = map_ints_to_dmy(int(substr($token,0, $k)),int(substr($token,$k,$l-$k)),int(substr($token,$l)));
				if(defined($dmy)) {
					push(@candidates,$dmy);
				}
			}
			unless(scalar(@candidates)>0) {
				next;
			}
			# at this point: different possible dmy mappings for the same i,j
			# substring. match the candidate date that likely takes the fewest
			# guesses: a year closest to 2000. (scoring.REFERENCE_YEAR).
			#
			# ie, considering '111504', prefer 11-15-04 to 1-1-1504
			# (interpreting '04' as 2004)
			my $best_candidate = $candidates[0];
			
			my $min_distance = _metric(%{$best_candidate});
			foreach my $candidate (@candidates[1..$#candidates]) {
				my $distance = _metric(%{$candidate});
				if($distance<$min_distance) {
					$best_candidate = $candidate;
					$min_distance = $distance;
				}
			}
			push(@matches,{
				'pattern'	=>	'date',
				'token'	=>	$token,
				'i'	=>	$i,
				'j'	=>	$j,
				'separator'	=>	'',
				'year'	=>	$best_candidate->{'year'},
				'month'	=>	$best_candidate->{'month'},
				'day'	=>	$best_candidate->{'day'},
			});
		}
	}
	
	# dates with separators are between length 6 '1/1/91' and 10 '11/11/1991'
	foreach my $i (0..(length($password) - 6)) {
		foreach my $j (($i + 5)..($i + 9)) {
			if($j >= length($password)) {
				last;
			}
			my $token = substr($password,$j - $i  + 1);
			if($token =~ $maybe_date_with_separator) {
				my $p_dmy = map_ints_to_dmy(int($1),int($3),int($4));
				next  unless(defined($p_dmy));
				push(@matches,{
					'pattern'	=>	'date',
					'token'	=>	$token,
					'i'	=>	$i,
					'j'	=>	$j,
					'separator'	=>	$2,
					'year'	=>	$p_dmy->{'year'},
					'month'	=>	$p_dmy->{'month'},
					'day'	=>	$p_dmy->{'day'},
				});
			} else {
				next;
			}
		}
	}
	
	@matches = grep { _filter_fun(%{$_},@matches) } @matches;
	return \@matches;
}

sub date_match($\%) {
	my($password,$_ranked_dictionaries) = @_;
	
	$_ranked_dictionaries = get_default_ranked_dictionaries()  unless(ref($_ranked_dictionaries) eq 'HASH');

	my $p_matches = date_match_unsorted($password,%{$_ranked_dictionaries});
	
	return _sort_match(@{$p_matches});
}



our @ALL_MATCHERS = (
	\&dictionary_match_unsorted,
	\&reverse_dictionary_match_unsorted,
	\&l33t_match_unsorted,
	\&spatial_match_unsorted,
	\&repeat_match_unsorted,
	\&sequence_match_unsorted,
	\&regex_match_unsorted,
	\&date_match_unsorted
);

=head2 omnimatch

omnimatch -- perform all matches
=cut
sub omnimatch_unsorted($;\%) {
	my($password,$_ranked_dictionaries) = @_;
	
	$_ranked_dictionaries = get_default_ranked_dictionaries()  unless(ref($_ranked_dictionaries) eq 'HASH');
	
	my @matches = ();
	
	foreach my $p_matcher (@ALL_MATCHERS) {
		push(@matches, @{$p_matcher->($password,$_ranked_dictionaries)});
	}
	
	return \@matches;
}

sub omnimatch($;\%) {
	my($password,$_ranked_dictionaries) = @_;
	
	$_ranked_dictionaries = get_default_ranked_dictionaries()  unless(ref($_ranked_dictionaries) eq 'HASH');
	
	my $p_matches = omnimatch_unsorted($password,%{$_ranked_dictionaries});
	
	return _sort_match(@{$p_matches});
}


1;
