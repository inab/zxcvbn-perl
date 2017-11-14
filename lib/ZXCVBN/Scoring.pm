#!/usr/bin/perl

use 5.014;
use feature 'unicode_strings';
use strict;
use warnings;

package ZXCVBN::Scoring;

use ZXCVBN::AdjacencyGraphs;
use boolean qw();
#use List::Util qw();

sub calc_average_degree(\%) {
	my($p_graph) = @_;
	
	my $average = 0;
	
	while(my($key,$p_neighbors) = each(%{$p_graph})) {
		$average += scalar(grep { defined($_) } @{$p_neighbors});
	}
	$average /= scalar(keys(%{$p_graph}));
	
	return $average;
}

use constant {
	BRUTEFORCE_CARDINALITY => 10,
	MIN_GUESSES_BEFORE_GROWING_SEQUENCE => 10000,
	MIN_SUBMATCH_GUESSES_SINGLE_CHAR => 10,
	MIN_SUBMATCH_GUESSES_MULTI_CHAR => 50,

	MIN_YEAR_SPACE => 20,
	REFERENCE_YEAR => 2017
};


=head2 nCk

http://blog.plover.com/math/choose.html
=cut
sub nCk($$) {
	my($n,$k) = @_;
	
	if($k > $n) {
		return 0;
	}
	if($k == $n) {
		return 1;
	}
	
	my $r = 1;
	foreach my $d (1..$k) {
		$r *= $n;
		$r /= $d;
		$n--;
	}
	
	return $r;
}


sub _factorial($) {
	my($l) = @_;
	return $l  if($l<=2);
	
	my $retval = 1;
	foreach my $v (2..$l) {
		$retval *= $v;
	}
	
	return $retval;
}

sub _max($$) {
	return $_[0] > $_[1] ? $_[0] : $_[1];
}

sub _min($$) {
	return $_[0] < $_[1] ? $_[0] : $_[1];
}


my $START_UPPER = qr/^[A-Z][^A-Z]+$/;
my $END_UPPER = qr/^[^A-Z]+[A-Z]$/;
my $ALL_UPPER = qr/^[^a-z]+$/;
my $ALL_LOWER = qr/^[^A-Z]+$/;


