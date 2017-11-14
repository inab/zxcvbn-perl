#!/usr/bin/perl

use 5.006;
use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
	module_name         => 'ZXCVBN',
	license             => 'lgpl_2_1',
	dist_author         => q{José María Fernández <jose.m.fernandez@bsc.es>},
	dist_version_from   => 'lib/ZXCVBN.pm',
	release_status      => 'stable',
	configure_requires => {
		'Module::Build' => '0',
	},
	build_requires => {
		'Test::More' => '0',
	},
	requires => {
		'perl'	=>	'5.6.1',
		'Carp'	=>	'0',
		'boolean'	=>	'0',
		'POSIX'	=>	'0',
		#'List::Util'	=>	'0',
		#'ABC'              => '1.6',
		#'Foo::Bar::Module' => '5.0401',
	},
	add_to_cleanup     => [ 'ZXCVBN-Perl-*' ],
);

$builder->create_build_script();
