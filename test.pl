#!/usr/bin/perl

use strict;
use warnings;
use Test::Harness qw(&runtests $verbose);

$verbose=0;

runtests @ARGV;
