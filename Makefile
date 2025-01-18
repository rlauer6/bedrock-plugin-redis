#-*- mode: makefile; -*-

PERL_MODULES = \
    lib/BLM/Startup/RedisSession.pm \
    lib/BLM/Redis.pm \
    lib/Bedrock/Log/Spooler.pm \
    lib/Bedrock/RedisCache.pm \
    lib/Bedrock/Role/RedisClient.pm

VERSION := $(shell perl -I lib -MBLM::Startup::RedisSession -e 'print $$BLM::Startup::RedisSession::VERSION;')

TARBALL = BLM-Startup-RedisSession-$(VERSION).tar.gz

$(TARBALL): buildspec.yml $(PERL_MODULES) requires test-requires README.md
	make-cpan-dist.pl -b $<

README.md: lib/BLM/Startup/RedisSession.pm
	pod2markdown $< > $@

clean:
	rm -f *.tar.gz
