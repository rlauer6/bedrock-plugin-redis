package BLM::Redis;

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

use Role::Tiny::With;
with 'Bedrock::Role::RedisClient';

use Bedrock::XML;
use Digest::MD5 qw(md5_hex);
use English qw(-no_match_vars);
use HTTP::Date;
use JSON -convert_blessed_universally;
use Scalar::Util qw(reftype);
use Storable qw(thaw freeze);
use parent qw( BLM::Plugin );

__PACKAGE__->follow_best_practice;
__PACKAGE__->mk_accessors(qw(_serialize handle config));

our $VERSION = '1.0.1';

########################################################################
sub init_plugin {
########################################################################
  my ( $self, @args ) = @_;

  $self->custom_options(
    qw(
      export-keys
      json
      no-md5
      no-timestamp
      options
      port
      server
      sock
      storable
      xml
    )
  );

  $self->SUPER::init_plugin(@args);

  # an admitedly confusing name, this holds a hash of values
  # <null:options port 6379 host localhost ... >
  # <plugin:Redis --options=$options>
  my $redis_options = $self->options('options');

  # try to find a Redis configuration
  # 1. --options=
  # 2. Bedrock's global configuration
  # 3. BLM::Startup::RedisSession configuration
  # 4. Just take the defaults for connecting to a Redis server (localhost:6379)

  my $config = eval {

    # <plugin:Redis --options=>
    return $redis_options
      if $redis_options && reftype($redis_options) eq 'HASH';

    # <plugin:Redis> (uses $config object)
    return $self->get__config->{redis}
      if $self->get__config->{redis};

    # <plugin:Redis> (hunt for a .xml configuration file)
    return redis_config();
  };

  if ( !$config || $EVAL_ERROR ) {
    $self->get_logger->warn('no config file found or error reading config...using default values');
    $config = {};
  }

  if ( !$redis_options ) {
    my $options = $self->options();

    if ( $options->{port} ) {
      $config->{port} = $options->{port};
      delete $config->{sock};
    }

    if ( $options->{sock} ) {
      $config->{sock} = $options->{sock};
      delete $config->{port};
    }

    if ( $options->{server} ) {
      $config->{server} = $options->{server};
    }
  }

  my $redis_config = $self->set_config($config);

  my $handle = $self->set_handle( redis_connect($redis_config) );

  $self->set__serialize( \&serialize );

  return $handle;
}

########################################################################
sub publish {
########################################################################
  my ( $self, $topic, $message ) = @_;

  die "publish(topic, message)\n"
    if !$topic || !$message;

  if ( ref $message ) {
    $message = JSON->new->allow_blessed->convert_blessed->encode($message);
  }

  return $self->handle->publish( $topic, $message );
}

########################################################################
sub storable {
########################################################################
  my ( $self, @args ) = @_;

  my $options = $self->options;

  if (@args) {
    $options->{storable} = $args[0];
  }

  return $options->{storable};
}

########################################################################
sub json {
########################################################################
  my ( $self, @args ) = @_;

  my $options = $self->options;

  if (@args) {
    $options->{json} = $args[0];
  }

  return $options->{json};
}

########################################################################
sub xml {
########################################################################
  my ( $self, @args ) = @_;

  my $options = $self->options;

  if (@args) {
    $options->{xml} = $args[0];
  }

  return $options->{xml};
}

########################################################################
sub export_keys {
########################################################################
  my ( $self, @args ) = @_;

  my $options = $self->options;

  if (@args) {
    $options->{'export-keys'} = $args[0];
  }

  return $options->{'export-keys'};
}

########################################################################
sub handle { return shift->get_handle; }
########################################################################

{
  my $json;

  sub serialize {
    my ( $self, $data, $deserialize ) = @_;

    my $serialization_method = $self->serialization_method;

    $json //= JSON->new->allow_blessed->convert_blessed;

    if ($deserialize) {
      return
        if !$data;

      my $metadata = $json->decode($data);
      my ( $method, $value ) = @{$metadata}{qw(method value)};

      return $value
        if $method eq 'raw';

      return $json->pretty->decode($value)
        if $method eq 'json';

      return thaw($value)
        if $method eq 'storable';

      return Bedrock::XML->newFromString($value)
        if $method eq 'xml';

      return $value;
    }
    else {
      if ( $serialization_method eq 'json' && ref $data ) {
        return $json->encode($data);
      }
      elsif ( $serialization_method eq 'storable' && ref $data ) {
        return freeze($data);
      }
      elsif ( $serialization_method eq 'xml' && ref $data ) {
        return Bedrock::XML::writeXMLString($data);
      }
      else {
        return $data;
      }
    }
  }
}

########################################################################
sub serialization_method {
########################################################################
  my ($self) = @_;

  my $options = $self->options();

  my ($method) = grep { defined $options->{$_} } qw(xml json storable);

  return $method // 'json';
}

