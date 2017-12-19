package hxbit;

class EnumFlagsData<T:EnumValue> extends NetworkSerializable.BaseProxy {

	public var value(default, null) : haxe.EnumFlags<T>;

	public function new(i = 0) {
		value = new haxe.EnumFlags(i);
	}

}


abstract EnumFlagsProxy<T:EnumValue>(EnumFlagsData<T>) {

	@:noCompletion public var __value(get, never) : haxe.EnumFlags<T>;

	public inline function new(i = 0) {
		this = new EnumFlagsData(i);
	}

	inline function get___value() return this.value;

	public inline function has(e:T) {
		return __value.has(e);
	}

	public inline function set(e:T) {
		if( !has(e) ) {
			this.mark();
			__value.set(e);
		}
	}

	public inline function unset(e:T) {
		if( has(e) ) {
			this.mark();
			__value.unset(e);
		}
	}

	public inline function toInt() : Int {
		return __value.toInt();
	}

	public inline function toString() {
		return "" + toInt();
	}

	@:noCompletion public inline function bindHost(o, bit) {
		this.bindHost(o, bit);
	}

	@:noCompletion public inline function unbindHost() {
		this.unbindHost();
	}

	@:from static inline function fromFlags<T:EnumValue>( f : haxe.EnumFlags<T> ) {
		return new EnumFlagsProxy<T>(f.toInt());
	}

}
