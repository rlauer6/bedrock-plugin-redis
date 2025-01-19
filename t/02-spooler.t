#!/usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use English qw(-no_match_vars);
use File::Temp;
use JSON;

use Test::More qw(no_plan);

BEGIN {

  use Module::Loaded;
  use File::Temp qw(tempfile);

  {
    ## no critic (ProhibitNoStrict ProhibitProlonged)
    no strict 'refs';

    my ( $fh, $filename ) = tempfile();

    close $fh;

    *{'Redis::new'} = sub { return bless {}, 'Redis'; };

    *{'Redis::filename'} = sub { return $filename };

    *{'Redis::publish'} = sub {
      my ( $self, @args ) = @_;

      open my $fh, '>>', $filename;
      print {$fh} join "\n", @args;
      close $fh;
    };

    *{'Redis::DESTROY'} = sub { unlink "$filename" };
  }

  mark_as_loaded(Redis);

  use_ok('Bedrock::Log::Spooler');
}

########################################################################
subtest 'publish' => sub {
########################################################################
  my $spooler = Bedrock::Log::Spooler->instance;

  $spooler->channel('test-channel');

  $ENV{'02-SPOOLER'} = $PID;

  $spooler->publish_env(1);
  $spooler->publish( ['message'], foo => 'bar' );

  open my $fh, '<', $spooler->redis_client->filename
    or BAIL_OUT('could open temp file for reading');

  my $channel = <$fh>;
  chomp $channel;
  is( $channel, 'test-channel', 'published to correct channel' );

  my $content = <$fh>;
  close $fh;

  chomp $content;

  my $json = eval { from_json($content); };

  ok( ref($json),          'published JSON content' );
  ok( exists $json->{env}, 'publish %ENV' );

  my $env = eval { from_json( $json->{env} ); };

  ok( ref($env) && $env->{'02-SPOOLER'} eq $PID, 'publish 02-SPOOLER to %ENV' );
};

done_testing;

1;

__END__
