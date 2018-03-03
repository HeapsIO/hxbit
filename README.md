# HxBit

HxBit is a binary serialization and network synchronization library for Haxe.

## Installation

Install through haxelib with `haxelib install hxbit` and use `-lib hxbit` to use it.

## Serialization

You can serialize objects by implementing the `hxbit.Serializable` interface. You need to specify which fields you want to serialize by using the `@:s` metadata:

```haxe
class User implements hxbit.Serializable {
    @:s public var name : String;
    @:s public var age : Int;
    @:s public var friends : Array<User>;
    ...
}
```

This will automatically add a few methods and variables to your `User` class:

```haxe
/**
  These fields are automatically generated when implementing the interface.
**/
interface Serializable {
	/** Unique identifier for the object, automatically set on new() **/
	public var __uid : Int;
	/** Returns the unique class id for this object **/
	public function getCLID() : Int;
	/** Serialize the object id and fields using this Serializer **/
	public function serialize( ctx : hxbit.Serializer ) : Void;
	/** Unserialize object fields using this Serializer **/  
	public function unserialize( ctx : hxbit.Serializer ) : Void;
	/** Returns the object data schema **/  
	public function getSerializeSchema() : hxbit.Schema;
}
```

This allows you to serialize/unserialize using this code:

```haxe
var s = new hxbit.Serializer();
var bytes = s.serialize(user);
....
var u = new hxbit.Serializer();
var user = u.unserialize(bytes, User);
....
```

### Comparison with haxe.Serializer/Unserializer

Haxe standard library serialization works by doing runtime type checking, which is slower. However it can serialize any value even if it's not been marked as Serializable.

HxBit serialization uses macro to generate strictly typed serialization code that allows very fast I/O. OTOH this increase code size and is using a less readable binary format instead of Haxe standard serialization which uses a text representation.

### Supported types

The following types are supported:

  - Int / haxe.UInt : stored as either 1 byte (0-254) or 5 bytes (0xFF + 32 bits)
  - Float : stored as single precision 32 bits IEEE float
  - Bool : stored as single by (0 or 1)
  - String : stored as size+1 prefix, then utf8 bytes (0 prefix = null)
  - any Enum value : stored as index byte + args values
  - haxe.io.Bytes : stored as size+1 prefix + raw bytes (0 prefix = null)
  - Array&lt;T&gt; and haxe.ds.Vector&lt;T&gt; : stored as size+1 prefix, then T list (0 prefix = null)
  - Map&lt;K,V&gt; : stored as size+1 prefix, then (K,V) pairs (0 prefix = null)
  - Null&lt;T&gt; : stored as a byte 0 for null, 1 followed by T either
  - Serializable (any other serializable instance) : stored with __uid, then class id and data if if was not already serialized
  - Strutures { field : T... } : optimized to store a bit field of not null values, then only defined fields values 

### Default values

When unserializing, the class constructor is not called. If you want to have some non-serialized field already initialized before starting unserialization, you can set the default value using Haxe initializers:

```haxe
class User implements hxbit.Serializable {
    ...
    // when unserializing, someOtherField will be set to [] instead of null
    var someOtherField : Array<Int> = []; 
}
```

### Unsupported types

If you want to serialize unsupported types, you could implement your own serialization through the optional methods `customSerialize` and `customUnserialize`.

```haxe
class Float32ArrayContainer implements hxbit.Serializable {

    public var value:Float32Array;

    ...

    @:keep
    public function customSerialize(ctx : hxbit.Serializer) {
        ctx.addInt(value.length);
        for(i in 0...value.length)
            ctx.addFloat(value[i]);
    }

    @:keep
    public function customUnserialize(ctx : hxbit.Serializer) {
        var length = ctx.getInt();
        var tempArray = new Array<Float>();
        for(i in 0...length)
            tempArray.push(ctx.getFloat());

        value = new Float32Array(tempArray);
    }
}
```

## Versioning

HxBit serialization is capable of performing versioning, by storing in serialized data the schema of each serialized class, then comparing it to the current schema when unserializing, making sure that data is not corrupted.

In order to save some data with versioning, use the following:

```haxe
var s = new hxbit.Serializer();
s.beginSave();
// ... serialize your data...
var bytes = s.endSave();
```

And in order to load versionned data, use:

```haxe
var s = new hxbit.Serializer();
s.beginLoad(bytes);
// .. unserializer your data
```
Versioned data is slightly larger than unversioned one since it contains the Schema data of each serialized class.

