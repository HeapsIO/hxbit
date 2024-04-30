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

#if (hl && hxbit64)

private class NativeKeyValueIterator {
	var map : hl.types.Int64Map;
	var keys : hl.NativeArray<haxe.Int64>;
	var pos : Int;
	var count : Int;

	public inline function new(map) {
		this.map = map;
		keys = map.keysArray();
		pos = 0;
		count = keys.length;
	}
	public inline function hasNext() {
		return pos < count;
	}
	public inline function next() {
		var k = keys[pos++];
		return {key:k, value:map.get(k)};
	}
}

abstract UIDMap(hl.types.Int64Map) {
	public inline function new() {
		this = new hl.types.Int64Map();
	}
	@:arrayAccess public inline function get( id : UID ) : Serializable {
		return this.get(id);
	}
	@:arrayAccess public inline function set( id : UID, v : Serializable ) {
		this.set(id,v);
		return v;
	}
	public inline function remove( id : UID ) {
		return this.remove(id);
	}
	public inline function exists( id : UID ) {
		return this.exists(id);
	}
	public inline function iterator() {
		return new hl.NativeArray.NativeArrayIterator<Serializable>(cast this.valuesArray());
	}
	public inline function keyValueIterator() {
		return new NativeKeyValueIterator(this);
	}
}
#else
typedef UIDMap = Map<UID,Serializable>;
#end

class Serializer {

	#if hxbit_host_mt
	static var UID(get,set) : UID;
	static var SEQ(get,set) : UID;
	static var __UID = new sys.thread.Tls<UID>();
	static var __SEQ = new sys.thread.Tls<UID>();
	static inline function get_UID() return __UID.value;
	static inline function get_SEQ() return __SEQ.value;
	static inline function set_UID(v:UID) { __UID.value = v; return v; }
	static inline function set_SEQ(v:UID) { __SEQ.value = v; return v; }
	#else
	static var UID : UID = 0;
	static var SEQ : UID = 0;
	#end
	static inline var SEQ_BITS = 8;
	static inline var SEQ_MASK = (-1:UID) >>> SEQ_BITS;

	public static function resetCounters() {
		UID = 0;
		SEQ = 0;
	}

