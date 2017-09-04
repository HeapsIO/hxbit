package hxbit;

typedef StatClass = {
	var name : String;
	var props : Array<Stat>;
	var rpcs : Array<Stat>;
}

typedef Stat = {
	var cl : StatClass;
	var name : String;
	var count : Int;
	var bytes : Int;
	var size : Int;
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
			c = { name : Type.getClassName(Type.getClass(o)), props : [], rpcs : [] };
			classes[cid] = c;
		}
		return c;
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
				p.bytes += p.size;
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
		all.sort(function(p1, p2) return p1.count - p2.count);
		var tot = 0;
		for( p in all )
			tot += p.bytes;
		if( print == null )
			print = #if sys Sys.println #else function(str) trace(str) #end;
		print("Network stats:");
		for( p in all )
			print("  "+p.cl.name+"." + p.name+" count = " + p.count + ", bytes = " + p.bytes+" "+hxd.Math.fmt(p.bytes*100.0/tot)+"%");
	}

	public function reset() {
		classes = new Map();
	}

}