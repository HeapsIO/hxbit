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

class ArrayProxyData<T> extends BaseProxy {
	public var array : Array<T>;
	public var length(get,never) : Int;
	public function new(v) {
		array = v;
	}
	inline function get_length() {
		return array.length;
	}
	public function iterator() {
		return array.iterator();
	}
}

@:generic
class ArrayProxyIterator<T> {
	public var a : Array<T>;
	public var index : Int;
	public var count : Int;
	public inline function new(a) {
		this.a = a;
		this.index = 0;
		this.count = a.length;
	}
	public inline function hasNext() return index < count;
	public inline function next() return a[index++];
}

abstract ArrayProxy<T>(ArrayProxyData<T>) {

	@:noCompletion public var __value(get, never) : Array<T>;
	public var length(get, never) : Int;
	inline function get___value() : Array<T> return this == null ? null : this.array;
	inline function get_length() return this.array.length;

	inline function new(a) {
		this = a;
	}

	public inline function concat( a : Array<T> ) {
		return this.array.concat(a);
	}

	public function copy() {
		return new ArrayProxy(new ArrayProxyData(this.array.copy()));
	}

	public function filter( t : T->Bool ) {
		return this.array.filter(t);
	}

	public inline function indexOf(x:T, ?fromIndex) {
		return this.array.indexOf(x, fromIndex);
	}

	public inline function insert(pos:Int,x:T) {
		this.array.insert(pos, x);
		this.mark();
	}

	public inline function iterator() {
		return new ArrayProxyIterator(__value);
	}

	public inline function join( s : String ) {
		return this.array.join(s);
	}

	public inline function lastIndexOf(x:T, ?fromIndex) {
		return this.array.lastIndexOf(x, fromIndex);
	}

	public function map<S>( t : T->S ) {
		return this.array.map(t);
	}

	public function mark() {
		this.mark();
	}

	public inline function pop() : Null<T> {
		this.mark();
		return this.array.pop();
	}

	public inline function push( x : T ) {
		this.array.push(x);
		this.mark();
	}

	public inline function remove( x : T ) {
		var r = this.array.remove(x);
		this.mark();
		return r;
	}

	public inline function reverse() {
		this.array.reverse();
		this.mark();
	}

	public inline function shift() : Null<T> {
		this.mark();
		return this.array.shift();
	}

	public inline function slice( pos : Int, ?end : Int ) : Array<T> {
		return this.array.slice(pos, end);
	}

	public inline function sort(cmp:T->T->Int) {
		this.array.sort(cmp);
		this.mark();
	}

	public inline function splice( pos : Int, len : Int ) : Array<T> {
		this.mark();
		return this.array.splice(pos, len);
	}

	public inline function toString() {
		return this.array.toString();
	}

	public inline function unshift( x : T ) : Void {
		this.mark();
		this.array.unshift(x);
	}

	@:to inline function toIterable() : Iterable<T> {
		return this.array;
	}

	@:noCompletion public inline function bindHost(o, bit) {
		this.bindHost(o, bit);
	}

	@:noCompletion public inline function unbindHost() {
		this.unbindHost();
	}

	@:arrayAccess inline function get(idx:Int) {
		return this.array[idx];
	}

	@:arrayAccess inline function set(idx:Int,v:T) {
		this.array[idx] = v;
		this.mark();
	}

	@:from static inline function fromArray<T>( a : Array<T> ) {
		if( a == null ) return null;
		return new ArrayProxy(new ArrayProxyData(a));
	}
}

abstract ArrayProxy2<T:ProxyChild>(ArrayProxyData<T>) {

	@:noCompletion public var __value(get, never) : Array<T>;
	public var length(get, never) : Int;
	inline function get___value() : Array<T> return this == null ? null : this.array;
	inline function get_length() return this.array.length;

	inline function new(a) {
		this = a;
	}

	inline function bind(v:T) {
		if( v != null ) v.bindHost(this, 0);
	}

	inline function unbind(v:T) {
		if( v != null ) v.unbindHost();
	}

	public inline function concat( a : Array<T> ) {
		return this.array.concat(a);
	}

	public function copy() {
		return new ArrayProxy2(new ArrayProxyData(this.array.copy()));
	}

	public function filter( t : T->Bool ) {
		return this.array.filter(t);
	}

	public inline function indexOf(x:T, ?fromIndex) {
		return this.array.indexOf(x, fromIndex);
	}

	public inline function insert(pos:Int, x:T) {
		bind(x);
		this.array.insert(pos, x);
		this.mark();
	}

	public inline function iterator() {
		return new ArrayProxyIterator(__value);
	}

	public inline function join( s : String ) {
		return this.array.join(s);
	}

	public inline function lastIndexOf(x:T, ?fromIndex) {
		return this.array.lastIndexOf(x, fromIndex);
	}

	public function map<S>( t : T->S ) {
		return this.array.map(t);
	}

	public function mark() {
		this.mark();
	}

	public inline function pop() : Null<T> {
		this.mark();
		var e = this.array.pop();
		unbind(e);
		return e;
	}

	public inline function push( x : T ) {
		bind(x);
		this.array.push(x);
		this.mark();
	}

	public inline function remove( x : T ) {
		var r = this.array.remove(x);
		if( r ) unbind(x);
		this.mark();
		return r;
	}

	public inline function reverse() {
		this.array.reverse();
		this.mark();
	}

	public inline function shift() : Null<T> {
		this.mark();
		var x = this.array.shift();
		unbind(x);
		return x;
	}

	public inline function slice( pos : Int, ?end : Int ) : Array<T> {
		return this.array.slice(pos, end);
	}

	public inline function sort(cmp:T->T->Int) {
		this.array.sort(cmp);
		this.mark();
	}

	public inline function splice( pos : Int, len : Int ) : Array<T> {
		this.mark();
		var objs = this.array.splice(pos, len);
		for( o in objs ) unbind(o);
		return objs;
	}

	public inline function toString() {
		return this.array.toString();
	}

	public inline function unshift( x : T ) : Void {
		this.mark();
		bind(x);
		this.array.unshift(x);
	}

	@:to inline function toIterable() : Iterable<T> {
		return this.array;
	}

	@:noCompletion public inline function bindHost(o,bit) {
		this.obj = o;
		this.bit = bit;
	}

	@:arrayAccess inline function get(idx:Int) {
		return this.array[idx];
	}

	@:arrayAccess inline function set(idx:Int, v:T) {
		unbind(this.array[idx]);
		bind(v);
		this.array[idx] = v;
		this.mark();
	}

	@:from static inline function fromArray<T:ProxyChild>( a : Array<T> ) {
		if( a == null ) return null;
		var p = new ArrayProxy2(new ArrayProxyData(a));
		for( x in a ) p.bind(x);
		return p;
	}
}