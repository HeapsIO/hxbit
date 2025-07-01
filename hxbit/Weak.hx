package hxbit;

abstract Weak<T:NetworkSerializable>(UID) {
	public inline function get() : T return resolve(this);
	@:from static inline function from<T:NetworkSerializable>( v : T ) : Weak<T> {
		return cast v?.__uid;
	}
	static function resolve( uid : UID ) : Dynamic {
		var host = NetworkHost.current;
		var r = @:privateAccess host.globalCtx.refs.get(uid);
		if( r == null ) {
			var h = @:privateAccess host.registerHead;
			while( h != null ) {
				if( h.__uid == uid ) return h;
				if( h.__next == h ) break;
				h = h.__next;
			}
		}
		return r;
	}
}

abstract WeakOpt<T:NetworkSerializable>(Null<UID>) {
	public inline function get() : T return this == null ? null : @:privateAccess Weak.resolve(this);
	@:from static inline function from<T:NetworkSerializable>( v : T ) : WeakOpt<T> {
		return cast v?.__uid;
	}
}