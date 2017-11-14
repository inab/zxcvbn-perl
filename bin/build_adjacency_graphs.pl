#!/usr/bin/perl


use 5.006;
use feature 'unicode_strings';
use strict;
use warnings;

use Carp qw();
use Data::Dumper;
use List::Util qw(all);

sub usage() {
	return <<EOF ;
constructs AdjacencyGraphs.pm from QWERTY and DVORAK keyboard layouts

usage:
$0 ../lib/ZXCVBN/AdjacencyGraphs.pm
EOF

}

my $qwerty = <<'QWERTY';
`~ 1! 2@ 3# 4$ 5% 6^ 7& 8* 9( 0) -_ =+
    qQ wW eE rR tT yY uU iI oO pP [{ ]} \|
     aA sS dD fF gG hH jJ kK lL ;: '"
      zZ xX cC vV bB nN mM ,< .> /?
QWERTY

my $dvorak = <<'DVORAK';
`~ 1! 2@ 3# 4$ 5% 6^ 7& 8* 9( 0) [{ ]}
    '" ,< .> pP yY fF gG cC rR lL /? =+ \|
     aA oO eE uU iI dD hH tT nN sS -_
      ;: qQ jJ kK xX bB mM wW vV zZ
DVORAK

my $keypad = <<'KEYPAD';
  / * -
7 8 9 +
4 5 6
1 2 3
  0 .
KEYPAD

my $mac_keypad = <<'MAC_KEYPAD';
  = / *
7 8 9 -
4 5 6 +
1 2 3
  0 .
MAC_KEYPAD

=head2 get_slanted_adjacent_coords
returns the six adjacent coordinates on a standard keyboard, where each row is slanted to the
right from the last. adjacencies are clockwise, starting with key to the left, then two keys
above, then right key, then two keys below. (that is, only near-diagonal keys are adjacent,
so g's coordinate is adjacent to those of t,y,b,v, but not those of r,u,n,c.)
=cut
sub get_slanted_adjacent_coords($$) {
	my($x, $y) = @_;
	return [[$x - 1, $y], [$x, $y - 1], [$x + 1, $y - 1], [$x + 1, $y], [$x, $y + 1], [$x - 1, $y + 1]];
}

=head2 get_aligned_adjacent_coords
returns the nine clockwise adjacent coordinates on a keypad, where each row is vert aligned.
=cut
sub get_aligned_adjacent_coords($$) {
	my($x, $y) = @_;
	
	return [[$x - 1, $y], [$x - 1, $y - 1], [$x, $y - 1], [$x + 1, $y - 1], [$x + 1, $y], [$x + 1, $y + 1], [$x, $y + 1],
            [$x - 1, $y + 1]];
}

=head2 build_graph
builds an adjacency graph as a dictionary: {character: [adjacent_characters]}.
adjacent characters occur in a clockwise order.
for example:
* on qwerty layout, 'g' maps to ['fF', 'tT', 'yY', 'hH', 'bB', 'vV']
* on keypad layout, '7' maps to [None, None, None, '=', '8', '5', '4', None]
=cut
sub build_graph($$) {
	my($layout_str, $slanted) = @_;
	
	my %position_table = ();  # maps from tuple (x,y) -> characters at that position.
	my @tokens = split(/\s/,$layout_str);
	my $token_size = 0;
	foreach my $token (@tokens) {
		$token_size = length($token);
		last  if($token_size > 0);
	}
	my $x_unit = $token_size + 1;  # x position unit len is token len plus 1 for the following whitespace.
	my $adjacency_func = $slanted ? \&get_slanted_adjacent_coords : \&get_aligned_adjacent_coords;

	# assert all(len(token) == token_size for token in tokens), 'token len mismatch:\n ' + layout_str
	Carp::croak("token len ($token_size) mismatch:\n".$layout_str)  unless(all { length($_) == 0 || length($_) == $token_size } @tokens);
	
	my @nsplit = split(/\n/,$layout_str);
	my $y = 0;
	foreach my $line (@nsplit) {
		# the way I illustrated keys above, each qwerty row is indented one space in from the last
		my $slant = $slanted ? ($y - 1) : 0;
		
		my @stokens = split(/\s/,$line);
		foreach my $token (@stokens) {
			my $dividend = index($line,$token) - $slant;
			my($x,$remainder);
			
			# Trick to apply integer division
			{
				use integer;
				($x,$remainder) = ($dividend / $x_unit , $dividend % $x_unit);
			}
			
			# assert remainder == 0, 'unexpected x offset for %s in:\n%s' % (token, layout_str)
			# Carp::croak("unexpected x offset for $token in:\n$layout_str")  unless($remainder == 0);
			
			$position_table{$x.'_'.$y} = $token;
		}
		
		$y++;
	}
	
	my %adjacency_graph = ();
	while(my($pos,$chars) = each(%position_table)) {
		my($x,$y) = split(/_/,$pos);
		my @chars = split(//,$chars);
		foreach my $char (@chars) {
			$adjacency_graph{$char} = [];
			my $p_coords = $adjacency_func->($x,$y);
			foreach my $p_coord (@{$p_coords}) {
				# position in the list indicates direction
				# (for qwerty, 0 is left, 1 is top, 2 is top right, ...)
				# for edge chars like 1 or m, insert None as a placeholder when needed
				# so that each character in the graph has a same-length adjacency list.
				my $coord = $p_coord->[0].'_'.$p_coord->[1];
				push(@{$adjacency_graph{$char}},(exists($position_table{$coord}) && $position_table{$coord} ne '') ? $position_table{$coord} : undef);
				#push(@{$adjacency_graph{$char}},exists($position_table{$coord}) ? $position_table{$coord} : undef);
			}
		}
	}
	
	return \%adjacency_graph;
}

sub escapeString($) {
	my $string = shift;
	$string =~ s/\\/\\\\/g;
	$string =~ s/"/\"/g;
}

my @keyboards = (
	['qwerty', $qwerty, 1],
	['dvorak', $dvorak, 1],
	['keypad', $keypad, undef],
	['mac_keypad', $mac_keypad, undef]
);

if(scalar(@ARGV)!=1) {
        print usage();
        exit(0);
}

if(open(my $f,'>:encoding(UTF-8)',$ARGV[0])) {
	my %ADJACENCY_GRAPHS = ();
	
	foreach my $p_keyboard (@keyboards) {
		my($graph_name,$layout_str,$slanted) = @{$p_keyboard};
		
		$ADJACENCY_GRAPHS{$graph_name} = build_graph($layout_str,$slanted);
	}
	
	$Data::Dumper::Terse = 1;
	$Data::Dumper::Sortkeys = 1;
	my $gline = Data::Dumper->Terse(1)->Sortkeys(1)->Dump([\%ADJACENCY_GRAPHS]);
	$gline = substr($gline,1,-2);
	print $f <<'EOF';
#!/usr/bin/perl

use 5.006;
use feature 'unicode_strings';
use strict;
use warnings;

package ZXCVBN::AdjacencyGraphs;

EOF
	print $f <<EOF;
# generated by $0

our %ADJACENCY_GRAPHS = ($gline);

1;
EOF
	close($f);
	exit 0;
} else {
	Carp::croak("Unable to create output file $ARGV[0]. Reason: $!");
}
