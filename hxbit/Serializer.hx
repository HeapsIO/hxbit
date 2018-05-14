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

#if !macro

class Serializer {

	static var UID = 0;
	static var SEQ = 0;
	static inline var SEQ_BITS = 8;
	static inline var SEQ_MASK = 0xFFFFFFFF >>> SEQ_BITS;

	public static function resetCounters() {
		UID = 0;
		SEQ = 0;
	}

	static inline function allocUID() {
		return (SEQ << (32 - SEQ_BITS)) | (++UID);
	}

	static var CLASSES : Array<Class<Dynamic>> = [];
	static var CL_BYID = null;
	static var CLIDS = null;
	static function registerClass( c : Class<Dynamic> ) {
		if( CLIDS != null ) throw "Too late to register class";
		var idx = CLASSES.length;
		CLASSES.push(c);
		return idx;
	}

	static inline function hash(name:String) {
		var v = 1;
		for( i in 0...name.length )
			v = Std.int(v * 223 + StringTools.fastCodeAt(name,i));

		v = 1 + ((v & 0x3FFFFFFF) % 65423);

		return v;
	}

	static function initClassIDS() {
		var cl = CLASSES;
		var subClasses = [for( c in cl ) []];
		var isSub = [];
		for( i in 0...cl.length ) {
			var c = cl[i];
			while( true ) {
				c = Type.getSuperClass(c);
				if( c == null ) break;
				var idx = cl.indexOf(c);
				if( idx < 0 ) break; // super class is not serializable
				subClasses[idx].push(i);
				isSub[i] = true;
			}
		}

		CLIDS = [for( i in 0...CLASSES.length ) if( subClasses[i].length == 0 && !isSub[i] ) 0 else hash(Type.getClassName(cl[i]))];
		CL_BYID = [];
		for( i in 0...CLIDS.length ) {
			var cid = CLIDS[i];
			if( cid == 0 ) continue;
			if( CL_BYID[cid] != null ) throw "Conflicting CLID between " + Type.getClassName(CL_BYID[cid]) + " and " + Type.getClassName(cl[i]);
			CL_BYID[cid] = cl[i];
		}
	}

	public static function isClassFinal( index : Int ) {
		return CLIDS[index] == 0;
	}

	public var refs : Map<Int,Serializable>;

	/**
		Set this before serializing in order to reaffect object ids starting UID
	**/
	public var remapIds(get, set) : Bool;

	var remapObjs : Map<Serializable,Int>;
	var newObjects : Array<Serializable>;
	var out : haxe.io.BytesBuffer;
	var input : haxe.io.Bytes;
	var inPos : Int;
	var usedClasses : Array<Bool> = [];
	var convert : Array<Convert>;
	var mapIndexes : Array<Int>;
	var knownStructs : Array<StructSerializable>;

	public function new() {
		if( CLIDS == null ) initClassIDS();
	}

	function set_remapIds(b) {
		remapObjs = b ? new Map() : null;
		return b;
	}

	inline function get_remapIds() return remapObjs != null;

	function remap( s : Serializable ) {
		if( remapObjs.exists(s) ) return;
		remapObjs.set(s, s.__uid);
		s.__uid = allocUID();
	}

	public function begin() {
		out = new haxe.io.BytesBuffer();
		refs = new Map();
		knownStructs = [];
	}

	public function end() {
		var bytes = out.getBytes();
		out = null;
		refs = null;
		knownStructs = null;
		return bytes;
	}

	public function setInput(data, pos) {
		input = data;
		inPos = pos;
		if( refs == null ) refs = new Map();
		if( knownStructs == null ) knownStructs = [];
	}

	public function serialize( s : Serializable ) {
		begin();
		addKnownRef(s);
		return out.getBytes();
	}

	public function unserialize<T:Serializable>( data : haxe.io.Bytes, c : Class<T>, startPos = 0 ) : T {
		refs = new Map();
		knownStructs = [];
		setInput(data, startPos);
		return getKnownRef(c);
	}

