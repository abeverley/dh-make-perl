#!/usr/bin/make -f

PERL ?= /usr/bin/perl

all: build

Build: Build.PL
	$(PERL) $<

build install test manifest distmeta: Build
	./Build $@

orig:
	[ ! -e debian/rules ] || $(MAKE) -f debian/rules clean
	$(MAKE) Build
	./Build $@

dist: manifest
	./Build $@

clean:
	[ ! -e Build ] || ./Build $@

realclean distclean: clean
	[ ! -e MANIFEST ] || rm MANIFEST
	[ ! -e META.yml ] || rm META.yml

.PHONY: all build install test orig dist manifest clean realclean distclean
# vim: noet