########################################################################
sub set_key {
########################################################################
  my ( $self, $key, $value, $expire ) = @_;

  my $options = $self->options();

  my $serialized_value = $value;

  $expire //= 0;

  my $method = 'raw';

  if ( ref $value ) {
    $serialized_value = $self->get__serialize->( $self, $value );

    $method = $self->serialization_method;
  }

  my $metadata = {
    expire => $expire,
    method => $method,
    value  => $serialized_value,
    $options->{'no-timestamp'} ? () : ( timestamp => time ),
    $options->{'no-md5'}       ? () : ( md5       => md5_hex($serialized_value) ),
  };

  my $handle = $self->handle;

  my $retval = $handle->set( $key, JSON->new->encode($metadata) );

  if ($expire) {
    $handle->expire( $key, $expire );
  }

  return $retval;
}

########################################################################
sub get_key {
########################################################################
  my ( $self, $key, %options ) = @_;

  my $handle = $self->handle;

  my $value = $handle->get($key);

  my $deserialized_value = eval {
    return $value
      if $options{raw};

    return $self->get__serialize->( $self, $value, 1 )
      if !$options{metadata};

    my $meta_data = eval { JSON->new->decode($value) };

    return $meta_data
      if $options{raw};

    $meta_data->{value} = $self->get__serialize->( $self, $value, 1 );

    return $meta_data;
  };

  if ( $self->options('export-keys') && !$options{raw} ) {
    $self->export( $key, $deserialized_value );
  }

  return $deserialized_value;
}

########################################################################
sub export {
########################################################################
  my ( $self, $key, $value ) = @_;

  if ( !$value ) {
    $value = $self->get_key($key);
  }

  $self->SUPER::export( $key, $value );

  return $value;
}

########################################################################
sub metadata {
########################################################################
  my ( $self, $key ) = @_;

  my $handle = $self->handle;

  my $raw      = $self->get_key( $key, raw => 1 );
  my $metadata = JSON->new->decode($raw);

  $metadata->{expire} = $handle->ttl($key);

  return $metadata;
}

########################################################################
sub last_modified {
########################################################################
  my ( $self, $key ) = @_;

  my $metadata = $self->metadata($key);

  my $timestamp = $metadata->{timestamp};

  return time2str($timestamp);
}

1;

__END__

=pod

=head1 PUBLIC

BLM::Redis - Interface to a Redis server

=head1 SYNOPSIS

 <plugin:Redis>
 <plugin:Redis --port=6379 --server=docker_redis_1 >

 <null:handle $Redis.handle()>
 <null $handle.set('foo', 'bar');

 <null $handle.get('foo')>

=head1 DESCRIPTION

Plugin access to Redis. Can be used to serialize/deserialize Perl
objects to a Redis cache.

See L</CONFIGURATION> for important details on connecting to a Redis server.

The methods presented by this BLM are designed to facilate operations
you might perform in the context of a Bedrock page. For the most part,
these are convenience routines. YOu have full access to the Redis Perl
class via the object returned by the C<handle()> method.

 <null:handle $Redis.handle()>
 <null $handle.set('foo', 'bar')>

This is not the same as:

 <null $Redis.set_key('foo', 'bar')>

The convenience routines store metadata about the object you are
storing. See L</metadata> for more information regarding what data is
stored with your object by the C<set_key()> method.

=head1 METHODS AND SUBROUTINES

=head2 export_keys

Causes the plugin to automatically export keys retrieved from Redis as
Bedrock variables.

=head2 get_key

 get_key(key, [raw])

Retrieves a serialized version of an object from Redis and converts it
to a Perl object.

Set C<raw> to a true value to retrieve the serialized version of the
object. The serialized version will be a JSON object containing some
metadata and the serialized representation of the object.

 {
  "value" : "...",
  "timestamp": ",
  "method" : "json",
  "md5" : "..."
 }

=head2 handle

Retrieve the Redis connection handle.

=head2 json

Causes the plugin to use the L<JSON> class for
serialization/deserialization.

=head2 last_modified

 last_modifed(key)

Returns the last modified date of the object in HTTP date format.

 Sun, 19 Jan 2025 14:40:24 GMT 

=head2 metadata

 metadata(key)

Returns the decoded metadata associated with the the key. The metadata
consists of these keys:

=over 5

=item expires

The number of seconds until expiration. This value is updated each
time you invoke this method.

=item value

The serialized value of the object.

=item md5

The md5 hash of the serialized object.

=item method

The serialization method, one of:

 json
 xml
 storable

=head2 publish

 publish(topic, message)

Publishes a message to a Redis topic. If the message is a reference it
is sent as a serialized JSON string.

=item timestamp

Number of seconds since the epoch when the value was stored.