	public inline function getByte() {
		return input.get(inPos++);
	}

	public inline function addByte(v:Int) {
		out.addByte(v);
	}

	public inline function addInt(v:Int) {
		if( v >= 0 && v < 0x80 )
			out.addByte(v);
		else {
			out.addByte(0x80);
			out.addInt32(v);
		}
	}

	public inline function addInt32(v:Int) {
		out.addInt32(v);
	}

	public inline function addInt64(v:haxe.Int64) {
		out.addInt64(v);
	}

	public inline function addFloat(v:Float) {
		out.addFloat(v);
	}

	public inline function addDouble(v:Float) {
		out.addDouble(v);
	}

	public inline function addBool(v:Bool) {
		addByte(v?1:0);
	}

	public inline function addArray<T>(a:Array<T>,f:T->Void) {
		if( a == null ) {
			addByte(0);
			return;
		}
		addInt(a.length + 1);
		for( v in a )
			f(v);
	}

	public inline function addVector<T>(a:haxe.ds.Vector<T>,f:T->Void) {
		if( a == null ) {
			addByte(0);
			return;
		}
		addInt(a.length + 1);
		for( v in a )
			f(v);
	}

	public inline function getArray<T>(f:Void->T) : Array<T> {
		var len = getInt();
		if( len == 0 )
			return null;
		len--;
		var a = [];
		for( i in 0...len )
			a[i] = f();
		return a;
	}

	public inline function getVector<T>(f:Void->T) : haxe.ds.Vector<T> {
		var len = getInt();
		if( len == 0 )
			return null;
		len--;
		var a = new haxe.ds.Vector<T>(len);
		for( i in 0...len )
			a[i] = f();
		return a;
	}

	public inline function addMap<K,T>(a:Map<K,T>,fk:K->Void,ft:T->Void) {
		if( a == null ) {
			addByte(0);
			return;
		}
		var keys = Lambda.array({ iterator : a.keys });
		addInt(keys.length + 1);
		for( k in keys ) {
			fk(k);
			ft(a.get(k));
		}
	}

	@:extern public inline function getMap<K,T>(fk:Void->K, ft:Void->T) : Map<K,T> {
		var len = getInt();
		if( len == 0 )
			return null;
		var m = new Map<K,T>();
		while( --len > 0 ) {
			var k = fk();
			var v = ft();
			m.set(k, v);
		}
		return m;
	}

	public inline function getBool() {
		return getByte() != 0;
	}

	public inline function getInt() {
		var v = getByte();
		if( v == 0x80 ) {
			v = input.getInt32(inPos);
			inPos += 4;
		}
		return v;
	}

	public inline function skip(size) {
		inPos += size;
	}

	public inline function getInt32() {
		var v = input.getInt32(inPos);
		inPos += 4;
		return v;
	}

	public inline function getInt64() {
		var v = input.getInt64(inPos);
		inPos += 8;
		return v;
	}

	public inline function getDouble() {
		var v = input.getDouble(inPos);
		inPos += 8;
		return v;
	}

	public inline function getFloat() {
		var v = input.getFloat(inPos);
		inPos += 4;
		return v;
	}

	public inline function addString( s : String ) {
		if( s == null )
			addByte(0);
		else {
			var b = haxe.io.Bytes.ofString(s);
			addInt(b.length + 1);
			out.add(b);
		}
	}

	public inline function addBytes( b : haxe.io.Bytes ) {
		if( b == null )
			addByte(0);
		else {
			addInt(b.length + 1);
			out.add(b);
		}
	}

	public inline function addBytesSub( b : haxe.io.Bytes, pos : Int, len : Int ) {
		if( b == null )
			addByte(0);
		else {
			addInt(len + 1);
			out.addBytes(b, pos, len);
		}
	}

	public inline function getString() {
		var len = getInt();
		if( len == 0 )
			return null;
		len--;
		var s = input.getString(inPos, len);
		inPos += len;
		return s;
	}

