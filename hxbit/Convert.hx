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

class ConvertField {
	public var index : Int;
	public var same : Bool;
	public var defaultValue : Dynamic;
	public var from : Null<Schema.FieldType>;
	public var to : Null<Schema.FieldType>;
	public function new(from, to) {
		this.from = from;
		this.to = to;
	}
}

class Convert {

	public var read : Array<ConvertField>;
	public var write : Array<ConvertField>;

	public function new( ourSchema : Schema, schema : Schema ) {
		var ourMap = new Map();
		for( i in 0...ourSchema.fieldsNames.length )
			ourMap.set(ourSchema.fieldsNames[i], ourSchema.fieldsTypes[i]);
		read = [];

		if( ourSchema.isFinal != schema.isFinal )
			throw "TODO : handle final flag change";

		var map = new Map();
		for( i in 0...schema.fieldsNames.length ) {
			var oldT = schema.fieldsTypes[i];
			var newT = ourMap.get(schema.fieldsNames[i]);
			var c = new ConvertField(oldT, newT);
			if( newT != null ) {
				if( sameType(oldT, newT) )
					c.same = true;
				else
					c.defaultValue = getDefault(newT);
			}
			c.index = read.length;
			read.push(c);
			map.set(schema.fieldsNames[i], c);
		}

		write = [];
		for( i in 0...ourSchema.fieldsNames.length ) {
			var newT = ourSchema.fieldsTypes[i];
			var c = map.get(ourSchema.fieldsNames[i]);
			if( c == null ) {
				c = new ConvertField(null, newT);
				// resolve default value using a specific method ?
				c.defaultValue = getDefault(newT);
			}
			write.push(c);
		}
	}

	function toString() {
		return [for( i in 0...write.length ) {
			var w = write[i];
			if( w.from == null ) "insert:"+w.defaultValue else
			if( w.same ) i == w.index ? "s" : "@" + w.index else
			"@" + w.index + ":" + w.to;
		}].toString();
	}

	public static function sameType( a : Schema.FieldType, b : Schema.FieldType ) {
		switch( [a, b] ) {
		case [PMap(ak, av), PMap(bk, bv)]:
			return sameType(ak, bk) && sameType(av, bv);
		case [PArray(a), PArray(b)],[PVector(a),PVector(b)],[PNull(a),PNull(b)]:
			return sameType(a, b);
		case [PObj(fa), PObj(fb)]:
			if( fa.length != fb.length ) return false;
			for( i in 0...fa.length ) {
				var a = fa[i];
				var b = fb[i];
				if( a.name != b.name || a.opt != b.opt || !sameType(a.type, b.type) )
					return false;
			}
			return true;
		case [PAlias(a), PAlias(b)]:
			return sameType(a, b);
		case [PAlias(a), _]:
			return sameType(a, b);
		case [_, PAlias(b)]:
			return sameType(a, b);
		case [PInt, PFlags(_)]:
			return true;
		case [PFlags(_), PInt]:
			return true;
		default:
			return Type.enumEq(a, b);
		}
	}

	public static function getDefault(t:Schema.FieldType) : Dynamic {
		return switch( t ) {
		case PInt64: haxe.Int64.make(0, 0);
		case PInt, PFlags(_): 0;
		case PFloat: 0.;
		case PArray(_): [];
		case PMap(k, _):
			switch( k ) {
			case PInt: new Map<Int,Dynamic>();
			case PString: new Map<String,Dynamic>();
			default: new Map<{},Dynamic>();
			}
		case PVector(_): new haxe.ds.Vector<Dynamic>(0);
		case PBool: false;
		case PAlias(t): getDefault(t);
		case PEnum(_), PNull(_), PObj(_), PSerializable(_), PString, PUnknown, PBytes, PDynamic, PStruct: null;
		};
	}

}
