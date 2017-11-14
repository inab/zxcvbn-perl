#!/usr/bin/perl

use 5.014;
use feature 'unicode_strings';
use strict;
use warnings;

use Carp qw();

package ZXCVBN;


=head1 NAME

ZXCVBN - A realistic password strength estimator

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

use ZXCVBN::Matching;
use ZXCVBN::Scoring;
use ZXCVBN::TimeEstimates;
use ZXCVBN::Feedback;

=head1 SYNOPSIS

ZXCVBN is a realistic password strength estimator

    use ZXCVBN;
    
    my $stats = zxcvbn('foo.password);

    my $z = ZXCVBN->new();
    
    my $stats2 = $z->check('another.foo.password');
    ...

=head1 EXPORT
=cut

use Exporter 'import';
our @EXPORT = qw(zxcvbn);

{
	my %RANKED_DICTIONARIES = ();
	
	sub zxcvbn($;\@) {
		my($password,$p_user_inputs) = @_;
		
		my $z = ZXCVBN->new(\%RANKED_DICTIONARIES);
		
		return $z->check($password,$p_user_inputs);
	}
}

=head1 SUBROUTINES/METHODS
=cut

sub new(;\%) {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	
	my $p_RANKED_DICTIONARIES = shift;
	
	$p_RANKED_DICTIONARIES = {  }  unless(ref($p_RANKED_DICTIONARIES) eq 'HASH');
	
	my $self = {
		'RANKED_DICTIONARIES'	=>	$p_RANKED_DICTIONARIES
	};
	bless($self,$class);
	
	return $self;
}

sub check($;\@) {
	my $self = shift;
	
	Carp::croak((caller(0))[3].' is an instance method!')  if($^D > 0 && !ref($self));
	
	my($password,$p_user_inputs) = @_;
	
	$p_user_inputs = []  unless(defined($p_user_inputs));
	
	my $start = time();
	
	my @sanitized_inputs = ();
	foreach my $arg (@{$p_user_inputs}) {
		push(@sanitized_inputs,defined($arg) ? $arg.'' : undef);
	}
	
	my %ranked_dictionaries = %{$self->{'RANKED_DICTIONARIES'}};
	# User defined dictionary
	$ranked_dictionaries{'user_inputs'} = ZXCVBN::Matching::build_ranked_dict(@sanitized_inputs);
	
	my $p_matches = ZXCVBN::Matching::omnimatch($password,%ranked_dictionaries);
	
	my $p_result = ZXCVBN::Scoring::most_guessable_match_sequence($password, @{$p_matches});
	$p_result->{'calc_time'} = time() - $start;
	
	my $p_attack_times = ZXCVBN::TimeEstimates::estimate_attack_times($p_result->{'guesses'});
	
	#    for prop, val in attack_times.items():
	#	result[prop] = val
	
	@{$p_result}{keys(%{$p_attack_times})} = values(%{$p_attack_times});
	
	$p_result->{'feedback'} = ZXCVBN::Feedback::get_feedback($p_result->{'score'},@{$p_result->{'sequence'}});
	
	return $p_result;
}

=head2 function1

=cut

sub function1 {
}

=head2 function2

=cut

sub function2 {
}

=head1 AUTHOR

José María Fernández, C<< <jose.m.fernandez at bsc.es> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-zxcvbn-perl at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=ZXCVBN-Perl>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc ZXCVBN


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=ZXCVBN-Perl>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/ZXCVBN-Perl>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/ZXCVBN-Perl>

=item * Search CPAN

L<http://search.cpan.org/dist/ZXCVBN-Perl/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2017 José María Fernández.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU Lesser General Public
License as published by the Free Software Foundation; either
version 2.1 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Lesser General Public License for more details.

You should have received a copy of the GNU Lesser General Public
License along with this program; if not, write to the Free
Software Foundation, Inc.,
51 Franklin Street, Fifth Floor, Boston, MA 02110-1301  USA


=cut

1; # End of ZXCVBN