	public inline function getBytes() {
		var len = getInt();
		if( len == 0 )
			return null;
		len--;
		var s = input.sub(inPos, len);
		inPos += len;
		return s;
	}

	public function getDynamic() : Dynamic {
		switch( getByte() ) {
		case 0:
			return null;
		case 1:
			return false;
		case 2:
			return true;
		case 3:
			return getInt();
		case 4:
			return getFloat();
		case 5:
			var o = {};
			for( i in 0...getInt() )
				Reflect.setField(o, getString(), getDynamic());
			return o;
		case 6:
			return getString();
		case 7:
			return [for( i in 0...getInt() ) getDynamic()];
		case 8:
			return getBytes();
		case x:
			throw "Invalid dynamic prefix " + x;
		}
	}

	public function addDynamic( v : Dynamic ) {
		if( v == null ) {
			addByte(0);
			return;
		}
		switch( Type.typeof(v) ) {
		case TBool:
			addByte((v:Bool) ? 2 : 1);
		case TInt:
			addByte(3);
			addInt(v);
		case TFloat:
			addByte(4);
			addFloat(v);
		case TObject:
			var fields = Reflect.fields(v);
			addByte(5);
			addInt(fields.length);
			for( f in fields ) {
				addString(f);
				addDynamic(Reflect.field(v, f));
			}
		case TClass(c):
			switch( c ) {
			case String:
				addByte(6);
				addString(v);
			case Array:
				addByte(7);
				var a : Array<Dynamic> = v;
				addInt(a.length);
				for( v in a )
					addDynamic(v);
			case haxe.io.Bytes:
				addByte(8);
				addBytes(v);
			default:
				throw "Unsupported dynamic " + c;
			}
		case t:
			throw "Unsupported dynamic " + t;
		}
	}

	public inline function addCLID( clid : Int ) {
		addByte(clid >> 8);
		addByte(clid & 0xFF);
	}

	public inline function getCLID() {
		return (getByte() << 8) | getByte();
	}

	public function addStruct( s : StructSerializable ) {
		if( s == null ) {
			addByte(0);
			return;
		}
		var c : Serializable = Std.is(s, Serializable) ? cast s : null;
		if( c != null ) {
			addByte(1);
			addAnyRef(c);
			return;
		}
		var index = knownStructs.indexOf(s);
		if( index >= 0 ) {
			addByte(2);
			addInt(index);
			return;
		}
		knownStructs.push(s);
		addByte(3);
		var c = Type.getClass(s);
		if( c == null ) throw s + " does not have a class ?";
		addString(Type.getClassName(c));
		@:privateAccess s.customSerialize(this);
		addByte(0xFF);
	}

	public function getStruct<T:StructSerializable>() : T {
		switch( getByte() ) {
		case 0:
			return null;
		case 1:
			return cast this.getAnyRef();
		case 2:
			return cast knownStructs[getInt()];
		case 3:
			var cname = getString();
			var cl = Type.resolveClass(cname);
			if( cl == null ) throw "Missing struct class " + cname;
			var s : StructSerializable = Type.createEmptyInstance(cl);
			knownStructs.push(s);
			@:privateAccess s.customUnserialize(this);
			if( getByte() != 0xFF ) throw "Invalid customUnserialize for "+s;
			return cast s;
		default:
			throw "assert";
		}
	}

	function addObjRef( s : Serializable ) {
		addInt(s.__uid);
	}

	function getObjRef() {
		return getInt();
	}

	public function addAnyRef( s : Serializable ) {
		if( s == null ) {
			addByte(0);
			return;
		}
		if( remapIds ) remap(s);
		addObjRef(s);
		if( refs[s.__uid] != null )
			return;
		refs[s.__uid] = s;
		var index = s.getCLID();
		usedClasses[index] = true;
		addCLID(index); // index
		s.serialize(this);
	}

