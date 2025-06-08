/*
 * Copyright (C)2015-2016 Nicolas Cannasse
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */
package hxbit;

interface ProxyHost {
	public function networkSetBitCond( bit : Int ) : Void;
}

interface ProxyChild {
	public function bindHost( p : ProxyHost, bit : Int ) : Void;
	public function unbindHost() : Void;
}

/** Classes implementing this will not be replicated over the network **/
interface NetworkNoReplication { }

enum abstract Operation(Int) {
	/**
		Allows initiating RPC on client side (only "normal" and "owner" rpc are checked against it).
	**/
	public var RPC = 0;
	/**
		Tells if the client is allowed to call a rpc(server) for this object
	**/
	public var RPCServer = 1;
	/**
		Tells if the client is allowed to call a rpc(owner) for this object
	**/
	public var RPCOwner = 6;
	/**
		Tells if the client is to be the target of the rpc(owner) messages
	**/
	public var Ownership = 2;
	/**
		Tells if the client is allowed to set fields for this object
	**/
	public var SetField = 3;
	/**
		Tells if the client is allowed to enable replication for this object
	**/
	public var Register = 4;
	/**
		Tells if the client is allowed to disable replication for this object
	**/
	public var Unregister = 5;
}

#if !hxbit_manual_build
@:autoBuild(hxbit.Macros.buildNetworkSerializable())
#end
interface NetworkSerializable extends Serializable extends ProxyHost {
	public var __host : NetworkHost;
	public var __bits1 : Int;
	public var __bits2 : Int;
	public var __next : NetworkSerializable;
	public var enableReplication(get, set) : Bool;
	public var enableAutoReplication(get, set) : Bool;
	public function alive() : Void; // user defined

	public function networkFlush( ctx : Serializer ) : Void;
	public function networkSync( ctx : Serializer ) : Void;
	public function networkRPC( ctx : NetworkSerializer, rpcID : Int, clientResult : NetworkHost.NetworkClient ) : Bool;
	public function networkAllow( op : Operation, propId : Int, client : NetworkSerializable ) : Bool;
	public function networkGetName( propId : Int, isRPC : Bool = false ) : String;
	public function networkSetBit( bit : Int ) : Void;

	#if hxbit_visibility
	public var __cachedVisibility : Map<hxbit.NetworkSerializable,Int>;
	public var __dirtyVisibilityGroups : Int;
	public function evalVisibility( group : VisibilityGroup, from : NetworkSerializable ) : Bool;
	public function setVisibilityDirty( group : VisibilityGroup ) : Void;
	public function getVisibilityMask( groups : Int ) : haxe.Int64;
	#end
	public function getNoSaveMask() : haxe.Int64;
}

class BaseProxy implements ProxyHost implements ProxyChild {
	public var obj : ProxyHost;
	public var bit : Int;
	@:noCompletion public inline function networkSetBitCond(_) {
		mark();
	}
	public inline function mark() {
		if( obj != null ) obj.networkSetBitCond(bit);
	}
	public function bindHost(o, bit) {
		if( obj != null && (o != this.obj || bit != this.bit) )
			throw "Binding proxy twice";
		this.obj = o;
		this.bit = bit;
	}
	public function unbindHost() {
		this.obj = null;
	}
	public static function objToString(o:Dynamic) {
		var fl = Reflect.fields(o);
		fl.remove("obj");
		fl.remove("bit");
		for( f in fl.copy() )
			if( StringTools.startsWith(f, "__ref_") || Reflect.field(o, f) == null )
				fl.remove(f);
		return "{" + [for( f in fl ) f + " : " + Reflect.field(o, f)].join(",") + "}";
	}
}

abstract NetworkProperty(Int) {

	public inline function new(x:Int) {
		this = x;
	}

	public inline function toInt() {
		return this;
	}

	@:op(a|b) inline function opOr(a:NetworkProperty) return new NetworkProperty(this | a.toInt());

}

class NetworkSerializer extends Serializer {

	var hasError = false;

	public var enableChecks = true;
	public var error(get, never) : Bool;
	public var errorPropId : Int = -1;
	public var currentTarget : NetworkSerializable;
	var host : NetworkHost;

	public function new(host) {
		super();
		this.host = host;
		forSave = false;
	}

	function get_error() {
		if( !hasError )
			return false;
		hasError = false;
		return true;
	}

	#if hxbit_visibility
	static var GROUPS = VisibilityGroup.createAll();
	override function evalVisibility(s:Serializable):Int {
		if( currentTarget == null )
			return -1;
		var ns = Std.downcast(s, NetworkSerializable);
		if( ns == null )
			return -1;
		if( ns.__cachedVisibility == null )
			ns.__cachedVisibility = new Map();
		var v = ns.__cachedVisibility.get(currentTarget);
		var bits : Int, mask : Int;
		if( v != null ) {
			mask = ns.__dirtyVisibilityGroups;
			if( mask == 0 ) return v;
			bits = v & ~mask;
		} else {
			bits = 0;
			mask = -1;
		}
		var groups = GROUPS;
		for( i in 0...groups.length )
			if( mask & (1<<i) != 0 && ns.evalVisibility(groups[i], currentTarget) )
				bits |= 1 << i;
		ns.__cachedVisibility.set(currentTarget, bits);
		return bits;
	}
	#end

	override function addAnyRef(s:Serializable) {
		if(Std.isOfType(s, NetworkNoReplication))
			s = null;
		super.addAnyRef(s);
	}

	override function addKnownRef(s:Serializable) {
		if(Std.isOfType(s, NetworkNoReplication))
			s = null;
		super.addKnownRef(s);
	}

	override function onNewObject(i:Serializable) {
		@:privateAccess host.onNewObject(i);
	}

	override function onAddNewObject(i:Serializable) {
		@:privateAccess host.onAddNewObject(i);
	}

	public dynamic function onUnboundObject(ns:NetworkSerializable) {
		throw "Can't send unbound object " + ns + " over network";
	}

	override function addObjRef(s:Serializable) {
		if( !enableChecks ) {
			super.addObjRef(s);
			return;
		}
		addUID(s.__uid);
		var ns = Std.downcast(s, NetworkSerializable);
		if( ns != null && ns.__host == null ) {
			if( ns.enableAutoReplication ) {
				ns.__next = null;
				ns.__host = host;
			} else {
				var prev = out;
				out = new haxe.io.BytesBuffer(); // prevent garbaged data from being kept if exception raised
				onUnboundObject(ns);
				// allow to keep going after logging message
				if( ns.enableAutoReplication ) {
					out = prev;
					ns.__next = null;
					ns.__host = host;
				} else {
					throw "assert";
				}
			}
		}
		addBool( refs.exists(s.__uid) );
	}

	override function getObjRef() {
		if( !enableChecks )
			return super.getObjRef();
		var id = getUID();
		if( id == 0 ) return 0;
		var b = getBool();
		if( b && !refs.exists(id) ) {
			hasError = true;
			errorPropId = host == null ? -1 : @:privateAccess host.isSyncingProperty;
			return 0;
		}
		return id;
	}

}
