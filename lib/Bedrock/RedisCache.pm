package Bedrock::RedisCache;
#
#    This file is a part of Bedrock, a server-side web scripting tool.
#    Check out http://www.openbedrock.net
#    Copyright (C) 2024, TBC Development Group, LLC.
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
#

use strict;
use warnings;

use Bedrock qw(slurp_file);
use Bedrock::Constants qw(:booleans);
use English qw(-no_match_vars);
use JSON;
use List::Util qw(any);
use Redis;

__PACKAGE__->follow_best_practice;
__PACKAGE__->mk_accessors(
  qw(
    auto_connect
    cache
    cnx_timeout
    config
    every
    handle
    host
    port
    read_timeout
    reconnect
    socket
    write_timeout
  )
);

use parent qw(Exporter Class::Accessor::Fast);

########################################################################
sub new {
########################################################################
  my ( $class, @args ) = @_;

  my $options = ref $args[0] ? $args[0] : {@args};

  my $config = eval {
    return $options
      if !$options->{config};

    return $options->{config}
      if ref $options->{config};

    return JSON->new->decode( scalar slurp_file $options->{config} );
  };

  die "could not read REDIS config file\n$EVAL_ERROR"
    if !$config || $EVAL_ERROR;

  my $redis_config = init_defaults($config);

  my $self = $class->SUPER::new( { config => $redis_config, %{$redis_config} } );

  return $self
    if !$self->get_auto_connect;

  return $self
    if !$self->get_host && !$self->get_socket;

  my $host = sprintf '%s:%s', $self->get_host, $self->get_port;

  my $socket = $self->get_socket;

  my $reconnect = $self->get_reconnect;
  my $every     = $self->get_every;

  my $cnx_timeout   = $self->get_cnx_timeout;
  my $read_timeout  = $self->get_read_timeout;
  my $write_timeout = $self->get_write_timeout;

  my $handle = Redis->new(
    $socket        ? ( socket        => $socket )        : ( server => $host ),
    $reconnect     ? ( reconnect     => $reconnect )     : (),
    $cnx_timeout   ? ( cnx_timeout   => $cnx_timeout )   : (),
    $read_timeout  ? ( read_timeout  => $read_timeout )  : (),
    $write_timeout ? ( write_timeout => $write_timeout ) : (),
  );

  $self->set_handle($handle);

  return $self;
}

########################################################################
sub init_defaults {
########################################################################
  my ($config) = @_;

  $config //= {};

  $config->{auto_connect} //= $TRUE;

  $config->{cache} //= [];

  $config->{host}   //= $ENV{REDIS_HOST} // 'localhost';
  $config->{port}   //= $ENV{REDIS_PORT} // '6379';
  $config->{socket} //= $ENV{REDIS_SOCKET};

  return $config;
}

########################################################################
sub can_cache_page {
########################################################################
  my ( $self, $uri ) = @_;

  my $cache_list = $self->get_cache // [];

  return any { $uri eq $_ } @{$cache_list};
}

########################################################################
sub cache_page {
########################################################################
  my ( $self, $key, $value ) = @_;

  my $handle = $self->get_handle;

  $handle->set( $key, $value );
  my $ttl = $self->get_config->{ttl};

  return
    if !$ttl;

  return $handle->expireat( $key, time + $ttl );
}

1;

__END__

=pod

=head1 PUBLIC

Bedrock::RedisCache - provides a wrapper class of Redis for Bedrock caching

=head1 SYNOPSIS

 my $redis = Bedrock::RedisCache->new(config => $config_file);

=head1 DESCRIPTION

Provides a wrapper class used by C<Bedrock::Apache::Bedrock> and
C<TagX::Output> to implement page caching. Page caching is only available
when running Bedrock in a web context. You provide a list of URIs that
are acceptable to cache. In a typical Bedrock web application not all
pages may be candidates for caching.  Only pages that are static after
they have been rendered should be considered for caching.

If your pages may be I<somewhat> static you might want to set a cache
expiration value (ttl).

The primary purpose of this class is to provide support for page
caching, but you can use if for whatever you'd like in your
applications (see below).  L<Bedrock::Apache::Bedrock> will
instantiate this class once for each Apache child when that class is
loaded in response to a request.  If the handler is able to connect to
a Redis server then the instatiated object will be stored in Bedrock's
context object (L<Bedrock::Context>) and is therefore available
throughout Bedrock wherever the context object can be found (use the
C<redis()> method of the context object).  That's a fancy way of
saying you may have dig into Bedrock internals if you are trying use
the Redis cache through that object.