	public function addKnownRef( s : Serializable ) {
		if( s == null ) {
			addByte(0);
			return;
		}
		if( remapIds ) remap(s);
		addObjRef(s);
		if( refs[s.__uid] != null )
			return;
		refs[s.__uid] = s;
		var index = s.getCLID();
		usedClasses[index] = true;
		var clid = CLIDS[index];
		if( clid != 0 )
			addCLID(clid); // hash
		s.serialize(this);
	}

	public function getAnyRef() : Serializable {
		var id = getObjRef();
		if( id == 0 ) return null;
		if( refs[id] != null )
			return cast refs[id];
		var rid = id & SEQ_MASK;
		if( UID < rid ) UID = rid;
		var clidx = getCLID();
		if( mapIndexes != null ) clidx = mapIndexes[clidx];
		var i : Serializable = Type.createEmptyInstance(CLASSES[clidx]);
		if( newObjects != null ) newObjects.push(i);
		i.__uid = id;
		i.unserializeInit();
		refs[id] = i;
		if( convert != null && convert[clidx] != null )
			convertRef(i, convert[clidx]);
		else
			i.unserialize(this);
		return i;
	}

	public function getRef<T:Serializable>( c : Class<T>, clidx : Int ) : T {
		var id = getObjRef();
		if( id == 0 ) return null;
		if( refs[id] != null )
			return cast refs[id];
		var rid = id & SEQ_MASK;
		if( UID < rid ) UID = rid;
		if( CLIDS[clidx] != 0 ) {
			var realIdx = getCLID();
			c = cast CL_BYID[realIdx];
			if( convert != null ) clidx = (c:Dynamic).__clid; // real class convert
		}
		var i : T = Type.createEmptyInstance(c);
		if( newObjects != null ) newObjects.push(i);
		i.__uid = id;
		i.unserializeInit();
		refs[id] = i;
		if( convert != null && convert[clidx] != null )
			convertRef(i, convert[clidx]);
		else
			i.unserialize(this);
		return i;
	}

	public inline function getKnownRef<T:Serializable>( c : Class<T> ) : T {
		return getRef(c, (c:Dynamic).__clid);
	}

	public function beginSave() {
		begin();
		usedClasses = [];
	}

	public function endSave( savePosition = 0 ) {
		var content = end();
		begin();
		var classes = [];
		var schemas = [];
		var sidx = CLASSES.indexOf(Schema);
		for( i in 0...usedClasses.length ) {
			if( !usedClasses[i] || i == sidx ) continue;
			var c = CLASSES[i];
			var schema = (Type.createEmptyInstance(c) : Serializable).getSerializeSchema();
			schemas.push(schema);
			classes.push(i);
			addKnownRef(schema);
			refs.remove(schema.__uid);
		}
		var schemaData = end();
		begin();
		out.addBytes(content, 0, savePosition);
		addString("HXS");
		addByte(1);
		for( i in 0...classes.length ) {
			var index = classes[i];
			addString(Type.getClassName(CLASSES[index]));
			addCLID(index);
			addInt32(schemas[i].checkSum);
		}
		addString(null);
		addInt(schemaData.length);
		out.add(schemaData);
		out.addBytes(content,savePosition,content.length - savePosition);
		return end();
	}

	public function beginLoad( bytes : haxe.io.Bytes, position = 0 ) {

		setInput(bytes, position);

		var classByName = new Map();
		var schemas = [];
		var mapIndexes = [];
		var indexes = [];
		var needConvert = false;
		var needReindex = false;
		for( i in 0...CLASSES.length ) {
			classByName.set(Type.getClassName(CLASSES[i]), i);
			mapIndexes[i] = i;
		}
		if( getString() != "HXS" )
			throw "Invalid HXS data";
		var version = getByte();
		if( version != 1 )
			throw "Unsupported HXS version " + version;

		while( true ) {
			var clname = getString();
			if( clname == null ) break;
			var index = getCLID();
			var crc = getInt32();
			var ourClassIndex = classByName.get(clname);
			if( ourClassIndex == null ) throw "Missing class " + clname+" found in HXS data";
			var ourSchema = (Type.createEmptyInstance(CLASSES[ourClassIndex]) : Serializable).getSerializeSchema();
			if( ourSchema.checkSum != crc ) {
				needConvert = true;
				schemas[index] = ourSchema;
			}
			if( index != ourClassIndex ) {
				needReindex = true;
				mapIndexes[index] = ourClassIndex;
			}
			indexes.push(index);
		}
		var schemaDataSize = getInt();
		if( needConvert ) {
			convert = [];
			for( index in indexes ) {
				var ourSchema = schemas[index];
				var schema = getKnownRef(Schema);
				refs.remove(schema.__uid);
				if( ourSchema != null )
					convert[mapIndexes[index]] = new Convert(ourSchema, schema);
			}
		} else {
			// skip schema data
			inPos += schemaDataSize;
		}
		if( needReindex )
			this.mapIndexes = mapIndexes;
	}