sub uppercase_variations(\%) {
	my($p_match) = @_;
	my $word = $p_match->{'token'};
	
	if($word =~ $ALL_LOWER || lc($word) eq $word) {
		return 1;
	}
	
	foreach my $regex ($START_UPPER, $END_UPPER, $ALL_UPPER) {
		if($word =~ $regex) {
			return 2;
		}
	}
	
	my $U = scalar(grep { $_ =~ /[[:upper:]]/ } split(//,$word));
	my $L = scalar(grep { $_ =~ /[[:lower:]]/ } split(//,$word));
	my $variations = 0;
	foreach my $i (1 .. _min($U, $L)) {
		$variations += nCk($U + $L, $i);
	}
	
	return $variations;
}


sub l33t_variations(\%) {
	my($p_match) = @_;
	
	return 1  unless(exists($p_match->{'l33t'}));
	
	my $variations = 1;
	
	while(my($subbed,$unsubbed) = each(%{$p_match->{'sub'}})) {
		# lower-case match.token before calculating: capitalization shouldn't
		# affect l33t calc.
		my @chrs = split(//,lc($p_match->{'token'}));
		my $S = scalar(grep { $_ eq $subbed } @chrs);
		my $U = scalar(grep { $_ eq $unsubbed } @chrs);
		if($S==0 || $U==0) {
			# for this sub, password is either fully subbed (444) or fully
			# unsubbed (aaa) treat that as doubling the space (attacker needs
			# to try fully subbed chars in addition to unsubbed.)
			$variations *= 2;
		} else {
			# this case is similar to capitalization:
			# with aa44a, U = 3, S = 2, attacker needs to try unsubbed + one
			# sub + two subs
			my $p = _min($U,$S);
			my $possibilities = 0;
			foreach my $i (1..$p) {
				$possibilities += nCk($U + $S, $i);
			}
			$variations *= $possibilities;
		}
	}
	
	return $variations;
}



sub bruteforce_guesses(\%) {
	my($p_match) = @_;
	my $guesses = BRUTEFORCE_CARDINALITY ** length($p_match->{'token'});
	# small detail: make bruteforce matches at minimum one guess bigger than
	# smallest allowed submatch guesses, such that non-bruteforce submatches
	# over the same [i..j] take precedence.
	my $min_guesses = undef;
	if(length($p_match->{'token'}) == 1) {
		$min_guesses = MIN_SUBMATCH_GUESSES_SINGLE_CHAR + 1;
	} else {
		$min_guesses = MIN_SUBMATCH_GUESSES_MULTI_CHAR + 1;
	}
	
	return _max($guesses, $min_guesses);
}

sub dictionary_guesses(\%) {
	my($p_match) = @_;
	
	# keep these as properties for display purposes
	$p_match->{'base_guesses'} = $p_match->{'rank'};
	$p_match->{'uppercase_variations'} = uppercase_variations(%{$p_match});
	$p_match->{'l33t_variations'} = l33t_variations(%{$p_match});
	my $reversed_variations = exists($p_match->{'reversed'}) ? 2 : 1;
	
	return $p_match->{'base_guesses'} * $p_match->{'uppercase_variations'} * \
		$p_match->{'l33t_variations'} * $reversed_variations;
}


sub repeat_guesses(\%) {
	my($p_match) = @_;
	
	return $p_match->{'base_guesses'} * $p_match->{'repeat_count'};
}


sub sequence_guesses(\%) {
	my($p_match) = @_;
	
	my $first_chr = substr($p_match->{'token'},0,1);
	# lower guesses for obvious starting points
	my $base_guesses = undef;
	if($first_chr ~~ ['a', 'A', 'z', 'Z', '0', '1', '9']) {
		$base_guesses = 4;
	} elsif($first_chr =~ /[[:digit:]]/) {
		$base_guesses = 10;  # digits
        } else {
		# could give a higher base for uppercase,
		# assigning 26 to both upper and lower sequences is more
		# conservative.
		$base_guesses = 26;
	}
	unless($p_match->{'ascending'}) {
		$base_guesses *= 2;
	}
        
	return $base_guesses * length($p_match->{'token'});
}

my %char_class_bases = (
        'alpha_lower'	=>	26,
        'alpha_upper'	=>	26,
        'alpha'	=>	52,
        'alphanumeric'	=>	62,
        'digits'	=>	10,
        'symbols'	=>	33,
);

sub regex_guesses(\%) {
	my($p_match) = @_;
	
	if(exists($char_class_bases{$p_match->{'regex_name'}})) {
		return $char_class_bases{$p_match->{'regex_name'}} ** length($p_match->{'token'});
	}
	my $year_space = undef;
	if($p_match->{'regex_name'} eq 'recent_year') {
		# conservative estimate of year space: num years from REFERENCE_YEAR.
		# if year is close to REFERENCE_YEAR, estimate a year space of
		# MIN_YEAR_SPACE.
		$year_space = int(abs(int($p_match->{'token'}) - REFERENCE_YEAR));
		$year_space = _max($year_space, MIN_YEAR_SPACE);
	}

        return $year_space;
}


sub date_guesses(\%) {
	my($p_match) = @_;
	
	my $year_space = _max(abs($p_match->{'year'} - REFERENCE_YEAR), MIN_YEAR_SPACE);
	my $guesses = $year_space * 365;
	if(exists($p_match->{'separator'})) {
		$guesses *= 4;
	}
        
	return $guesses;
}


my $KEYBOARD_AVERAGE_DEGREE = calc_average_degree(%{$ZXCVBN::AdjacencyGraphs::ADJACENCY_GRAPHS{'qwerty'}});
# slightly different for keypad/mac keypad, but close enough
my $KEYPAD_AVERAGE_DEGREE = calc_average_degree(%{$ZXCVBN::AdjacencyGraphs::ADJACENCY_GRAPHS{'keypad'}});

my $KEYBOARD_STARTING_POSITIONS = scalar(keys(%{$ZXCVBN::AdjacencyGraphs::ADJACENCY_GRAPHS{'qwerty'}}));
my $KEYPAD_STARTING_POSITIONS = scalar(keys(%{$ZXCVBN::AdjacencyGraphs::ADJACENCY_GRAPHS{'keypad'}}));


sub spatial_guesses(\%) {
	my($p_match) = @_;

	my $s = undef;
	my $d = undef;
	if($p_match->{'graph'} ~~ ['qwerty', 'dvorak']) {
		$s = $KEYBOARD_STARTING_POSITIONS;
		$d = $KEYBOARD_AVERAGE_DEGREE;
	} else {
		$s = $KEYPAD_STARTING_POSITIONS;
		$d = $KEYPAD_AVERAGE_DEGREE;
	}
	my $guesses = 0;
	my $L = length($p_match->{'token'});
	my $t = $p_match->{'turns'};
	# estimate the number of possible patterns w/ length L or less with t turns
	# or less.
	foreach my $i (2 .. $L) {
		my $possible_turns = _min($t, $i - 1) + 1;
		foreach my $j (1 .. ($possible_turns - 1)) {
			$guesses += nCk($i - 1, $j - 1) * $s * ($d ** $j);
		}
	}
	# add extra guesses for shifted keys. (% instead of 5, A instead of a.)
	# math is similar to extra guesses of l33t substitutions in dictionary
	# matches.
	if($p_match->{'shifted_count'}) {
		my $S = $p_match->{'shifted_count'};
		my $U = length($p_match->{'token'}) - $S;  # unshifted count
		if($S == 0 || $U == 0) {
		    $guesses *= 2;
		} else {
			my $shifted_variations = 0;
			foreach my $i (1, _min($S, $U)) {
				$shifted_variations += nCk($S + $U, $i);
			}
			$guesses *= $shifted_variations;
		}
	}

	return $guesses;
}


my %estimation_functions = (
	'bruteforce'	=> \&bruteforce_guesses,
	'dictionary'	=> \&dictionary_guesses,
	'spatial'	=> \&spatial_guesses,
	'repeat'	=> \&repeat_guesses,
	'sequence'	=> \&sequence_guesses,
	'regex'		=> \&regex_guesses,
	'date'		=> \&date_guesses
);


sub estimate_guesses(\%$) {
	my($p_match,$password) = @_;
	
	if(exists($p_match->{'guesses'})) {
		return $p_match->{'guesses'};
	}
	
	my $min_guesses = 1;
	if(length($p_match->{'token'}) < length($password)) {
		if(length($p_match->{'token'}) == 1) {
			$min_guesses = MIN_SUBMATCH_GUESSES_SINGLE_CHAR;
		} else {
			$min_guesses = MIN_SUBMATCH_GUESSES_MULTI_CHAR;
		}
	}
	
	my $guesses = $estimation_functions{$p_match->{'pattern'}}->($p_match);
	$p_match->{'guesses'} = _max($guesses, $min_guesses);
	$p_match->{'guesses_log10'} = log($p_match->{'guesses'}) / log(10);

	return $p_match->{'guesses'};
}

# helper: considers whether a length-l sequence ending at match m is better
# (fewer guesses) than previously encountered sequences, updating state if
# so.
sub _update(\%$$\%$) {
	my($p_m, $l, $password,$p_optimal,$_exclude_additive) = @_;
	
	my $k = $p_m->{'j'};
	my $pi = estimate_guesses(%{$p_m}, $password);
	if($l > 1) {
		# we're considering a length-l sequence ending with match m:
		# obtain the product term in the minimization function by
		# multiplying m's guesses by the product of the length-(l-1)
		# sequence ending just before m, at m.i - 1.
		$pi *= $p_optimal->{'pi'}[$p_m->{'i'} - 1]{$l - 1};
	}
	# calculate the minimization func
	my $g = _factorial($l) * $pi;
	unless($_exclude_additive) {
		$g += MIN_GUESSES_BEFORE_GROWING_SEQUENCE ** ($l - 1);
	}

	# update state if new best.
	# first see if any competing sequences covering this prefix, with l or
	# fewer matches, fare better than this sequence. if so, skip it and
	# return.
	while(my($competing_l,$competing_g) = each(%{$p_optimal->{'g'}[$k]})) {
		next  if($competing_l > $l);
		return  if($competing_g <= $g);
	}
	
	# this sequence might be part of the final optimal sequence.
	$p_optimal->{'g'}[$k]{$l} = $g;
	$p_optimal->{'m'}[$k]{$l} = $p_m;
	$p_optimal->{'pi'}[$k]{$l} = $pi;
}

# helper: make bruteforce match objects spanning i to j, inclusive.
sub _make_bruteforce_match($$$) {
	my($i, $j, $password) = @_;
	return {
		'pattern'	=>	'bruteforce',
		'token'	=>	substr($password,$i,$j-$i+1),
		'i'	=>	$i,
		'j'	=>	$j,
	};
}

# helper: evaluate bruteforce matches ending at k.
sub _bruteforce_update($$\%$) {
	my($k,$password,$p_optimal, $_exclude_additive) = @_;
	
        # see if a single bruteforce match spanning the k-prefix is optimal.
        my $p_m = _make_bruteforce_match(0, $k, $password);
        _update(%{$p_m}, 1, $password, %{$p_optimal}, $_exclude_additive);
        foreach my $i (1 .. $k) {
		# generate k bruteforce matches, spanning from (i=1, j=k) up to
		# (i=k, j=k). see if adding these new matches to any of the
		# sequences in optimal[i-1] leads to new bests.
		my $p_m = _make_bruteforce_match($i, $k, $password);
		while(my($l, $last_m) = each(%{$p_optimal->{'m'}[$i - 1]})) {
			$l = int($l);

			# corner: an optimal sequence will never have two adjacent
			# bruteforce matches. it is strictly better to have a single
			# bruteforce match spanning the same region: same contribution
			# to the guess product with a lower length.
			# --> safe to skip those cases.
			if(exists($last_m->{'pattern'}) && $last_m->{'pattern'} eq 'bruteforce') {
				next;
			}
			
			# try adding m to this length-l sequence.
			_update(%{$p_m}, $l + 1, $password, %{$p_optimal}, $_exclude_additive);
		}
	}
}

# helper: step backwards through optimal.m starting at the end,
# constructing the final optimal match sequence.
sub _unwind($\%) {
	my($n,$p_optimal) = @_;
	
	my @optimal_match_sequence = ();
	
	my $k = $n - 1;
	# find the final best sequence length and score
	my $l = undef;
	my $g = 'inf' + 0;
	while(my($candidate_l,$candidate_g) = each(%{$p_optimal->{'g'}[$k]})) {
		if($candidate_g < $g) {
			$l = $candidate_l;
			$g = $candidate_g;
		}
	}
	
	while($k >= 0) {
		my $p_m = $p_optimal->{'m'}[$k]{$l};
		unshift(@optimal_match_sequence, $p_m);
		$k = $p_m->{'i'} - 1;
		$l -= 1;
	}

	return \@optimal_match_sequence;
}

=head2 most_guessable_match_sequence

------------------------------------------------------------------------------
search --- most guessable match sequence -------------------------------------
------------------------------------------------------------------------------

takes a sequence of overlapping matches, returns the non-overlapping sequence with
minimum guesses. the following is a O(l_max * (n + m)) dynamic programming algorithm
for a length-n password with m candidate matches. l_max is the maximum optimal
sequence length spanning each prefix of the password. In practice it rarely exceeds 5 and the
search terminates rapidly.

the optimal "minimum guesses" sequence is here defined to be the sequence that
minimizes the following function:

   g = l! * Product(m.guesses for m in sequence) + D^(l - 1)

where l is the length of the sequence.

the factorial term is the number of ways to order l patterns.

the D^(l-1) term is another length penalty, roughly capturing the idea that an
attacker will try lower-length sequences first before trying length-l sequences.

for example, consider a sequence that is date-repeat-dictionary.
 - an attacker would need to try other date-repeat-dictionary combinations,
   hence the product term.
 - an attacker would need to try repeat-date-dictionary, dictionary-repeat-date,
   ..., hence the factorial term.
 - an attacker would also likely try length-1 (dictionary) and length-2 (dictionary-date)
   sequences before length-3. assuming at minimum D guesses per pattern type,
   D^(l-1) approximates Sum(D^i for i in [1..l-1]

------------------------------------------------------------------------------
=cut
sub most_guessable_match_sequence($\@;$) {
	my($password,$p_matches,$_exclude_additive) = @_;
	
	my $n = length($password);
	
	# partition matches into sublists according to ending index j
	my @matches_by_j = map { [] } (1..$n);
	foreach my $p_m (@{$p_matches}) {
		push(@{$matches_by_j[$p_m->['j']]},$p_m)  if(exists($p_m->['j']));
	}
	# small detail: for deterministic output, sort each sublist by i.
	foreach my $p_lst (@matches_by_j) {
		@{$p_lst} = sort { $a->{'i'} <=> $b->{'j'} } @{$p_lst};
	}
	
	my %optimal = (
		# optimal.m[k][l] holds final match in the best length-l match sequence
		# covering the password prefix up to k, inclusive.
		# if there is no length-l sequence that scores better (fewer guesses)
		# than a shorter match sequence spanning the same prefix,
		# optimal.m[k][l] is undefined.
		'm'	=> [ map { {} } (1..$n) ],

		# same structure as optimal.m -- holds the product term Prod(m.guesses
		# for m in sequence). optimal.pi allows for fast (non-looping) updates
		# to the minimization function.
		'pi'	=> [ map { {} } (1..$n) ],

		# same structure as optimal.m -- holds the overall metric.
		'g'	=> [ map { {} } (1..$n) ]
	);
	
	foreach my $k (0..$n-1) {
		foreach my $p_m (@{$matches_by_j[$k]}) {
			if($p_m->{'i'} >0) {
				foreach my $l (@{$optimal{'m'}[$p_m->{'i'} - 1]}) {
					$l = int($l);
					_update(%{$p_m}, $l + 1, $password, %optimal, $_exclude_additive);
				}
			} else {
				_update(%{$p_m}, 1, $password, %optimal, $_exclude_additive);
			}
		}
		_bruteforce_update($k,$password,%optimal, $_exclude_additive);
	}
	
	my $p_optimal_match_sequence = _unwind($n,%optimal);
	my $optimal_l = scalar(@{$p_optimal_match_sequence});
	
	# corner: empty password
	my $guesses = undef;
	if(length($password) == 0) {
		$guesses = 1;
	} else {
		$guesses = $optimal{'g'}[$n - 1]{$optimal_l};
	}
	
	# final result object
	return {
		'password'	=>	$password,
		'guesses'	=>	$guesses,
		'guesses_log10'	=>	log($guesses) / log(10),
		'sequence'	=>	$p_optimal_match_sequence
	};
}

1;
