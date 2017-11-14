#!/usr/bin/perl

use 5.006;
use feature 'unicode_strings';
use strict;
use warnings;

package ZXCVBN::Feedback;

use ZXCVBN::Scoring;

sub get_dictionary_match_feedback(\%$) {
	my($p_match,$is_sole_match) = @_;
	
	my $warning = '';
	if($p_match->{'dictionary_name'} eq 'passwords')  {
		if($is_sole_match && !exists($p_match->{'l33t'}) && !$p_match->{'reversed'}) {
			if($p_match->{'rank'} <= 10) {
				$warning = 'This is a top-10 common password.';
			} elsif($p_match->{'rank'} <= 100) {
				$warning = 'This is a top-100 common password.';
			} else {
				$warning = 'This is a very common password.';
			}
		} elsif($p_match->{'guesses_log10'} <= 4) {
			$warning = 'This is similar to a commonly used password.';
		}
	} elsif($p_match->{'dictionary_name'} eq 'english') {
		if($is_sole_match) {
			$warning = 'A word by itself is easy to guess.';
		}
	} elsif($p_match->{'dictionary_name'} ~~ ['surnames', 'male_names', 'female_names']) {
		if($is_sole_match) {
			$warning = 'Names and surnames by themselves are easy to guess.';
		} else {
			$warning = 'Common names and surnames are easy to guess.';
		}
	}
	
	my @suggestions = ();
	my $word = $p_match->{'token'};
	if($word =~ $ZXCVBN::Scoring::START_UPPER) {
		push(@suggestions,"Capitalization doesn't help very much.");
	} elsif($word =~ $ZXCVBN::Scoring::ALL_UPPER && lc($word) ne $word) {
		push(@suggestions,"All-uppercase is almost as easy to guess as all-lowercase.");
	}
	
	if($p_match->{'reversed'} && length($word) >= 4) {
		push(@suggestions,"Reversed words aren't much harder to guess.");
	}
	if(exists($p_match->{'l33t'})) {
		push(@suggestions,"Predictable substitutions like '\@' instead of 'a' don't help very much.");
	}
	
	return {
		'warning'	=> $warning,
		'suggestions'	=> \@suggestions
	};
}

sub get_match_feedback(\%$) {
	my($p_match,$is_sole_match) = @_;
	
	if($p_match->{'pattern'} eq 'dictionary') {
		return get_dictionary_match_feedback(%{$p_match},$is_sole_match);
	} elsif($p_match->{'pattern'} eq 'spatial') {
		my $warning = undef;
		if($p_match->{'turns'} == 1) {
			$warning = 'Straight rows of keys are easy to guess.';
		} else {
			$warning = 'Short keyboard patterns are easy to guess.';
		}
		
		return {
			'warning'	=> $warning,
			'suggestions'	=> [
				'Use a longer keyboard pattern with more turns.'
			]
		};
	} elsif($p_match->{'pattern'} eq 'repeat') {
		my $warning = undef;
		if(length($p_match->{'base_token'}) == 1) {
			$warning = 'Repeats like "aaa" are easy to guess.';
		} else {
			$warning = 'Repeats like "abcabcabc" are only slightly harder to guess than "abc".';
		}
		
		return {
			'warning'	=> $warning,
			'suggestions'	=> [
				'Avoid repeated words and characters.'
			]
		};
	} elsif($p_match->{'pattern'} eq 'sequence') {
		return {
			'warning'	=> 'Sequences like "abc" or "6543" are easy to guess.',
			'suggestions'	=> [
				'Avoid sequences.'
			]
		};
	} elsif($p_match->{'pattern'} eq 'regex') {
		if($p_match->{'regex_name'} eq 'recent_year') {
			return {
				'warning'	=> 'Recent years are easy to guess.',
				'suggestions'	=> [
					'Avoid recent years.',
					'Avoid years that are associated with you.'
				]
			};
		}
	} elsif($p_match->{'pattern'} eq 'date') {
		return {
			'warning'	=> 'Dates are often easy to guess.',
			'suggestions'	=> [
				'Avoid dates and years that are associated with you.',
			]
		}
	}
	
	return undef;
}

sub get_feedback($\@) {
	my($score,$p_sequence) = @_;
	
	if(scalar(@{$p_sequence}) == 0) {
		return {
			'warning'	=> '',
			'suggestions'	=> [
				"Use a few words, avoid common phrases.",
				"No need for symbols, digits, or uppercase letters."
			]
		};
	}
	
	if($score > 2) {
		return {
			'warning'	=> '',
			'suggestions'	=> [ ]
		};
	}
	
	my $longest_match = undef;
	foreach my $p_match (@{$p_sequence}) {
		if(!defined($longest_match) || length($p_match->{'token'}) > length($longest_match->{'token'})) {
			$longest_match = $p_match;
		}
	}
	
	my $p_feedback = get_match_feedback(%{$longest_match},scalar(@{$p_sequence}) == 1);
	my $extra_feedback = 'Add another word or two. Uncommon words are better.';
	if(defined($p_feedback)) {
		unshift(@{$p_feedback->{'suggestions'}},$extra_feedback);
		$p_feedback->{'warning'} = ''  unless(exists($p_feedback->{'warning'}));
	} else {
		$p_feedback = {
			'warning'	=> '',
			'suggestions'	=> [ $extra_feedback ]
		};
	}
	
	return $p_feedback;
}


1;
