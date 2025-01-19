#!/usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use English qw(-no_match_vars);
use File::Temp;
use JSON;
use Bedrock::Log::Spooler;

use Role::Tiny::With;
with 'Bedrock::Role::RedisClient';

use Test::More;

my $spooler = eval {
  return Bedrock::Log::Spooler->instance;
};

plan skip_all => 'no Redis server'
  if !$spooler;

our $MESSAGE;

my $redis = redis_connect();

$redis->psubscribe( 'bedrock.*', sub { $MESSAGE = \@_; });

########################################################################
subtest 'publish' => sub {
########################################################################
  
  $spooler->publish_env(1);

  local $ENV{HELLO} = 'World!';

  $spooler->publish( ['message'], foo => 'bar' );

  my $timeout = 5;;

  while ($timeout--) {
    $redis->wait_for_messages(1);
    last if $MESSAGE;
  }

  ok($MESSAGE, 'got a message');

  isa_ok($MESSAGE, 'ARRAY')
    or BAIL_OUT('could not get message');

  is($MESSAGE->[1], 'bedrock.log', 'log message');

  my $message = eval {
    return JSON->new->decode($MESSAGE->[0]);
  };

  ok( !$EVAL_ERROR, 'decoded JSON message');

  isa_ok($message, 'HASH');

  ok($message->{time},'published time of message');

  ok($message->{message}, 'published message');

  is($message->{message}, 'message', 'message is correct');

  is($message->{foo}, 'bar', 'extra details foo=bar');

  my $env = $message->{env};

  ok($env, 'published environment');
  
  $env = eval {
    return JSON->new->decode($env);
  };

  ok($env, 'publish environment as JSON');

  is($env->{HELLO} , 'World!', 'Hello World!');
};

done_testing;

1;

__END__
