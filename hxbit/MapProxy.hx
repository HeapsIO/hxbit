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

import hxbit.NetworkSerializable;

@:generic class MapData<K,V> extends BaseProxy {
	public var map : Map<K,V>;
	public function new(map) {
		this.map = map;
	}
}

abstract MapProxy<K,V>(MapData<K,V>) {

	@:noCompletion public var __value(get, never) : Map<K,V>;
	inline function get___value() return this == null ? null : this.map;

	public inline function set(key:K, value:V) {
		this.mark();
		this.map.set(key, value);
	}

	@:arrayAccess public inline function get(key:K) return this.map.get(key);
	public inline function exists(key:K) return this.map.exists(key);
	public inline function remove(key:K) {
		var b = this.map.remove(key);
		if( b ) this.mark();
		return b;
	}

	@:noCompletion public inline function bindHost(o, bit) {
		this.bindHost(o, bit);
	}

	@:noCompletion public inline function unbindHost() {
		this.unbindHost();
	}

	public inline function keys():Iterator<K> {
		return this.map.keys();
	}

	public inline function iterator():Iterator<V> {
		return this.map.iterator();
	}

	public inline function toString():String {
		return this.map.toString();
	}

	@:arrayAccess @:noCompletion public inline function arrayWrite(k:K, v:V):V {
		this.mark();
		this.map.set(k, v);
		return v;
	}

	@:from static inline function fromMap<K,V>(map:Map<K,V>):MapProxy<K,V> {
		if( map == null ) return null;
		return cast new MapData(map);
	}

}