=back
=head2 set_key

 set_key(key, object, [expire])
 set_key(key)

Stores a serialized version of an object to Redis. Blessed objects
will be stored as plain 'ol Perl objects. If you want to retain their
type you should store them using the 'storable' serialization
method.

 <null $Redis.storable(1)>
 <null $Redis.set_key('input', $input)>

Set the C<expire> value in seconds if you want the key to expire.

=head2 storable

 storable(1)

Set or retrieve the 'storable' setting. When true, enables the plugin
to use the L<Storable> class for serialization/deserialization. Use
this when you want to preserve the type of the object being stored.

=head2 xml

Causes the plugin to use the L<Bedrock::XML> class for
serialization/deserialization.

=head1 CONFIGURATION

The Redis plugin can use either the configuration file used by the
L<BLM::Startup::RedisSession> module (F<redis-session.xm>), or a
C<redis> configuration object in the global Bedrock configuration
object. So somewhere in F<tagx.xml>...

 <object name="redis">
   <scalar name="port">6379</scalar>
   <scalar name="server">localhost</scalar>
 </object>

See L<Redis> for more details regaring connection options.

You can also use the options to the plugin to configure the Redis
client. Using the plugin options is the least flexible way of
connecting as all connection options are not supported.

=over 5

=item C<BLM::Startup::RedisSession> Configuration

 <object>
   <scalar name="binding">session</scalar>
   <scalar name="session">yes</scalar>
   <scalar name="module">BLM::Startup::RedisSession</scalar>
 
   <object name="config">
     <scalar name="verbose">2</scalar>
     <scalar name="param">session</scalar>
 
     <!-- Redis connect information -->
     <scalar name="server">172.25.0.1</scalar>
     <scalar name="port">6379</scalar>
     <scalar name="sock">/path/to/sock</scalar>
     <scalar name="name">connection-name</scalar>
     <object name="cookie">
       <scalar name="path">/</scalar>
       <scalar name="expiry_secs">3600</scalar>
       <scalar name="domain"></scalar>
     </object>
   </object>
 </object>

=item Global Configuration

 <object name="redis">
   <scalar name="port">6379</scalar>
   <scalar name="server">localhost</scalar>
   <scalar name="sock">/path/to/sock</scalar>
   <scalar name="name">connection-name</scalar>
 </object>

=back

=head2 NOTES

=over 5

=item * Use either C<port> or C<sock> but not both. 

=item * Use the C<get_key> and C<set_key> methods to store Perl
objects to Redis. If you want to use the Redis connection directly
call Redis methods by retrieving the handle.

 <plugin:Redis --define-var="handle" >

or

 <null:handle $Redis.handle()>

=item * Use the C<--export-keys> option to export the value of a Redis
key into a Bedrock variable.

 <plugin:Redis --export-keys>
 
 <null $Redis.get_key('foo')>
 <var $foo>

=item * C<get_key> will return the value from the Redis store
immediately for use.

 <var $Redis.get_key('foo')>

=item * Serialization methods can be dynamically changed.

The plugin stores metadata with each object indicating the time the
object was stored and the method used for serialization.  You can get
the raw serialized data from Redis using the handle's C<get> method or
by using the C<get_key> method with the raw option enabled.

=back

=head1 TAG OPTIONS

=over 5

=item --export-keys

When using the C<get_key> method exports the key value as a Bedrock
variable as the key name.

 <null $Redis.get_key('x')>

 <var $x>

=item --no-md5

By default serialized objects are stored with an MD5 hex hash. To
disable this use the C<--no-md5> option.

=item --no-timestamp

By default serialized objects are stored with an timestamp. To
disable this use the C<--no-timestamp> option.

=item --options

Name of a Bedrock hash that contains the Redis configuration.  This
allows you to pass whatever values you require when connection to the
Redis server.

 <hash:redis_config server myserver port 6379>
 <plugin:Redis --options=$redis_config>

=item --port

Port value.

default: 6379

=item --json

Serialize Perl objects as JSON.

When using the C<json> options, Bedrock will use the L<JSON> class.
Blessed objects will be converted if possible to POPOs.

=item --storable

When using the C<storable> option, Bedrock will use the C<freeze()>
and C<store()> methods of the L<Storable> class.

=item --server

Name of the server.  You can include the port value or use the C<--port> option.

default: localhost

=item --sock

Path for Unix domain socket.

Example:

 <plugin:Redis --sock=/path/to/sock>

=item --xml

When using the C<xml> option, Bedrock will use L<Bedrock::XML> to
serialize/deserialize objects to Redis.

=back

=head1 SEE ALSO

L<Redis>, L<Bedrock::Role::RedisClient>, L<Storable>, L<JSON>

=head1 AUTHOR

BIGFOOT - <bigfoot@cpan.org>

=cut
