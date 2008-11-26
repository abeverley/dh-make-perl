PERL ?= /usr/bin/perl

test:
	$(PERL) test.pl t/*.t
