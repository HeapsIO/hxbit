package hxbit;

typedef StatClass = {
	var name : String;
	var props : Array<Stat>;
	var rpcs : Array<Stat>;
	var schema : Schema;
}

typedef Stat = {
	var cl : StatClass;
	var name : String;
	var count : Int;
	var bytes : Int;
	var size : Int;
}

private enum EmptyEnum {
}

class NetworkStats {

	var classes : Map<Int,StatClass>;
	var curRPC : Stat;

	public function new() {
		classes = new Map();
	}

	function getClass( o : NetworkSerializable ) {
		var cid = o.getCLID();
		var c = classes[cid];
		if( c == null ) {
			c = { name : Type.getClassName(Type.getClass(o)), props : [], rpcs : [], schema : o.getSerializeSchema() };
			classes[cid] = c;
		}
		return c;
	}

	inline function intSize( v : Int ) {
		return (v >= 0 && v < 0x80) ? 1 : 5;
	}

	function isNullable( t : Schema.FieldType ) {
		return switch( t ) {
		case PInt, PFloat, PBool: false;
		default: true;
		}
	}

	function calcPropSize( t : Schema.FieldType, v : Dynamic ) {
		var size = 0;
		switch( t ) {
		case PInt: size += intSize(v);
		case PFloat: size += 4;
		case PBool: size += 1;
		case PString:
			if( v == null )
				size++;
			else {
				var b = haxe.io.Bytes.ofString(v);
				size += intSize(b.length + 1) + b.length;
			}
		case PBytes:
			if( v == null )
				size++;
			else {
				var b : haxe.io.Bytes = v;
				size += intSize(b.length + 1) + b.length;
			}
		case PSerializable(_):
			size += v == null ? 1 : intSize((v:Serializable).__uid);
		case PEnum(_):
			size += v == null ? 1 : intSize(Type.enumIndex(v) + 1);
		case PMap(kt, vt):
			if( v == null )
				size++;
			else {

				if( Std.is(v, hxbit.NetworkSerializable.BaseProxy) ) v = v.map;

				switch( kt ) {
				case PInt:
					var m : Map<Int,Dynamic> = v;
					var keys = Lambda.array({ iterator : m.keys });
					size += intSize(keys.length + 1);
					for( v in keys )
						size += intSize(v) + calcPropSize(vt, m.get(v));
				case PString:
					var m : Map<String,Dynamic> = v;
					var keys = Lambda.array({ iterator : m.keys });
					size += intSize(keys.length + 1);
					for( v in keys )
						size += calcPropSize(kt, v) + calcPropSize(vt, m.get(v));
				default:
					var m : haxe.Constraints.IMap<Dynamic,Dynamic> = v;
					var keys = Lambda.array({ iterator : function() return m.keys() });
					size += intSize(keys.length + 1);
					for( v in keys )
						size += calcPropSize(kt, v) + calcPropSize(vt, m.get(v));
				}
			}
		case PArray(at):

			if( Std.is(v, hxbit.NetworkSerializable.BaseProxy) ) v = v.array;

			var a : Array<Dynamic> = v;
			if( a == null )
				size++;
			else {
				size += intSize(a.length + 1);
				for( v in a ) size += calcPropSize(at, v);
			}
		case PObj(fields):
			if( v == null )
				size++;
			else {
				var fbits = 0;
				var nullables = [for( f in fields ) if( isNullable(f.type) ) f];
				for( i in 0...nullables.length )
					if( Reflect.field(v, nullables[i].name) != null )
						fbits |= 1 << i;
				size += intSize(fbits + 1);
				for( f in fields ) {
					var nidx = nullables.indexOf(f);
					if( nidx >= 0 && fbits & (1 << nidx) == 0 ) continue;
					size += calcPropSize(f.type, Reflect.field(v, f.name));
				}
			}
		case PAlias(t):
			return calcPropSize(t, v);
		case PVector(t):
			if( v == null )
				size++;
			else {
				var v : haxe.ds.Vector<Dynamic> = v;
				size += intSize(v.length + 1);
				for( e in v )
					size += calcPropSize(t, e);
			}
		case PNull(t):
			size += 1 + calcPropSize(t, v);
		case PUnknown:
			throw "assert";
		case PDynamic:
			var s = new hxbit.Serializer();
			@:privateAccess {
				s.begin();
				s.addDynamic(v);
				size += s.out.length;
			}
		case PInt64:
			size += 8;
		case PFlags(_):
			if( Std.is(v, hxbit.NetworkSerializable.BaseProxy) ) v = v.value;
			size += intSize(v);
		case PStruct:
			// TODO
		}
		return size;
	}

	public function sync( o : NetworkSerializable ) {
		var c = getClass(o);
		var i = 0;
		while( 1 << i <= o.__bits ) {
			if( o.__bits & (1 << i) != 0 ) {
				var p = c.props[i];
				if( p == null ) {
					p = { cl : c, name : o.networkGetName(i), count : 0, bytes : 0, size : 0 };
					c.props[i] = p;
				}
				p.count++;
				p.bytes += calcPropSize(c.schema.fieldsTypes[i], Reflect.field(o, p.name));
			}
			i++;
		}
	}

	public function beginRPC( o : NetworkSerializable, id : Int ) {
		var c = getClass(o);
		var r = c.rpcs[id];
		if( r == null ) {
			r = { cl : c, name : o.networkGetName(id, true), count : 0, bytes : 0, size : 0 };
			c.rpcs[id] = r;
		}
		curRPC = r;
		r.count++;
		return r;
	}

	public function endRPC( size : Int ) {
		curRPC.bytes += size;
		curRPC = null;
	}

	function scoreSort( p : Stat ) {
		return p.count * 4 + p.bytes;
	}

	public function dump( ?print ) {
		var all = [];
		for( c in classes ) {
			for( i in 0...c.props.length ) {
				var p = c.props[i];
				if( p != null && p.count > 0 )
					all.push(p);
			}
			for( i in 0...c.rpcs.length ) {
				var p = c.rpcs[i];
				if( p != null && p.count > 0 )
					all.push(p);
			}
		}
		all.sort(function(p1, p2) return scoreSort(p1) - scoreSort(p2));
		var tot = 0;
		for( p in all )
			tot += p.bytes;
		if( print == null )
			print = #if sys Sys.println #else function(str) trace(str) #end;
		print("Network stats:");
		for( p in all )
			print("  "+p.cl.name+"." + p.name+" count = " + p.count + ", bytes = " + p.bytes+" "+(Std.int(p.bytes*1000.0/tot)/10)+"%");
	}

	public function reset() {
		classes = new Map();
	}

}