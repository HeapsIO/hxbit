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
	public function networkSetBit( bit : Int ) : Void;
}

interface ProxyChild {
	public function bindHost( p : ProxyHost, bit : Int ) : Void;
	public function unbindHost() : Void;
}

@:enum
abstract Operation(Int) {
	/**
		Allows initiating RPC on client side (only "normal" and "owner" rpc are checked against it).
	**/
	public var RPC = 0;
	/**
		Tells if the client is allowed to call a rpc(server) for this object
	**/
	public var RPCServer = 1;
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

@:autoBuild(hxbit.Macros.buildNetworkSerializable())
interface NetworkSerializable extends Serializable extends ProxyHost {
	public var __host : NetworkHost;
	public var __bits : Int;
	public var __next : NetworkSerializable;
	public var enableReplication(get, set) : Bool;
	public function alive() : Void; // user defined

	public function networkFlush( ctx : Serializer ) : Void;
	public function networkSync( ctx : Serializer ) : Void;
	public function networkRPC( ctx : NetworkSerializer, rpcID : Int, clientResult : NetworkHost.NetworkClient ) : Bool;
	public function networkAllow( op : Operation, propId : Int, client : NetworkSerializable ) : Bool;
	public function networkGetName( propId : Int, isRPC : Bool = false ) : String;
}

class BaseProxy implements ProxyHost implements ProxyChild {
	public var obj : ProxyHost;
	public var bit : Int;
	public inline function networkSetBit(_) {
		mark();
	}
	public inline function mark() {
		if( obj != null ) obj.networkSetBit(bit);
	}
	public inline function bindHost(o, bit) {
		this.obj = o;
		this.bit = bit;
	}
	public inline function unbindHost() {
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

	function get_error() {
		if( !hasError )
			return false;
		hasError = false;
		return true;
	}

	override function addObjRef(s:Serializable) {
		if( !enableChecks ) {
			super.addObjRef(s);
			return;
		}
		addInt(s.__uid);
		var ns = Std.instance(s, NetworkSerializable);
		if( ns != null && ns.__host == null ) throw "Can't send unbound object " + s + " over network";
		addBool( refs.exists(s.__uid) );
	}

	override function getObjRef() {
		if( !enableChecks )
			return super.getObjRef();
		var id = getInt();
		if( id == 0 ) return 0;
		var b = getBool();
		if( b && !refs.exists(id) ) {
			hasError = true;
			return 0;
		}
		return id;
	}

}
