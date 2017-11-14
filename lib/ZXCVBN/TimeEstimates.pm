#!/usr/bin/perl

use 5.006;
use feature 'unicode_strings';
use strict;
use warnings;

package ZXCVBN::TimeEstimates;

use POSIX qw();

use constant DELTA	=> 5;

sub guesses_to_score($) {
	my($guesses) = @_;
	
	if($guesses < 1e3 + DELTA) {
		# risky password: "too guessable"
		return 0;
	} elsif($guesses < 1e6 + DELTA) {
		# modest protection from throttled online attacks: "very guessable"
		return 1;
	} elsif($guesses < 1e8 + DELTA) {
		# modest protection from unthrottled online attacks: "somewhat
		# guessable"
		return 2;
	} elsif($guesses < 1e10 + DELTA) {
		# modest protection from offline attacks: "safely unguessable"
		# assuming a salted, slow hash function like bcrypt, scrypt, PBKDF2,
		# argon, etc
		return 3;
	} else {
		# strong protection from offline attacks under same scenario: "very
		# unguessable"
		return 4;
	}
}

use constant MINUTE	=> 60.0;
use constant HOUR	=> MINUTE * 60.0;
use constant DAY	=> HOUR * 24.0;
use constant MONTH	=> DAY * 31.0;
use constant YEAR	=> MONTH * 12.0;
use constant CENTURY	=> YEAR * 100.0;

sub display_time($) {
	my($seconds) = @_;
	
	my $display_num = undef;
	my $display_str = undef;
	if($seconds < 1) {
		#$display_num = undef;
		$display_str = 'less than a second';
	} elsif($seconds < MINUTE) {
		my $base = POSIX::round($seconds);
		$display_num = $base;
		$display_str = $base .' second';
	} elsif($seconds < HOUR) {
		my $base = POSIX::round($seconds / MINUTE);
		$display_num = $base;
		$display_str = $base .' minute';
	} elsif($seconds < DAY) {
		my $base = POSIX::round($seconds / HOUR);
		$display_num = $base;
		$display_str = $base .' hour';
	} elsif($seconds < MONTH) {
		my $base = POSIX::round($seconds / DAY);
		$display_num = $base;
		$display_str = $base . ' day';
	} elsif($seconds < YEAR) {
		my $base = POSIX::round($seconds / MONTH);
		$display_num = $base;
		$display_str = $base . ' month';
	} elsif($seconds < CENTURY) {
		my $base = POSIX::round($seconds / YEAR);
		$display_num = $base;
		$display_str = $base . ' year';
	} else {
		#$display_num = undef;
		$display_str = 'centuries';
	}
	
	if(defined($display_num) && $display_num != 1) {
		$display_str .= 's';
	}
	
	return $display_str;
}

sub estimate_attack_times($) {
	my($guesses) = @_;
	
	# Translating it into a floating point number
	$guesses = $guesses + 0.0;
	
	my %crack_times_seconds = (
		'online_throttling_100_per_hour'	=> $guesses / (100.0 / 3600.0),
		'online_no_throttling_10_per_second'	=> $guesses / 10.0,
		'offline_slow_hashing_1e4_per_second'	=> $guesses / 1e4,
		'offline_fast_hashing_1e10_per_second'	=> $guesses / 1e10
	);
	
	my %crack_times_display = map { $_ => display_time($crack_times_seconds{$_}) } keys(%crack_times_seconds);
	
	return {
		'crack_times_seconds'	=> \%crack_times_seconds,
		'crack_times_display'	=> \%crack_times_display,
		'score'	=> guesses_to_score($guesses)
	};
}

1;
