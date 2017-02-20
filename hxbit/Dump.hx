package hxbit;

class Dump extends Serializer {

	var cachedEnum : Map<String, Schema>;
	var drefs : Map<Int,Dynamic>;
	var hids : Map < Int, { name : String, index : Int, schema : Schema }>;
	var hhashed : Map<Int,{name:String, index:Int, schema:Schema }>;
	var hclasses : Map<String,{ name : String, index : Int, schema : Schema }>;

	public function new( data : haxe.io.Bytes ) {
		super();
		setInput(data, 0);
		drefs = new Map();
	}

	public function dumpObj() {
		if( getString() != "HXS" )
			throw "Invalid HXS data";
		var version = getByte();
		if( version != 1 )
			throw "Unsupported HXS version " + version;

		var classes = [], cobjs = [];
		hclasses = new Map();
		hids = new Map();
		hhashed = new Map();
		cachedEnum = new Map();
		while( true ) {
			var clname = getString();
			if( clname == null ) break;
			var index = getCLID();
			var crc = getInt32();
			var cl = { name : clname, index : index, schema : null };
			classes.push(cl);
			hclasses.set(clname, cl);
			hids.set(index, cl);
			hhashed.set(Serializer.hash(clname), cl);
			cobjs.push({ name : clname, crc : StringTools.hex(crc, 8) });
		}

		var schemaDataSize = getInt();
		for( c in classes )
			c.schema = getKnownRef(Schema);

		var objs = [];
		while(true) {
			var o = dumpAnyRef();
			if( o == null ) break;
			objs.push(o);
		}
		return { version : version, classes : cobjs, objs : objs };
	}

	public function dump( file = "dump.json" ) {
		sys.io.File.saveContent(file, haxe.Json.stringify(dumpObj(), "\t"));
	}

	function dumpAnyRef() : Dynamic {
		var id = getInt();
		if( id == 0 )
			return null;
		if( drefs[id] != null )
			return "@"+id;
		var clidx = getCLID();
		var cl = hids[clidx];
		var o = { _ : cl.name, __uid : id };
		drefs[id] = o;
		dumpRefFields(o, cl.schema);
		return o;
	}

	function dumpRef( clname : String, s : Schema ) : Dynamic {
		var id = getInt();
		if( id == 0 ) return null;
		if( drefs[id] != null )
			return "@"+id;
		if( !s.isFinal ) {
			var realIdx = getCLID();
			var c = hhashed.get(realIdx);
			if( c == null ) throw "Missing class " + realIdx + "(" + Serializer.CL_BYID[realIdx] + ")";
			s = c.schema;
			clname = c.name;
		}
		var o = { _ : clname, __uid : id };
		drefs[id] = o;
		dumpRefFields(o, s);
		return o;
	}


	function dumpRefFields( o : Dynamic, schema : Schema ) {
		for( i in 0...schema.fieldsNames.length ) {
			var n = schema.fieldsNames[i];
			var t = schema.fieldsTypes[i];
			var v : Dynamic = readValue(t);
			Reflect.setField(o, n, v);
		}
	}

	override function readValue( t : Schema.FieldType ) : Dynamic {
		switch( t ) {
		case PSerializable(name):
			var c = hclasses.get(name);
			if( c == null ) {
				var cl : Class<Serializable> = cast Type.resolveClass(name);
				if( cl == null )
					throw("Could not find class " + name);
				trace("*** Class " + name+" was not listed in schemas! ***");
				c = { name : name, schema : Type.createEmptyInstance(cl).getSerializeSchema(), index : -1 };
				hclasses.set(name, c);
			}
			return dumpRef(c.name,c.schema);
		case PEnum(name):
			var index = getByte();
			if( index == 0 )
				return null;
			index--;
			var s = cachedEnum.get(name);
			if( s == null ) {
				var ser : Dynamic = Type.resolveClass("hxbit.enumSer." + name.split(".").join("_"));
				if( ser == null ) throw "No enum unserializer found for " + name;
				s = ser.getSchema();
				cachedEnum.set(name, s);
			}
			var name = s.fieldsNames[index];
			var t = s.fieldsTypes[index];
			if( name == null )
				return "????@" + index;
			if( t == null )
				return name;
			var args = switch( t ) { case PObj(fl): [for( f in fl ) readValue(f.type)]; default: throw "assert"; };
			var o = { _ : args };
			Reflect.setField(o, name, "");
			return o;
		case PBytes:
			var bytes = getBytes();
			if( bytes == null )
				return null;
			if( bytes.length < 64 )
				return "0x" + bytes.toHex();
			var crc = haxe.crypto.Md5.make(bytes).toHex();
			sys.io.File.saveBytes(crc + ".bin", bytes);
			return "<" + crc + ">";
		case PMap(_):
			var m : Map.IMap<Dynamic,Dynamic> = super.readValue(t);
			var o = {};
			for( i in m.keys() )
				Reflect.setField(o, "" + i, m.get(i));
			return o;
		default:
			return super.readValue(t);
		}
	}

}