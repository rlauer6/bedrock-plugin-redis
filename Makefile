#-*- mode: makefile; -*-

PERL_MODULES = \
    lib/BLM/Startup/RedisSession.pm \
    lib/BLM/Redis.pm \
    lib/Bedrock/Log/Spooler.pm \
    lib/Bedrock/RedisCache.pm \
    lib/Bedrock/Role/RedisClient.pm

SHELL := /bin/bash

.SHELLFLAGS := -ec

VERSION := $(shell cat VERSION)

TARBALL = BLM-Startup-RedisSession-$(VERSION).tar.gz

%.pm: %.pm.in
	sed  's/[@]PACKAGE_VERSION[@]/$(VERSION)/;' $< > $@

$(TARBALL): buildspec.yml $(PERL_MODULES) requires test-requires README.md
	make-cpan-dist.pl -b $<

README.md: lib/BLM/Startup/RedisSession.pm
	pod2markdown $< > $@

include version.mk

clean:
	rm -f *.tar.gz $(PERL_MODULES)