	public function endLoad() {
		convert = null;
		mapIndexes = null;
		setInput(null, 0);
	}

	function convertRef( i : Serializable, c : Convert ) {
		var values = new haxe.ds.Vector<Dynamic>(c.read.length);
		var writePos = 0;
		for( r in c.read )
			values[r.index] = readValue(r.from);
		var oldOut = this.out;
		out = new haxe.io.BytesBuffer();
		for( w in c.write ) {
			var v : Dynamic;
			if( w.from == null )
				v = w.defaultValue;
			else {
				v = values[w.index];
				if( !w.same ) {
					if( v == null )
						v = w.defaultValue;
					else
						v = convertValue(v, w.from, w.to);
				}
			}
			writeValue(v, w.to);
		}
		var bytes = out.getBytes();
		out = oldOut;
		var oldIn = input;
		var oldPos = inPos;
		setInput(bytes, 0);
		i.unserialize(this);
		setInput(oldIn, oldPos);
	}

	function isNullable( t : Schema.FieldType ) {
		return switch( t ) {
		case PInt, PFloat, PBool: false;
		default: true;
		}
	}

	function convertValue( v : Dynamic, from : Schema.FieldType, to : Schema.FieldType ) : Dynamic {

		if( v == null && isNullable(to) )
			return null;

		if( Convert.sameType(from,to) )
			return v;

		switch( [from, to] ) {
		case [PObj(obj1), PObj(obj2)]:
			var v2 = {};
			for( f in obj2 ) {
				var found = false;
				var field : Dynamic = null;
				for( f2 in obj1 )
					if( f2.name == f.name ) {
						found = true;
						field = convertValue(Reflect.field(v, f2.name), f2.type, f.type);
						break;
					}
				if( !found ) {
					if( f.opt ) continue;
					field = Convert.getDefault(f.type);
				} else if( field == null && f.opt )
					continue;
				Reflect.setField(v2, f.name, field);
			}
			return v2;
		default:
		}
		throw "Cannot convert " + v + " from " + from + " to " + to;
	}