A more direct way of accessing the object can be created using an
Application Plugin which gives direct access to the context object via
the C<context()> getter.

 package BLM::Startup::RedisCache;

 use strict;
 use warnings;

 use parent qw(Bedrock::Application::Plugin);

 sub handle {
   my ($self) = @_;

   my $redis = $self->context->redis();
   
   return
     if !$redis;

   return $redis->get_handle;
 }

 sub redis {
   my ($self) = @_;

   return $self->context->redis();
 }

 1;

Drop this in your site's application plugin config directory
(typically /var/www/config.d/startup).

 <object>
   <scalar name="binding">redis</scalar> 
   <scalar name="module">BLM::Startup::RedisCache</scalar> 
 </object> 

Then test:

 <null:handle $redis.handle()>
 <null:keys $handle.keys('*')>

 <foreach --define-index=i --start-index=0 $keys>
 [<var $i>] <var $_><br/>
 </foreach>

=head1 CACHING SUPPORT IN BEDROCK

=head2 Page Caching

Some pages are static after they have been rendered by Bedrock.  You
might use Bedrock to create a page but once it has been assembled it
is relatively static.  To avoid having Bedrock re-assemble pages that
are static once they are rendered, simply add the page URI to the list
of cached pages in the configuration.

After Bedrock renders the page it looks to see if caching is enabled
and if the page just rendered is in the cache list. If so, Bedrock
will add an Etag header containing the MD5 sum of the page
contents. Bedrock will then store the page in Redis using the Etag as
the key.

If a browser makes a request for the page using an Etag, Bedrock will
consult the cache if it is enabled to see if that key exists.  If so,
Bedrock will return a 304 (NOT-MODIFIED) HTTP status code and suspend
further processing.  This process happens as early as possible, even
before Bedrock performs any other actions (like reading config
files).

Page caching can have a significant impact on performance. Consider
using caching for other operations that add to page latency.

=head2 Tags that write to the cache

=over 5

=item <var>

 <var --cache="key-name" $value>

=item <sink>

 <sink --cache="key-name">
 Hello World!
 </sink>

=back

Tags for writing to the cache also support a C<--ttl> option for
setting the expiration of a key.

=head2 Tags that read from cache

=over 5

=item <null>

 <null:foo --cache="key-name">

The C<E<lt>nullE<gt>> tag has options for transforming data.  For
example, to convert a JSON representation to a Perl object use the
C<--json> option.

 <null:customer --cache="customer" --json>

=back

=head2 Other support for caching in Bedrock

The C<--cached> boolean operator can be used to determine if a key is in the cache.

 <if --cached "customer">
   <null:customer --cache="customer" --json>
 <else>
   <null:customer $customer.get($input.id)>
   <sink --cache="customer"><var $customer --json></sink>
 </if>

=head1 CONFIGURATION

Configure the class by creating a JSON file with the configuration values listed below.

The configuration object will be passed to the C<new()> constructor
the first time an Apache child responds to a request.

You can also configure the class by passing the same element shown
below in the constructor or pass a hash reference containing the
values.

 {
   "host" : "10.1.4.100",
   "socket" : "",
   "port" : "6379",
   "cache" : [
      "/",
      "/about"
    ],
    "write_timeout" : 5,
    "read_timeout" : 5,
    "cnx_timeout" : 20,
    "auto_connect" : 1,
    "reconnect" : "",
    "every" : "",
    "ttl" : ""
 }

In practice you don't use this class directly, it is used by
C<Bedrock::Apache::Bedrock>.  All you need to do to enable caching is
create the configuration object and let Bedrock now where it is by
setting an environment variable in the hosts configuration file.

 PerlSetEnv REDIS_CONFIG /var/www/config/redis-cache.json

If there's an error reading the file or the file can't be found,
Bedrock will just continue without caching.

=over 5

=item config

Name of a JSON file containg the configuration values.

=item host

Host name or IP of the Redis server.

default: localhost

=item socket

Socket name if using sockets. Set C<host> or C<socket> but not both.

=item port

Port number for connecting to the Redis server over TCP.

default: 6379

=item cache

An array of strings that represent URIs of pages to cache.

=item write_timeout

Write timeout value is seconds.

default: none

=item read_timeout

Read timeout in seconds

default: none

=item cnx_timeout

Connect timeout value in seconds.

default: none

=item auto_connect

Boolean that indicates whether a connection should be attempted when
the C<new()> constructor is called.

default: true

=item reconnect

Reconnect time in seconds.

default: none

=item every

Used with reconnect to retry connections at a specfied interval (in
microseconds).

default: none

=item ttl

Number of seconds the page should available in the cache.  After this
interval the page will be deleted from the cache.

=back

=head1 METHODS AND SUBROUTINES

=head1 SEE OTHER

L<Bedrock::Role::RedisClient>, L<Redis>

=head1 AUTHOR

Rob Lauer - <bigfoot@cpan.org>

=cut