	static inline function allocUID() : UID {
		UID += 1;
		return (SEQ << (#if hxbit64 64 #else 32 #end - SEQ_BITS)) | (UID);
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

	static var __SIGN = null;
	public static function getSignature() : haxe.io.Bytes {
		if( __SIGN != null ) return __SIGN;
		var s = new Serializer();
		s.begin();
		s.addInt(CLASSES.length);
		for( i in 0...CLASSES.length ) {
			s.addInt(CLIDS[i]);
			s.addInt32((Type.createEmptyInstance(CLASSES[i]) : Serializable).getSerializeSchema().checkSum);
		}
		return __SIGN = haxe.crypto.Md5.make(s.end());
	}

	public static function isClassFinal( index : Int ) {
		return CLIDS[index] == 0;
	}

	public var refs : UIDMap;

	/**
		Set this before serializing in order to reaffect object ids starting UID
	**/
	public var remapIds(get, set) : Bool;

	var remapObjs : Map<Serializable,UID>;
	var newObjects : Array<Serializable>;
	var out : haxe.io.BytesBuffer;
	var input : haxe.io.Bytes;
	var inPos : Int;
	var usedClasses : Array<Bool> = [];
	var usedEnums : Map<String,Bool> = [];
	var convert : Array<Convert>;
	var enumConvert : Map<String,Convert.EnumConvert> = [];
	var mapIndexes : Array<Int>;
	#if hxbit_visibility
	var visibilityGroups : Int = -1;
	var hasVisibility : Bool;
	#end
	public var forSave : Bool = true;

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
		refs = new UIDMap();
	}

	public function end() {
		var bytes = out.getBytes();
		out = null;
		refs = null;
		return bytes;
	}

	public function setInput(data, pos) {
		input = data;
		inPos = pos;
		if( refs == null ) refs = new UIDMap();
	}

	public function serialize( s : Serializable ) {
		begin();
		addKnownRef(s);
		return out.getBytes();
	}

	public function unserialize<T:Serializable>( data : haxe.io.Bytes, c : Class<T>, startPos = 0 ) : T {
		refs = new UIDMap();
		setInput(data, startPos);
		return getKnownRef(c);
	}

	public inline function getByte() {
		return input.get(inPos++);
	}

	public function addByte(v:Int) {
		out.addByte(v);
	}

	public inline function addUID(v:UID) {
		#if hxbit64
		out.addInt64(v);
		#else
		addInt(v);
		#end
	}

	public inline function getUID() : UID {
		#if hxbit64
		var v = input.getInt64(inPos);
		inPos += 8;
		return v;
		#else
		return getInt();
		#end
	}

	public function addInt(v:Int) {
		if( v >= 0 && v < 0x80 )
			out.addByte(v);
		else {
			out.addByte(0x80);
			out.addInt32(v);
		}
	}

	public function addInt32(v:Int) {
		out.addInt32(v);
	}

	public function addInt64(v:haxe.Int64) {
		out.addInt64(v);
	}

	public function addFloat(v:Float) {
		out.addFloat(v);
	}

	public function addDouble(v:Float) {
		out.addDouble(v);
	}

	public function addBool(v:Bool) {
		out.addByte(v?1:0);
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
		var keys = [for (k in a.keys()) k];
		addInt(keys.length + 1);
		for( k in keys ) {
			fk(k);
			ft(a.get(k));
		}
	}

	extern public inline function getMap<K,T>(fk:Void->K, ft:Void->T) : Map<K,T> {
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

	public function getInt() {
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

	public function addString( s : String ) {
		if( s == null )
			out.addByte(0);
		else {
			var b = haxe.io.Bytes.ofString(s);
			addInt(b.length + 1);
			out.add(b);
		}
	}

	public function addBytes( b : haxe.io.Bytes ) {
		if( b == null )
			out.addByte(0);
		else {
			addInt(b.length + 1);
			out.add(b);
		}
	}

	public function addBytesSub( b : haxe.io.Bytes, pos : Int, len : Int ) {
		if( b == null )
			out.addByte(0);
		else {
			addInt(len + 1);
			out.addBytes(b, pos, len);
		}
	}

	public function getString() {
		var len = getInt();
		if( len == 0 )
			return null;
		len--;
		var s = input.getString(inPos, len);
		inPos += len;
		return s;
	}

	public function getBytes() {
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
		case 9:
			var v : Dynamic = getAnyRef();
			#if hl
			if( hl.Type.getDynamic(v).kind == HVirtual ) {
				var real : Dynamic = hl.Api.getVirtualValue(v);
				if( real != null ) v = real;
			}
			#end
			return v;
		case 10:
			var ename = getString();
			var ser : Dynamic = getEnumClass(ename);
			if( ser == null )
				throw "Unsupported enum "+ename;
			return ser.doUnserialize(this);
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
				if( Std.isOfType(v,Serializable) ) {
					addByte(9);
					addAnyRef(v);
				} else
					throw "Unsupported dynamic " + c;
			}
		case TEnum(e):
			var ename = e.getName();
			var ser : Dynamic = getEnumClass(ename);
			if( ser == null )
				throw "Unsupported enum "+ename;
			addByte(10);
			addString(ename);
			ser.doSerialize(this, v);
		case t:
			throw "Unsupported dynamic " + t;
		}
	}

	public function addCLID( clid : Int ) {
		out.addByte(clid >> 8);
		out.addByte(clid & 0xFF);
	}

	public function getCLID() {
		return (getByte() << 8) | getByte();
	}

	public function addCustom( s : CustomSerializable ) {
		if( s == null ) {
			addByte(0);
			return;
		}
		addByte(3);
		var c = Type.getClass(s);
		if( c == null ) throw s + " does not have a class ?";
		addString(Type.getClassName(c));
		@:privateAccess s.customSerialize(this);
		addByte(0xFF);
	}

	public function getCustom<T:CustomSerializable>() : T {
		switch( getByte() ) {
		case 0:
			return null;
		case 3:
			var cname = getString();
			var cl = Type.resolveClass(cname);
			if( cl == null ) throw "Missing struct class " + cname;
			var s : CustomSerializable = Type.createEmptyInstance(cl);
			@:privateAccess s.customUnserialize(this);
			if( getByte() != 0xFF ) throw "Invalid customUnserialize for "+s;
			return cast s;
		default:
			throw "assert";
		}
	}

	function addObjRef( s : Serializable ) {
		addUID(s.__uid);
	}

	function getObjRef() {
		return getUID();
	}

	#if hxbit_visibility
	inline function addVisBits(v) {
		addInt(v);
	}
	inline function getVisBits() {
		return getInt();
	}
	function evalVisibility( s : Serializable ) {
		return -1;
	}
	#end


	inline function addRef( s : Serializable, forceCLID : Bool ) {
		if( s == null ) {
			addUID(0);
			return;
		}
		if( remapIds ) remap(s);
		addObjRef(s);
		var r = refs[s.__uid];
		if( r != null ) {
			#if hxbit_check_ref
			if( r != s ) {
				s.__uid = allocUID();
				throw r+" and "+s+" have same id";
			}
			#end
			return;
		}
		refs[s.__uid] = s;
		var index = s.getCLID();
		usedClasses[index] = true;
		if( forceCLID )
			addCLID(index); // index
		else {
			var clid = CLIDS[index];
			if( clid != 0 )
				addCLID(clid); // hash
		}
		#if hxbit_visibility
		var prevVis = visibilityGroups;
		if( hasVisibility ) {
			visibilityGroups = evalVisibility(s);
			addVisBits(visibilityGroups);
		}
		#end
		s.serialize(this);
		#if hxbit_visibility
		visibilityGroups = prevVis;
		#end
		onAddNewObject(s);
	}

	public function addAnyRef( s : Serializable ) {
		addRef(s,true);
	}

	public function addKnownRef( s : Serializable ) {
		addRef(s,false);
	}

	inline function makeRef(id:UID, clidx:Int) : Serializable {
		var rid = id & SEQ_MASK;
		if( UID < rid && !remapIds ) UID = rid;
		var i : Serializable = Type.createEmptyInstance(CLASSES[clidx]);
		if( newObjects != null ) newObjects.push(i);
		i.__uid = id;
		i.unserializeInit();
		refs[id] = i;
		if( remapIds ) remap(i);
		#if hxbit_visibility
		var prevVis = visibilityGroups;
		if( hasVisibility )
			visibilityGroups = getVisBits();
		#end
		if( convert != null && convert[clidx] != null )
			convertRef(i, convert[clidx]);
		else
			i.unserialize(this);
		#if hxbit_visibility
		visibilityGroups = prevVis;
		#end
		onNewObject(i);
		return i;
	}

	function onNewObject( i : Serializable ) {
	}

	function onAddNewObject( i : Serializable ) {
	}

	public function getAnyRef() : Serializable {
		var id = getObjRef();
		if( id == 0 ) return null;
		if( refs[id] != null )
			return cast refs[id];
		var clidx = getCLID();
		if( mapIndexes != null ) clidx = mapIndexes[clidx];
		return makeRef(id, clidx);
	}

	public function getRef<T:Serializable>( c : Class<T>, clidx : Int ) : T {
		var id = getObjRef();
		if( id == 0 ) return null;
		if( refs[id] != null )
			return cast refs[id];
		if( convert != null && convert[clidx] != null ) {
			var conv = convert[clidx];
			if( conv.hadCID ) {
				var realIdx = getCLID();
				if( conv.hasCID ) {
					c = cast CL_BYID[realIdx];
					clidx = (c:Dynamic).__clid;
				}
			}
		} else {
			if( CLIDS[clidx] != 0 ) {
				var realIdx = getCLID();
				c = cast CL_BYID[realIdx];
				clidx = (c:Dynamic).__clid;
			}
		}
		return cast makeRef(id, clidx);
	}

	public inline function getKnownRef<T:Serializable>( c : Class<T> ) : T {
		return getRef(c, (c:Dynamic).__clid);
	}

	public function beginSave() {
		begin();
		usedClasses = [];
		usedEnums = [];
	}

	public function endSave( savePosition = 0 ) {
		var content = end();
		begin();
		var classes = [], enums = [];
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
		for( name in usedEnums.keys() ) {
			if( name == "hxbit.PropTypeDesc" ) continue;
			var schema : hxbit.Schema = (getEnumClass(name) : Dynamic).getSchema();
			schemas.push(schema);
			addKnownRef(schema);
			refs.remove(schema.__uid);
			enums.push(name);
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
		for( i in 0...enums.length ) {
			addString(enums[i]);
			addCLID(0);
			addInt32(schemas[i+classes.length].checkSum);
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
		var enumSchemas = [];
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
			if( ourClassIndex == null ) {
				if( index == 0 ) {
					var enumCl = getEnumClass(clname);
					if( enumCl != null ) {
						var ourSchema : hxbit.Schema = (enumCl : Dynamic).getSchema();
						if( ourSchema.checkSum != crc )
							needConvert = true;
						else
							ourSchema = null;
						enumSchemas.push({ name : clname, ourSchema : ourSchema });
						continue;
					}
				}
				throw "Missing class "+clname+" found in HXS data";
			}
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
			remapIds = false;
			convert = [];
			for( index in indexes ) {
				var ourSchema = schemas[index];
				var schema = getKnownRef(Schema);
				refs.remove(schema.__uid);
				if( ourSchema != null )
					convert[mapIndexes[index]] = new Convert(Type.getClassName(CLASSES[mapIndexes[index]]),ourSchema, schema);
			}
			for( e in enumSchemas ) {
				var schema = getKnownRef(Schema);
				refs.remove(schema.__uid);
				if( e.ourSchema != null )
					enumConvert[e.name] = new Convert.EnumConvert(e.name, e.ourSchema, schema);
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

	static var EMPTY_MAP = new Map();

	function convertEnum( econv : Convert.EnumConvert ) : Dynamic {
		inPos--;
		var cid = getByte() - 1;
		var c = econv.constructs[cid];
		var values = new haxe.ds.Vector<Dynamic>(c.read.length);
		for( r in c.read )
			values[r.index] = readValue(r.from);
		var newCid = econv.reindex[cid];
		if( newCid < 0 )
			return null; // no longer used constructor
		var bytes = writeConvValues(c, values, newCid + 1);
		var oldIn = input;
		var oldPos = inPos;
		var oldConv = enumConvert;
		enumConvert = EMPTY_MAP;
		setInput(bytes, 0);
		var v : Dynamic = getEnumClass(econv.enumClass).doUnserialize(this);
		setInput(oldIn, oldPos);
		enumConvert = oldConv;
		return v;
	}

	function convertRef( i : Serializable, c : Convert ) {
		var values = new haxe.ds.Vector<Dynamic>(c.read.length);
		for( r in c.read )
			values[r.index] = readValue(r.from);
		var bytes = writeConvValues(c, values);
		var oldIn = input;
		var oldPos = inPos;
		var oldConv = enumConvert;
		enumConvert = EMPTY_MAP;
		setInput(bytes, 0);
		var obj = Reflect.field(i,"oldHxBitFields");
		if( obj != null ) {
			for( r in c.read )
				if( !r.written )
					Reflect.setField(obj,r.path.split(".").pop(),values[r.index]);
		}
		i.unserialize(this);
		setInput(oldIn, oldPos);
		enumConvert = oldConv;
	}

	function writeConvValues( c : Convert, values : haxe.ds.Vector<Dynamic>, ?extraByte ) {
		var oldOut = this.out;
		out = new haxe.io.BytesBuffer();
		if( extraByte != null )
			out.addByte(extraByte);
		for( w in c.write ) {
			var v : Dynamic;
			if( w.from == null )
				v = w.defaultValue;
			else {
				v = values[w.index];
				if( !w.same ) {
					if( v == null )
						v = w.defaultValue;
					else if( w.conv != null )
						v = w.conv(v);
					else
						v = convertValue(w.path, v, w.from, w.to);
				}
			}
			writeValue(v, w.to);
		}
		var bytes = out.getBytes();
		out = oldOut;
		return bytes;
	}

	function isNullable( t : Schema.FieldType ) {
		return switch( t ) {
		case PInt, PFloat, PBool, PFlags(_), PInt64: false;
		case PAlias(t), PAliasCDB(t), PNoSave(t):
			return isNullable(t);
		default: true;
		}
	}

	function convertValue( path : String, v : Dynamic, from : Schema.FieldType, to : Schema.FieldType ) : Dynamic {

		if( v == null )
			return Convert.getDefault(to);

		if( Convert.sameType(from,to) )
			return v;

		var conv = @:privateAccess hxbit.Convert.convFuns.get(path);
		if( conv != null )
			return conv(v);

		switch( [from, to] ) {
		case [PObj(obj1), PObj(obj2)]:
			var v2 = {};
			for( f in obj2 ) {
				var found = false;
				var field : Dynamic = null;
				for( f2 in obj1 )
					if( f2.name == f.name ) {
						found = true;
						field = convertValue(path+"."+f2.name, Reflect.field(v, f2.name), f2.type, f.type);
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
		case [PStruct(name1,obj1), PStruct(name2,obj2)] if( name1 == name2 ):
			var v2 = {};
			for( f in obj2 ) {
				var found = false;
				var field : Dynamic = null;
				for( f2 in obj1 )
					if( f2.name == f.name ) {
						found = true;
						field = convertValue(path+"."+f2.name, Reflect.field(v, f2.name), f2.type, f.type);
						break;
					}
				if( !found )
					field = Convert.getDefault(f.type);
				if( field == null && isNullable(f.type) )
					continue;
				Reflect.setField(v2, f.name, field);
			}
			return v2;
		case [PNull(from),_]:
			return convertValue(path, v, from, to);
		case [_,PNull(to)]:
			return convertValue(path, v, from, to);
		case [PInt, PFloat]:
			return (v:Int) * 1.0;
		case [PBool, PInt]:
			return (v:Bool) ? 1 : 0;
		case [PBool, PFloat]:
			return (v:Bool) ? 1. : 0.;
		case [PFloat, PInt]:
			return Std.int(v);
		case [PFloat, PInt64]:
			return haxe.Int64.ofInt(Std.int((v:Float)));
		case [PInt, PInt64]:
			return ((v:Int):haxe.Int64);
		case [PInt64, PInt]:
			return haxe.Int64.toInt((v:haxe.Int64));
		case [PInt64, PFloat]:
			return haxe.Int64.toInt((v:haxe.Int64)) * 1.0;
		case [PSerializable(_),PSerializable(to)]:
			var cl = Type.resolveClass(to);
			if( cl == null ) throw "Missing target class "+to;
			var v2 = #if haxe4 Std.downcast #else Std.instance #end(v, cl);
			if( v2 != null ) return v2;
		case [PArray(from),PArray(to)]:
			var arr : Array<Dynamic> = v;
			var path = path+"[]";
			return [for( v in arr ) convertValue(path, v,from,to)];
		case [PAlias(from)|PAliasCDB(from),_]:
			return convertValue(path, v, from, to);
		case [_,PAlias(to)|PAliasCDB(to)]:
			return convertValue(path, v, from, to);
		case [PMap(ft,fv),PMap(tt,tv)] if( Convert.sameType(ft,tt) ):
			var path = path+"[]";
			switch( ft ) {
			case PString:
				var v : Map<String,Dynamic> = v;
				var v2 = new Map<String,Dynamic>();
				for( k in v.keys() )
					v2.set(k, convertValue(path,v.get(k),fv,tv));
				return v2;
			case PInt:
				var v : Map<Int,Dynamic> = v;
				var v2 = new Map<Int,Dynamic>();
				for( k in v.keys() )
					v2.set(k, convertValue(path,v.get(k),fv,tv));
				return v2;
			case PSerializable(_), PObj(_):
				var v : Map<{},Dynamic> = v;
				var v2 = new Map<{},Dynamic>();
				for( k in v.keys() )
					v2.set(k, convertValue(path,v.get(k),fv,tv));
				return v2;
			case PEnum(_):
				var v : haxe.ds.EnumValueMap<Dynamic,Dynamic> = v;
				var v2 = new haxe.ds.EnumValueMap<Dynamic,Dynamic>();
				for( k in v.keys() )
					v2.set(k, convertValue(path,v.get(k),fv,tv));
				return v2;
			default:
				// todo
			}
		default:
		}

		throw 'Cannot convert $path($v) from $from to $to';
	}

	static var ENUM_CLASSES = new Map();
	static function getEnumClass( name : String ) : Dynamic {
		var cl = ENUM_CLASSES.get(name);
		if( cl != null ) return cl;
		var path = name.split(".").join("_");
		path = path.charAt(0).toUpperCase() + path.substr(1);
		cl = Type.resolveClass("hxbit.enumSer." + path);
		if( cl != null ) ENUM_CLASSES.set(name,cl);
		return cl;
	}

	function readValue(t:Schema.FieldType) : Dynamic {
		var v : Dynamic = readValueImpl(t);
		#if hl
		if( hl.Type.getDynamic(v).kind == HVirtual && !t.match(PSerInterface(_)) ) {
			var real : Dynamic = hl.Api.getVirtualValue(v);
			if( real != null ) v = real;
		}
		#end
		return v;
	}

	function readValueImpl( t : Schema.FieldType ) : Dynamic {
		return switch( t ) {
		case PInt64: getInt64();
		case PInt: getInt();
		case PFloat: getFloat();
		case PAlias(t), PAliasCDB(t): readValue(t);
		case PBool: getBool();
		case PString: getString();
		case PArray(t): getArray(function() return readValue(t));
		case PVector(t): getVector(function() return readValue(t));
		case PBytes: getBytes();
		case PEnum(name):
			var ser : Dynamic = getEnumClass(name);
			if( ser == null ) {
				var e = Type.resolveEnum(name);
				// an old enum can be tagged with @skipSerialize in order to allow loading old content.
				// but this will only work if the enum does not have any constructor parameters !
				if( e != null && Reflect.hasField(haxe.rtti.Meta.getType(e), "skipSerialize") ) {
					getByte();
					return null;
				}
				throw "No enum unserializer found for " + name;
			}
			return ser.doUnserialize(this);
		case PSerializable(name):
			var cl = cast Type.resolveClass(name);
			if( cl == null )
				getRef(null,0); // fallback for hxbit64
			else
				getKnownRef(cl);
		case PSerInterface(_): getAnyRef();
		case PNull(t): getByte() == 0 ? null : readValue(t);
		case PObj(fields):
			var bits = getInt();
			if( bits == 0 )
				return null;
			var o = {};
			bits--;
			var bit = 0;
			for( f in fields ) {
				if( isNullable(f.type) ) {
					var flag = 1 << bit;
					bit++;
					if( bits & flag == 0 ) continue;
				}
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
		case PCustom:
			getCustom();
		case PStruct(_, fields):
			var bits = getInt();
			if( bits == 0 )
				return null;
			var o = {};
			bits--;
			var bit = 0;
			for( f in fields ) {
				if( isNullable(f.type) ) {
					var flag = 1 << bit;
					bit++;
					if( bits & flag != 0 ) continue;
				}
				Reflect.setField(o, f.name, readValue(f.type));
			}
			return o;
		case PNoSave(t):
			if( forSave ) return null;
			return readValueImpl(t);
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
		case PAlias(t), PAliasCDB(t):
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
			var ser : Dynamic = getEnumClass(name);
			if( ser == null ) throw "No enum unserializer found for " + name;
			ser.doSerialize(this,v);
		case PSerializable(_):
			addKnownRef(v);
		case PSerInterface(_):
			addAnyRef(v);
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
				var bit = 0;
				for( f in fields )
					if( isNullable(f.type) ) {
						if( Reflect.field(v, f.name) != null )
							fbits |= 1 << bit;
						bit++;
					}
				addInt(fbits + 1);
				for( f in fields ) {
					var v : Dynamic = Reflect.field(v, f.name);
					if( v == null && isNullable(f.type) ) continue;
					writeValue(v, f.type);
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
			case PEnum(_) if( Std.isOfType(v,haxe.ds.EnumValueMap) ):
				var v : haxe.ds.EnumValueMap<Dynamic,Dynamic> = v;
				if( v == null ) {
					addByte(0);
					return;
				}
				var keys = [for (k in v.keys()) k];
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
		case PCustom:
			addCustom(v);
		case PStruct(_, fields):
			if( v == null )
				addByte(0);
			else {
				var fbits = 0;
				var bit = 0;
				for( f in fields )
					if( isNullable(f.type) ) {
						if( Reflect.field(v, f.name) == null )
							fbits |= 1 << bit;
						bit++;
					}
				addInt(fbits + 1);
				for( f in fields ) {
					var v : Dynamic = Reflect.field(v, f.name);
					if( v == null && isNullable(f.type) ) continue;
					writeValue(v, f.type);
				}
			}
		case PNoSave(t):
			if( !forSave ) writeValue(v, t);
		case PUnknown:
			throw "assert";
		}
	}

	public static function save( value : Serializable ) {
		var s = new Serializer();
		s.beginSave();
		s.addKnownRef(value);
		return s.endSave();
	}

	static function sortByUID(o1:Serializable, o2:Serializable) : Int {
		#if hxbit64
		if( o1.__uid == o2.__uid )
			return 0;
		return o1.__uid > o2.__uid ? 1 : -1;
		#else
		return o1.__uid - o2.__uid;
		#end
	}

	static function sortByUIDDesc(o1:Serializable, o2:Serializable) : Int {
		#if hxbit64
		if( o1.__uid == o2.__uid )
			return 0;
		return o1.__uid > o2.__uid ? -1 : 1;
		#else
		return o2.__uid - o1.__uid;
		#end
	}

	public static function load<T:Serializable>( bytes : haxe.io.Bytes, cl : Class<T>, ?iterObjects : Serializable -> Void, ?remapIds : Bool ) : T {
		var s = new Serializer();
		s.remapIds = remapIds;
		s.beginLoad(bytes);
		var value = s.getKnownRef(cl);
		s.endLoad();
		if( iterObjects != null ) {
			var objects = [for( o in s.refs ) o];
			objects.sort(sortByUID);
			for( o in objects )
				iterObjects(o);
		}
		return value;
	}


	#if (hxbit_visibility || hxbit_mark)
	static function markReferencesDyn( value : Dynamic, mark : hxbit.Serializable.MarkInfo, from : NetworkSerializable ) {
		if( value == null ) return;
		switch( Type.typeof(value) ) {
		case TObject:
			for( f in Reflect.fields(value) ) {
				markReferencesDyn(Reflect.field(value,f), mark, from);
			}
		case TClass(c):
			switch( c ) {
			case Array:
				var a : Array<Dynamic> = value;
				for( v in a )
					markReferencesDyn(v, mark, from);
			case haxe.ds.StringMap, haxe.ds.ObjectMap, haxe.ds.EnumValueMap, haxe.ds.IntMap:
				throw "TODO";
			default:
				var s = Std.downcast(value, hxbit.Serializable.AnySerializable);
				if( s != null )
					s.markReferences(mark, from);
			}
		case TEnum(_):
			for( v in Type.enumParameters(value) )
				markReferencesDyn(value, mark, from);
		default:
		}
	}
	#end

	#if hxbit_clear
	static function clearReferencesDyn( value : Dynamic, mark : hxbit.Serializable.MarkInfo ) : Dynamic {
		if( value == null )
			return null;
		switch( Type.typeof(value) ) {
		case TObject:
			for( f in Reflect.fields(value) ) {
				clearReferencesDyn(Reflect.field(value,f), mark);
			}
		case TClass(c):
			switch( c ) {
			case Array:
				var a : Array<Dynamic> = value;
				for( i => v in a )
					a[i] = clearReferencesDyn(v, mark);
			case haxe.ds.StringMap, haxe.ds.ObjectMap, haxe.ds.EnumValueMap, haxe.ds.IntMap:
				throw "TODO";
			default:
				var s = Std.downcast(value, hxbit.Serializable.AnySerializable);
				if( s != null )
					s.clearReferences(mark);
			}
		case TEnum(e):
			var vl = Type.enumParameters(value);
			var changed = false;
			for( i => v in vl ) {
				var v2 = clearReferencesDyn(value, mark);
				if( v != v2 ) {
					vl[i] = v2;
					changed = true;
				}
			}
			if( changed )
				return Type.createEnumIndex(e, Type.enumIndex(value), vl);
		default:
		}
		return value;
	}
	#end

}

#end