Currently versioning handles:
 - removing fields (previous data is ignored)
 - adding fields (they are set to default value: 0 for Int/Float, false for Bool, empty Array/Map/etc.)

More convertions can be easily added in `Serializer.convertValue`, including custom ones if you extends Serializer. 

## Networking

Additionaly to serialization, HxBit supports synchronization of objects over network and Remote Procedure Call.

### Example

An example of networking in action can be found as part of the Heaps samples here: https://github.com/ncannasse/heaps/blob/master/samples/Network.hx

In order to use Networking, your classes need to implement `hxbit.NetworkSerializable`. You also need to implement a `NetworkHost` such as done with Heaps here: https://github.com/ncannasse/heaps/blob/master/hxd/net/SocketHost.hx

### Principles

A host is a `NetworkHost` instance which handles communications betwen a server (or authority) and several clients.

A NetworkSerializable can be shared over the network by setting `enableReplication = true` on it.

When a shared Serializable field is modified, we store a bit to mark it as changed. When host.sync() is called (or when a RPC occurs), we send the modified fields over the network so the objects state is correctly replicated on other connected nodes.

Only the authority can modify the serializable fields and call normal RPCs. By default an object doesn't have any ownership rights, you can define the `networkAllow()` method to specify it.

In order to detect whenever a new object has been shared over the network, you must implement the `alive()` method, which will be triggered once an object has been fully initialized. 

### Remote Procedure Calls (RPC)

RPC can be easily performed by tagging a shared object member method with `@:rpc`:

```haxe
class Cursor implements hxbit.NetworkSerializable {
   @:rpc public function blink() {
      ...
   }
}
```

There are different RPC modes, which can be specified by using `@:rpc(mode)`:

  - `all` (default) : When called on the client, will forward the call on the server, but not execute locally. When called on the server, will forward the call to the clients (and force its execution), then execute.
  - `client` : When called on the server, will forward the call to the clients, but not execute locally. When called on the client, will execute locally. 
  - `server` : When called on the client: will forward the call the server (if networkAllow(RPCServer) allows it), but not execute locally. When called on the server, will execute locally.
  - `owner` : When called on the client: will forward the call to the server (if networkAllow(RPC) allows it), but not execute locally. When called on the server: will forward the call to the owners as defined by networkAllow(Ownership).
  - `immediate` : Like `all` but executes immediately locally
  
Return values are possible unless you are in `all` mode, and will add an extra callback to capture the result asynchronously:

```haxe
   @:rpc(server) public function sendAction( act : String ) : Bool {
   }
   
   ...
   sendAction("test", function(onResult) { ... });
   
```

RPC executing on the client can change network properties on the current object without triggering errors or network data

### Filtering

You might not want to send the property value everytime it is modified. You can specify the following metadata together with `@:s` in order to perform some filtering:

 - `@:increment(value)` only send if the value has changed by more than the increment. For instance if you write `@:increment(10)` the value will only be sent if its tens value change.
 - `@:condSend(cond)` only send if the cond is true. You can use `@:condSend(false)` to disable network sync for this property (but still keep it serializable - for instance for a server only value). You can also use `@:condSend(x > current)` to only send if the value `x` is greater than the last sent value for the current property. You can insert any expression here including calls.  
 - `@:notMutable` is used to disable proxy creation on a property (see below)
 
### Proxys

In order to track changes inside a mutable value such as Array/Map/Vector/Structure, a proxy object will be used to wrap the value and make sure that all changes to it correctly set the mark bit.

At the moment, each change in one of these structures will send the whole content again. In the future it might be possible to track each mutation and only send the information necessary to replicate this specific change.

### Local change

Sometimes you might want to perform some local change without triggering network data. You must be sure that the same changes occur on the server and all the connected clients or else you risk having unsynchronized states. 

This can be performed by wrapping the changes as the following example shows:

```haxe
function teleport( t : Target ) {
    networkLocalChanges(function() {
       var pos = t.getPosition();
       // changes to x/y will not be sent over the network
       // clients are also allowed to change serialized properties this way
       x = pos.x;
       y = pos.y;
    });
}
```

### Cancel change

You can also cancel the change of a property can calling `networkCancelProperty(propId)` the id of the property can be obtained from its name by accessing `networkProp<Name>`, with name being the name of the property with first letter uppercased (`networkPropPosition` for `position` for instance)

### Save and load

The whole set of currently shared network objects can be saved using host.saveState() and loaded using host.loadState(bytes). It uses the versionning decribed previously. Once loaded, call host.makeAlive() to make sure all alive() calls are made to object.