	function readValue( t : Schema.FieldType ) : Dynamic {
		return switch( t ) {
		case PInt64: getInt64();
		case PInt: getInt();
		case PFloat: getFloat();
		case PAlias(t): readValue(t);
		case PBool: getBool();
		case PString: getString();
		case PArray(t): getArray(function() return readValue(t));
		case PVector(t): getVector(function() return readValue(t));
		case PBytes: getBytes();
		case PEnum(name):
			var ser : Dynamic = Type.resolveClass("hxbit.enumSer." + name.split(".").join("_"));
			if( ser == null ) {
				var e = Type.resolveEnum(name);
				// an old enum can be tagged with @skipSerialize in order to allow loading old content.
				// but this will only work if the enum does not have any constructor parameters !
				if( e != null && Reflect.hasField(haxe.rtti.Meta.getType(e), "skipSerialize") ) {
					getInt();
					return null;
				}
				throw "No enum unserializer found for " + name;
			}
			return ser.doUnserialize(this);
		case PSerializable(name): getKnownRef(cast Type.resolveClass(name));
		case PNull(t): getByte() == 0 ? null : readValue(t);
		case PObj(fields):
			var bits = getInt();
			if( bits == 0 )
				return null;
			var o = {};
			bits--;
			var nullables = [for( f in fields ) if( isNullable(f.type) ) f];
			for( f in fields ) {
				var nidx = nullables.indexOf(f);
				if( nidx >= 0 && bits & (1 << nidx) == 0 ) continue;
				Reflect.setField(o, f.name, readValue(f.type));
			}
			return o;
		case PMap(k, v):
			switch( k ) {
			case PInt:
				(getMap(function() return readValue(k), function() return readValue(v)) : Map<Int,Dynamic>);
			case PString:
				(getMap(function() return readValue(k), function() return readValue(v)) : Map<String,Dynamic>);
			case PEnum(_):
				var len = getInt();
				if( len == 0 )
					return null;
				var m = new haxe.ds.EnumValueMap<Dynamic,Dynamic>();
				while( --len > 0 ) {
					var k = readValue(k);
					var v = readValue(v);
					m.set(k, v);
				}
				return m;
			default:
				(getMap(function() return readValue(k), function() return readValue(v)) : Map<{},Dynamic>);
			}
		case PDynamic:
			getDynamic();
		case PFlags(_):
			getInt();
		case PStruct:
			getStruct();
		case PUnknown:
			throw "assert";
		}
	}

	function writeValue( v : Dynamic, t : Schema.FieldType )  {
		switch( t ) {
		case PInt64:
			addInt64(v);
		case PInt:
			addInt(v);
		case PFloat:
			addFloat(v);
		case PAlias(t):
			writeValue(v,t);
		case PBool:
			addBool(v);
		case PString:
			addString(v);
		case PArray(t):
			addArray(v, function(v) return writeValue(v,t));
		case PVector(t):
			addVector(v, function(v) return writeValue(v,t));
		case PBytes:
			addBytes(v);
		case PEnum(name):
			var ser = "hxbit.enumSer." + name.split(".").join("_");
			if( ser == null ) throw "No enum unserializer found for " + name;
			(Type.resolveClass(ser) : Dynamic).doSerialize(this,v);
		case PSerializable(_):
			addKnownRef(v);
		case PNull(t):
			if( v == null ) {
				addByte(0);
			} else {
				addByte(1);
				writeValue(v, t);
			}
		case PObj(fields):
			if( v == null )
				addByte(0);
			else {
				var fbits = 0;
				var nullables = [for( f in fields ) if( isNullable(f.type) ) f];
				for( i in 0...nullables.length )
					if( Reflect.field(v, nullables[i].name) != null )
						fbits |= 1 << i;
				addInt(fbits + 1);
				for( f in fields ) {
					var nidx = nullables.indexOf(f);
					if( nidx >= 0 && fbits & (1 << nidx) == 0 ) continue;
					writeValue(Reflect.field(v, f.name), f.type);
				}
			}
		case PMap(k, t):
			switch( k ) {
			case PInt:
				var v : Map<Int,Dynamic> = v;
				addMap(v, function(v) writeValue(v, k), function(v) writeValue(v, t));
			case PString:
				var v : Map<String,Dynamic> = v;
				addMap(v, function(v) writeValue(v, k), function(v) writeValue(v, t));
			case PEnum(_):
				var v : haxe.ds.EnumValueMap<Dynamic,Dynamic> = v;
				if( v == null ) {
					addByte(0);
					return;
				}
				var keys = Lambda.array({ iterator : v.keys });
				addInt(keys.length + 1);
				for( vk in keys ) {
					writeValue(vk, k);
					writeValue(v.get(vk), t);
				}
			default:
				var v : Map<{},Dynamic> = v;
				addMap(v, function(v) writeValue(v, k), function(v) writeValue(v, t));
			}
		case PDynamic:
			addDynamic(v);
		case PFlags(_):
			addInt(v);
		case PStruct:
			addStruct(v);
		case PUnknown:
			throw "assert";
		}
	}

}

#end
