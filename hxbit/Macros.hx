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

import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.Context;
using haxe.macro.TypeTools;
using haxe.macro.ComplexTypeTools;

enum RpcMode {
	/*
		When called on the client: will forward the call on the server (if networkAllows(RPC) allows it), but not execute locally.
		When called on the server: will forward the call to the clients (and force its execution), then execute.
		This is the default behavior.
	*/
	All;
	/*
		When called on the server: will forward the call to the clients, but not execute locally.
		When called on the client: will execute locally.
	*/
	Clients;
	/*
		When called on the client: will forward the call the server (if networkAllow(RPCServer) allows it), but not execute locally.
		When called on the server: will execute locally.
	*/
	Server;
	/*
		When called on the client: will forward the call to the server (if networkAllow(RPC) allows it), but not execute locally.
		When called on the server: will forward the call to the owners as defined by networkAllow(Ownership).
	*/
	Owner;
	/*
		When called on the client: will forward the call to the server and other clients (if networkAllows(RPC) allows it) and execute locally immediately.
		When called on the server: will forward the call to the clients (and force its execution), then execute.
	*/
	Immediate;
}

enum PropTypeDesc<PropType> {
	PInt;
	PFloat;
	PBool;
	PString;
	PBytes;
	PSerializable( name : String );
	PEnum( name : String );
	PMap( k : PropType, v : PropType );
	PArray( k : PropType );
	PObj( fields : Array<{ name : String, type : PropType, opt : Bool }> );
	PAlias( k : PropType );
	PVector( k : PropType );
	PNull( t : PropType );
	PUnknown;
	PDynamic;
	PInt64;
	PFlags( t : PropType );
	PStruct;
	PSerInterface( name : String );
}

typedef PropType = {
	var d : PropTypeDesc<PropType>;
	var t : ComplexType;
	@:optional var isProxy : Bool;
	@:optional var increment : Float;
	@:optional var condSend : Expr;
	@:optional var notMutable : Bool;
	@:optional var visibility : Int;
}

class Macros {

	static var IN_ENUM_SER = false;
	static var PREFIX_VARS : Map<String,Bool> = null;
	public static var IGNORED_META : Map<String,Bool> = new Map();
	public static var VISIBILITY_VALUES = [];
	@:persistent static var NW_BUILD_STACK : Array<String> = [];

	#if macro
	public static function markAsSerializable( className : String ) {
		NW_BUILD_STACK.push(className);
	}
	#end

	public static function makeEnumPath( name : String ) {
		name = name.split(".").join("_");
		name = name.charAt(0).toUpperCase() + name.substr(1);
		return "hxbit.enumSer." + name;
	}

	public static macro function serializeValue( ctx : Expr, v : Expr ) : Expr {
		var t = Context.typeof(v);
		var pt = getPropType(t, false);
		if( pt == null ) {
			Context.error("Unsupported serializable type " + t.toString(), v.pos);
			return macro { };
		}
		IN_ENUM_SER = StringTools.startsWith(Context.getLocalClass().toString(), "hxbit.enumSer.");
		return withPos(serializeExpr(ctx, v, pt),v.pos);
	}

	public static macro function unserializeValue( ctx : Expr, v : Expr, depth : Int = 0 ) : Expr {
		var t = Context.typeof(v);
		var pt = getPropType(t, false);
		if( pt == null ) {
			Context.error("Unsupported serializable type " + t.toString(), v.pos);
			return macro { };
		}
		var cl = Context.getLocalClass();
		IN_ENUM_SER = StringTools.startsWith(cl.toString(), "hxbit.enumSer.");
		PREFIX_VARS = null;
		for( v in cl.get().meta.extract(":prefixVar") ) {
			if( v.params == null ) continue;
			for( p in v.params ) {
				switch( p.expr ) {
				case EConst(CIdent(i)):
					if( PREFIX_VARS == null ) PREFIX_VARS = new Map();
					PREFIX_VARS.set(i, true);
				default:
				}
			}
		}
		return withPos(unserializeExpr(ctx, v, pt, depth),v.pos);
	}

	public static macro function getFieldType( v : Expr ) {
		var t = Context.typeof(v);
		var pt = getPropType(t, false);
		if( pt == null )
			return macro null;
		var v = toFieldType(pt);
		return macro $v{v};
	}

	public static function iterType<T>( t : PropTypeDesc<T>, f : T -> Void ) {
		switch( t ) {
		case PMap(k, v):
			f(k);
			f(v);
		case PArray(t):
			f(t);
		case PObj(fields):
			for( tf in fields )
				f(tf.type);
		case PAlias(t):
			f(t);
		case PVector(t):
			f(t);
		case PNull(t):
			f(t);
		default:
		}
	}

	#if macro

	static function toFieldType( t : PropType ) : Schema.FieldType {
		return switch( t.d ) {
		case PInt64: PInt64;
		case PInt: PInt;
		case PFloat: PFloat;
		case PBool: PBool;
		case PString: PString;
		case PBytes: PBytes;
		case PSerializable(name): PSerializable(name);
		case PEnum(name): PEnum(name);
		case PMap(k, v): PMap(toFieldType(k), toFieldType(v));
		case PArray(v): PArray(toFieldType(v));
		case PObj(fields): PObj([for( f in fields ) { name : f.name, type : toFieldType(f.type), opt : f.opt }]);
		case PAlias(t): return toFieldType(t);
		case PVector(k): PVector(toFieldType(k));
		case PNull(t): PNull(toFieldType(t));
		case PFlags(t): PFlags(toFieldType(t));
		case PStruct: PStruct;
		case PUnknown: PUnknown;
		case PDynamic: PDynamic;
		case PSerInterface(name): PSerInterface(name);
		};
	}

	static function lookupInterface( c : Ref<ClassType>, name : String ) {
		while( true ) {
			var cg = c.get();
			for( i in cg.interfaces ) {
				if( i.t.toString() == name )
					return true;
				if( lookupInterface(i.t, name) )
					return true;
			}
			var sup = cg.superClass;
			if( sup == null )
				break;
			c = sup.t;
		}
		return false;
	}

	static function isSerializable( c : Ref<ClassType> ) {
		return NW_BUILD_STACK.indexOf(c.toString()) >= 0 || c.get().meta.has(":isSerializable") || lookupInterface(c, "hxbit.Serializable");
	}

	static function isStructSerializable( c : Ref<ClassType> ) {
		return lookupInterface(c, "hxbit.StructSerializable");
	}

	static function getVisibility( m : MetadataEntry ) : Null<Int> {
		#if !hxbit_visibility
		Context.error("Visibility needs -D hxbit-visibility", m.pos);
		return null;
		#end
		switch( m.params[0].expr ) {
		case EConst(CIdent(s)):
			var idx = VISIBILITY_VALUES.indexOf(s);
			if( idx < 0 ) {
				if( VISIBILITY_VALUES.length == 0 )
					Context.error("hxbit.Macros.VISIBILITY_VALUES has not been initialized", m.pos);
				else
					Context.error(s+" is not a valid visibility", m.params[0].pos);
			} else
				return idx;
		default:
		}
		return null;
	}

	static function getPropField( ft : Type, meta : Metadata, partial : Bool ) {
		var t = getPropType(ft, partial);
		if( t == null )
			return null;
		for( m in meta) {
			switch( m.name ) {
			case ":s", ":optional", ":serializePriority":
				//
			case ":increment":
				var inc : Null<Float> = null;
				if( m.params.length == 1 )
					switch( m.params[0].expr ) {
					case EConst(CInt(i)): inc = Std.parseInt(i);
					case EConst(CFloat(f)): inc = Std.parseFloat(f);
					default:
					}
				if( inc == null )
					Context.error("Increment requires value parameter", m.pos);
				switch( t.d ) {
				case PFloat, PNull({ d : PFloat }):
					t.increment = inc;
				default:
					Context.error("Increment not allowed on " + t.t.toString(), m.pos);
				}
			case ":condSend" if( m.params.length == 1 ):
				t.condSend = m.params[0];
				switch( t.condSend.expr ) {
				case EConst(CIdent("false")):
					t.notMutable = true;
				default:
				}
			case ":notMutable":
				t.notMutable = true;
			case ":visible" if( m.params.length == 1 ):
				t.visibility = getVisibility(m);
			default:
				if( m.name.charAt(0) == ":" && !IGNORED_META.exists(m.name.substr(1)) )
					Context.error("Unsupported network metadata", m.pos);
			}
		}
		return t;
	}

	static function getNativePath( e : BaseType ) {
		var name = e.pack.length == 0 ? e.name : e.pack.join(".") + "." + e.name;
		// handle @:native on enum
		for( m in e.meta.get() )
			if( m.name == ":native" && m.params.length == 1 )
				switch( m.params[0].expr ) {
				case EConst(CString(s)): name = s;
				default:
				}
		return name;
	}

	static function getPropType( t : haxe.macro.Type, partial : Bool ) : PropType {
		var isProxy = false;
		var isMutable = true;
		var desc = switch( t ) {
		case TAbstract(a, pl):
			switch( a.toString() ) {
			case "haxe.Int64":
				PInt64;
			case "Float":
				PFloat;
			case "Int","UInt":
				PInt;
			case "Bool":
				PBool;
			case "Map", "haxe.ds.Map":
				var tk = getPropType(pl[0],partial);
				var tv = getPropType(pl[1],partial);
				if( tk == null || tv == null )
					return null;
				PMap(tk, tv);
			case "haxe.ds.Vector":
				var tk = getPropType(pl[0],partial);
				if( tk == null )
					return null;
				PVector(tk);
			case "hxbit.VectorProxy":
				var t = getPropType(pl[0],partial);
				if( t == null )
					return null;
				isProxy = true;
				PVector(t);
			case "hxbit.ArrayProxy", "hxbit.ArrayProxy2":
				var t = getPropType(pl[0],partial);
				if( t == null )
					return null;
				isProxy = true;
				PArray(t);
			case "hxbit.MapProxy", "hxbit.MapProxy2":
				var k = getPropType(pl[0],partial);
				var v = getPropType(pl[1],partial);
				if( k == null || v == null ) return null;
				isProxy = true;
				PMap(k, v);
			case "hxbit.EnumFlagsProxy":
				var e = getPropType(pl[0],partial);
				if( e == null ) return null;
				isProxy = true;
				PFlags(e);
			case "haxe.EnumFlags":
				var e = getPropType(pl[0],partial);
				if( e == null ) return null;
				PFlags(e);
			case "Null":
				var p = getPropType(pl[0],partial);
				if( p != null && !isNullable(p) )
					p = { d : PNull(p), t : TPath( { pack : [], name : "Null", params : [TPType(p.t)] } ) };
				return p;
			case name:
				var t2 = Context.followWithAbstracts(t, true);
				switch( t2 ) {
				case TAbstract(a2, _) if( a2.toString() == name ):
					return null;
				default:
				}
				var pt = getPropType(t2,partial);
				if( pt == null ) return null;
				PAlias(pt);
			}
		case TEnum(e,_):
			PEnum(getNativePath(e.get()));
		case TDynamic(_):
			PDynamic;
		case TAnonymous(a):
			var a = a.get();
			var fields = [];
			isMutable = false;
			for( f in a.fields ) {
				if( f.meta.has(":noSerialize") )
					continue;
				var ft = getPropField(f.type, f.meta.get(), partial);
				if( ft == null ) return null;
				fields.push( { name : f.name, type : ft, opt : f.meta.has(":optional") } );
				#if (haxe_ver >= 4)
				if( !f.isFinal ) isMutable = true;
				#end
			}
			a.fields.length == 0 ? PDynamic : PObj(fields);
		case TInst(c, pl):
			switch( c.toString() ) {
			case "String":
				PString;
			case "Array":
				var at = getPropType(pl[0],partial);
				if( at == null ) return null;
				PArray(at);
			case "haxe.ds.IntMap":
				var vt = getPropType(pl[0],partial);
				if( vt == null ) return null;
				PMap({ t : macro : Int, d : PInt }, vt);
			case "haxe.ds.StringMap":
				var vt = getPropType(pl[0],partial);
				if( vt == null ) return null;
				PMap({ t : macro : String, d : PString }, vt);
			case "haxe.io.Bytes":
				PBytes;
			case name if( StringTools.startsWith(name, "hxbit.ObjProxy_") ):
				var fields = c.get().fields.get();
				for( f in fields )
					if( f.name == "__value" ) {
						var t = getPropType(f.type,partial);
						if( t == null ) return t;
						t.isProxy = true;
						return t;
					}
				throw "assert";
			default:
				if( isSerializable(c) ) {
					var c = c.get();
					var path = getNativePath(c);
					c.isInterface ? PSerInterface(path) : PSerializable(path);
				} else if( isStructSerializable(c) )
					PStruct;
				else
					return null;
			}
		case TType(td, pl):
			switch( td.toString() ) {
			case "Null":
				var p = getPropType(pl[0],partial);
				if( p != null && !isNullable(p) )
					p = { d : PNull(p), t : TPath( { pack : [], name : "Null", params : [TPType(p.t)] } ) };
				return p;
			default:
				var p = getPropType(Context.follow(t, true),partial);
				if( p != null )
					p.t = t.toComplexType(); // more general, still identical
				return p;
			}
		case TLazy(f):
			// browsing TLazy would flush the context leading to more recursions,
			// since we are in our build phase, let's instead return Unknown
			if( partial )
				return { d : PUnknown, t : null };
			return getPropType(f(), partial);
		default:
			return null;
		}
		var p : PropType = {
			d : desc,
			t : t.toComplexType(),
		};
		if( isProxy ) p.isProxy = isProxy;
		if( !isMutable ) p.notMutable = true;
		return p;
	}

	static function isNullable( t : PropType ) {
		switch( t.d ) {
		case PInt, PFloat, PBool, PFlags(_), PInt64:
			return false;
		case PAlias(t):
			return isNullable(t);
		default:
			return true;
		}
	}

	static function toType( t : ComplexType ) : Type {
		return Context.typeof(macro (null:$t));
	}

	static function serializeExpr( ctx : Expr, v : Expr, t : PropType, skipCheck = false ) {

		if( t.isProxy && !skipCheck )
			return serializeExpr(ctx, { expr : EField(v, "__value"), pos : v.pos }, t, true);

		switch( t.d ) {
		case PInt64:
			return macro $ctx.addInt64($v);
		case PFloat:
			return macro $ctx.addFloat($v);
		case PInt:
			return macro $ctx.addInt($v);
		case PBool:
			return macro $ctx.addBool($v);
		case PBytes:
			return macro $ctx.addBytes($v);
		case PMap(kt, vt):
			var kt = kt.t;
			var vt = toProxy(vt);
			var vk = { expr : EConst(CIdent("k")), pos : v.pos };
			var vv = { expr : EConst(CIdent("v")), pos : v.pos };
			return macro $ctx.addMap($v, function(k:$kt) return hxbit.Macros.serializeValue($ctx, $vk), function(v:$vt) return hxbit.Macros.serializeValue($ctx, $vv));
		case PEnum(_):
			var et = t.t;
			var ser = "serialize";
			if( IN_ENUM_SER )
				ser += "2";
			return macro (null : hxbit.Serializable.SerializableEnum<$et>).$ser($ctx,$v);
		case PObj(fields):
			var nullables = [for( f in fields ) if( isNullable(f.type) ) f];
			var ct = t.t;
			if( nullables.length >= 32 )
				Context.error("Too many nullable fields", v.pos);
			return macro {
				var v : $ct = $v;
				if( v == null )
					$ctx.addByte(0);
				else {
					var fbits = 0;
					$b{[
						for( i in 0...nullables.length ) {
							var name = nullables[i].name;
							macro if( v.$name != null ) fbits |= $v{ 1 << i };
						}
					]};
					$ctx.addInt(fbits + 1);
					$b{[
						for( f in fields ) {
							var nidx = nullables.indexOf(f);
							var name = f.name;
							if( nidx < 0 )
								macro hxbit.Macros.serializeValue($ctx, v.$name);
							else
								macro if( fbits & $v{1<<nidx} != 0 ) hxbit.Macros.serializeValue($ctx, v.$name);
						}
					]};
				}
			};
		case PString:
			return macro $ctx.addString($v);
		case PArray(t):
			var at = toProxy(t);
			var ve = { expr : EConst(CIdent("e")), pos : v.pos };
			return macro $ctx.addArray($v, function(e:$at) return hxbit.Macros.serializeValue($ctx, $ve));
		case PVector(t):
			var at = toProxy(t);
			var ve = { expr : EConst(CIdent("e")), pos : v.pos };
			return macro $ctx.addVector($v, function(e:$at) return hxbit.Macros.serializeValue($ctx, $ve));
		case PSerializable(_):
			return macro $ctx.addKnownRef($v);
		case PSerInterface(_):
			return macro $ctx.addAnyRef($v);
		case PAlias(t):
			return serializeExpr(ctx, { expr : ECast(v, null), pos : v.pos }, t);
		case PNull(t):
			var e = serializeExpr(ctx, v, t);
			return macro if( $v == null ) $ctx.addByte(0) else { $ctx.addByte(1); $e; };
		case PDynamic:
			return macro $ctx.addDynamic($v);
		case PFlags(t):
			return serializeExpr(ctx, { expr : ECast(v, null), pos : v.pos }, { t : macro : Int, d : PInt });
		case PStruct:
			return macro $ctx.addStruct($v);
		case PUnknown:
			throw "assert";
		}
	}

	dynamic static function unserializeExpr( ctx : Expr, v : Expr, t : PropType, depth : Int ) {
		switch( t.d ) {
		case PInt64:
			return macro $v = $ctx.getInt64();
		case PFloat:
			return macro $v = $ctx.getFloat();
		case PInt:
			return macro $v = $ctx.getInt();
		case PBool:
			return macro $v = $ctx.getBool();
		case PBytes:
			return macro $v = $ctx.getBytes();
		case PMap(k,t):
			var kt = k.t;
			var vt = toProxy(t);
			var kname = "k" + depth;
			var vname = "v" + depth;
			var vk = { expr : EConst(CIdent(kname)), pos : v.pos };
			var vv = { expr : EConst(CIdent(vname)), pos : v.pos };
			return macro {
				var $kname : $kt;
				var $vname : $vt;
				$v = $ctx.getMap(function() { hxbit.Macros.unserializeValue($ctx, $vk, $v{depth + 1}); return $vk; }, function() { hxbit.Macros.unserializeValue($ctx, $vv, $v{depth+1}); return $vv; });
			};
		case PEnum(_):
			var et = t.t;
			var unser = "unserialize";
			if( IN_ENUM_SER )
				unser += "2";
			return macro { var __e : $et; __e = (null : hxbit.Serializable.SerializableEnum<$et>).$unser($ctx); $v = __e; }
		case PObj(fields):
			var nullables = [for( f in fields ) if( isNullable(f.type) ) f];
			if( nullables.length >= 32 )
				Context.error("Too many nullable fields", v.pos);
			var ct = t.t;
			return macro {
				var fbits = $ctx.getInt();
				if( fbits == 0 )
					$v = null;
				else {
					fbits--;
					$b{{
						var exprs = [];
						var vars = [];
						for( f in fields ) {
							var nidx = nullables.indexOf(f);
							var name = f.name;
							var ct = f.type.t;
							vars.push( { field : name, expr : { expr : EConst(CIdent(name)), pos:v.pos } } );
							if( nidx < 0 ) {
								exprs.unshift(macro var $name : $ct);
								exprs.push(macro hxbit.Macros.unserializeValue($ctx, $i{name}, $v{depth+1}));
							} else {
								exprs.unshift(macro var $name : $ct = null);
								exprs.push(macro if( fbits & $v { 1 << nidx } != 0 ) hxbit.Macros.unserializeValue($ctx, $i{name}, $v{depth+1}));
							}
						}
						exprs.push( { expr : EBinop(OpAssign,v, { expr : EObjectDecl(vars), pos:v.pos } ), pos:v.pos } );
						exprs;
					}};
				}
			};
		case PString:
			return macro $v = $ctx.getString();
		case PArray(at):
			var at = toProxy(at);
			var ve = { expr : EConst(CIdent("e")), pos : v.pos };
			var ename = "e" + depth;
			return macro {
				var $ename : $at;
				$v = $ctx.getArray(function() { hxbit.Macros.unserializeValue($ctx, $i{ename}, $v{depth+1}); return $i{ename}; });
			};
		case PVector(at):
			var at = toProxy(at);
			var ve = { expr : EConst(CIdent("e")), pos : v.pos };
			var ename = "e" + depth;
			return macro {
				var $ename : $at;
				$v = $ctx.getVector(function() { hxbit.Macros.unserializeValue($ctx, $i{ename}, $v{depth+1}); return $i{ename}; });
			};
		case PSerializable(_):
			function loop(t:ComplexType) {
				switch( t ) {
				case TPath( { name : "Null", params:[TPType(t)] } ):
					return loop(t);
				case TPath( p = { params:a } ) if( a.length > 0 ):
					return TPath( { pack : p.pack, name:p.name, sub:p.sub } );
				default:
					return t;
				}
			}
			var ct = loop(t.t);
			if( PREFIX_VARS != null ) {
				switch( ct ) {
				case TPath(inf = { pack : pk }) if( pk.length > 0 && PREFIX_VARS.exists(pk[0]) ):
					ct = TPath({ pack : ["std"].concat(pk), name : inf.name, params : inf.params, sub : inf.sub });
				default:
				}
			}
			var cexpr = Context.parse(ct.toString(), v.pos);
			return macro $v = $ctx.getRef($cexpr,@:privateAccess $cexpr.__clid);
		case PSerInterface(name):
			return macro $v = cast $ctx.getAnyRef();
		case PAlias(at):
			var cvt = at.t;
			var vname = "v" + depth;
			return macro {
				var $vname : $cvt;
				${unserializeExpr(ctx,macro $i{vname},at,depth+1)};
				$v = cast $i{vname};
			};
		case PNull(t):
			var e = unserializeExpr(ctx, v, t, depth);
			return macro if( $ctx.getByte() == 0 ) $v = null else $e;
		case PDynamic:
			return macro $v = $ctx.getDynamic();
		case PFlags(_):
			return macro {
				var v : Int;
				${unserializeExpr(ctx,macro v,{ t : macro : Int, d : PInt },depth + 1)};
				$v = ${t.isProxy ? macro new hxbit.EnumFlagsProxy(v) : macro new haxe.EnumFlags(v)};
			};
		case PStruct:
			return macro $v = $ctx.getStruct();
		case PUnknown:
			throw "assert";
		}
	}

	static function withPos( e : Expr, p : Position ) {
		e.pos = p;
		haxe.macro.ExprTools.iter(e, function(e) withPos(e, p));
		return e;
	}

	public static function buildSerializable() {
		var cl = Context.getLocalClass().get();
		if( cl.isInterface || Context.defined("display") || cl.meta.has(":skipSerialize") )
			return null;
		var fields = Context.getBuildFields();
		var toSerialize = [];
		var addCustomSerializable = false;
		var addCustomUnserializable = false;

		var sup = cl.superClass;
		var isSubSer = sup != null && isSerializable(sup.t);
		var hasNonSerializableParent = sup != null && !isSerializable(sup.t);
		var serializePriority = null;

		for( f in fields ) {
			// has already been processed
			if( f.name == "__clid" )
				return null;
			if( f.name == "customSerialize" && ( f.access.indexOf(AOverride) < 0 || hasNonSerializableParent ) ) {
				addCustomSerializable = true;
			}
			if( f.name == "customUnserialize" && ( f.access.indexOf(AOverride) < 0 || hasNonSerializableParent ) ) {
				addCustomUnserializable = true;
			}
			if( f.meta == null ) continue;

			var isPrio = false, isSer = null, vis = null;
			for( meta in f.meta ) {
				switch( meta.name ) {
				case ":s": isSer = meta;
				case ":serializePriority": isPrio = true;
				case ":visible": vis = getVisibility(meta);
				}
			}
			if( isSer != null ) {
				if( isPrio ) serializePriority = f;
				toSerialize.push({ f : f, m : isSer, vis : vis });
			}
		}

		if( cl.meta.has(":serializeSuperClass") ) {
			if( toSerialize.length != 0 || !isSubSer )
				Context.error("Cannot use serializeSuperClass on this class", cl.pos);
			return null;
		}

		var supClass = sup == null ? null : sup.t.get();
		if( supClass != null && supClass.meta.has(":prefixVar") && !cl.meta.has(":prefixVar") ) {
			for( v in supClass.meta.extract(":prefixVar") )
				cl.meta.add(v.name, v.params, v.pos);
		}

		if( addCustomSerializable != addCustomUnserializable ) {
			Context.error("customSerialize and customUnserialize must both exist or both be removed!",cl.pos);
		}

		var fieldsInits = [];
		for( f in fields ) {
			if( f.access.indexOf(AStatic) >= 0 ) continue;
			switch( f.kind ) {
			case FVar(_, e), FProp(_, _, _, e) if( e != null ):
				// before unserializing
				fieldsInits.push({ expr : EBinop(OpAssign,{ expr : EConst(CIdent(f.name)), pos : e.pos },e), pos : e.pos });
			default:
			}
		}

		var pos = Context.currentPos();
		// todo : generate proper generic static var ?
		// this is required for fixing conflicting member var / package name
		var useStaticSer = cl.params.length == 0;
		var el = [], ul = [], serializePriorityFuns = null;
		for( f in toSerialize ) {
			var fname = f.f.name;
			var ef = useStaticSer && f.f != serializePriority ? macro __this.$fname : macro this.$fname;
			el.push(withPos(macro hxbit.Macros.serializeValue(__ctx,$ef),f.f.pos));
			ul.push(withPos(macro hxbit.Macros.unserializeValue(__ctx, $ef),f.f.pos));
			if( f.vis != null ) {
				el.push(macro if( @:privateAccess __ctx.visibilityGroups & (1<<$v{f.vis}) != 0 ) ${el.pop()});
				ul.push(macro if( @:privateAccess __ctx.visibilityGroups & (1<<$v{f.vis}) != 0 ) ${ul.pop()} else $ef = cast null);
			}
			if( f.f == serializePriority ) {
				if( serializePriorityFuns != null ) throw "assert";
				serializePriorityFuns = { ser : el.pop(), unser : ul.pop() };
			}
		}

		var noCompletion = [{ name : ":noCompletion", pos : pos }];
		var access = [APublic];
		if( isSubSer )
			access.push(AOverride);
		else
			fields.push({
				name : "__uid",
				pos : pos,
				access : [APublic],
				meta : noCompletion,
				kind : FVar(macro : hxbit.UID, macro @:privateAccess hxbit.Serializer.allocUID()),
			});

		var clName = StringTools.endsWith(cl.module,"."+cl.name) ? cl.module.split(".") : [cl.name];
		fields.push({
			name : "__clid",
			pos : pos,
			access : [AStatic],
			meta : noCompletion,
			kind : FVar(macro : Int, macro @:privateAccess hxbit.Serializer.registerClass($p{clName})),
		});
		fields.push({
			name : "getCLID",
			pos : pos,
			access : access,
			meta : noCompletion,
			kind : FFun({ args : [], ret : macro : Int, expr : macro return __clid }),
		});

		var needSerialize = toSerialize.length != 0 || !isSubSer || addCustomSerializable;
		var needUnserialize = needSerialize || fieldsInits.length != 0 || addCustomUnserializable;

		if( needSerialize ) {
			if( useStaticSer ) fields.push({
				name : "doSerialize",
				pos : pos,
				access : [AStatic],
				meta : noCompletion,
				kind : FFun({
					args : [ { name : "__ctx", type : macro : hxbit.Serializer }, { name : "__this", type : TPath({ pack : [], name : cl.name }) } ],
					ret : null,
					expr : macro $b{el},
				}),
			});
			fields.push({
				name : "serialize",
				pos : pos,
				access : access,
				kind : FFun({
					args : [ { name : "__ctx", type : macro : hxbit.Serializer } ],
					ret : null,
					expr : macro @:privateAccess {
						${ if( serializePriorityFuns != null ) serializePriorityFuns.ser else macro { } };
						${ if( isSubSer ) macro super.serialize(__ctx) else macro { } };
						${ if( useStaticSer ) macro doSerialize(__ctx,this) else macro $b{el} };
						${ if( addCustomSerializable ) macro this.customSerialize(__ctx) else macro { } };
					}
				}),
			});
			var schema = [];
			for( s in toSerialize ) {
				var name = s.f.name;
				var acall = s.f == serializePriority ? "unshift" : "push";
				var e = macro { schema.fieldsNames.$acall($v{name}); schema.fieldsTypes.$acall(hxbit.Macros.getFieldType(this.$name)); };
				schema.push(e);
			}
			fields.push({
				name : "getSerializeSchema",
				pos : pos,
				access : access,
				meta : noCompletion,
				kind : FFun({
					args : [],
					ret : null,
					expr : macro {
						var schema = ${if( isSubSer ) macro super.getSerializeSchema() else macro new hxbit.Schema()};
						$b{schema};
						schema.isFinal = hxbit.Serializer.isClassFinal(__clid);
						return schema;
					}
				})
			});
		}

		if( fieldsInits.length > 0 || !isSubSer )
			fields.push({
				name : "unserializeInit",
				pos : pos,
				meta : noCompletion,
				access : access,
				kind : FFun({
					args : [],
					ret : null,
					expr : isSubSer ? macro { super.unserializeInit(); $b{fieldsInits}; } : { expr : EBlock(fieldsInits), pos : pos },
				})
			});

		if( needUnserialize ) {
			var unserExpr = macro @:privateAccess {
				${ if( serializePriorityFuns != null ) serializePriorityFuns.unser else macro { } };
				${ if( isSubSer ) macro super.unserialize(__ctx) else macro { } };
				${ if( useStaticSer ) macro doUnserialize(__ctx,this) else macro $b{ul} };
				${ if( addCustomUnserializable ) macro this.customUnserialize(__ctx) else macro { } };
			};

			var unserFound = false;
			for( f in fields )
				if( f.name == "unserialize" ) {
					var found = false;
					function repl(e:Expr) {
						switch( e.expr ) {
						case ECall( { expr : EField( { expr : EConst(CIdent("super")) }, "unserialize") }, [ctx]):
							found = true;
							return macro { var __ctx : hxbit.Serializer = $ctx; $unserExpr; }
						default:
							return haxe.macro.ExprTools.map(e, repl);
						}
					}
					switch( f.kind ) {
					case FFun(f):
						f.expr = repl(f.expr);
					default:
					}
					if( !found ) Context.error("Override of unserialize() with no super.unserialize(ctx) found", f.pos);
					unserFound = true;
					break;
				}

			if( useStaticSer ) fields.push({
				name : "doUnserialize",
				pos : pos,
				access : [AStatic],
				meta : noCompletion,
				kind : FFun({
					args : [ { name : "__ctx", type : macro : hxbit.Serializer }, { name : "__this", type : TPath({ pack : [], name : cl.name }) } ],
					ret : null,
					expr : macro $b{ul},
				}),
			});

			if( !unserFound ) fields.push({
				name : "unserialize",
				pos : pos,
				access : access,
				kind : FFun({
					args : [ { name : "__ctx", type : macro : hxbit.Serializer } ],
					ret : null,
					expr : unserExpr,
				}),
			});
		}

		return fields;
	}

	public static function buildSerializableEnum() {
		var pt = switch( Context.getLocalType() ) {
		case TInst(_, [pt]): pt;
		default: null;
		}
		if( pt != null )
			pt = Context.follow(pt);
		if( pt != null )
		switch( pt ) {
		case TEnum(e, tparams):
			var e = e.get();
			var pathName = getNativePath(e);
			var className = makeEnumPath(pathName);
			try {
				return Context.getType(className);
			} catch( _ : Dynamic ) {
				var pos = Context.currentPos();
				var cases = [], ucases = [], schemaExprs = [];
				if( e.names.length >= 256 )
					Context.error("Too many constructors", pos);
				for( f in e.names ) {
					var c = e.constructs.get(f);
					switch( Context.follow(c.type) ) {
					case TFun(args, _):
						var eargs = [for( a in args ) { var arg = { expr : EConst(CIdent("_"+a.name)), pos : c.pos }; macro hxbit.Macros.serializeValue(ctx, $arg); }];
						cases.push({
							values : [{ expr : ECall({ expr : EConst(CIdent(c.name)), pos : pos },[for( a in args ) { expr : EConst(CIdent("_"+a.name)), pos : pos }]), pos : pos }],
							expr : macro {
								ctx.addByte($v{c.index+1});
								$b{eargs};
							}
						});

						var evals = [], etypes = [];
						for( a in args ) {
							var aname = "_" + a.name;
							var at = haxe.macro.TypeTools.applyTypeParameters(a.t,e.params,tparams).toComplexType();
							evals.push(macro var $aname : $at);
							evals.push(macro hxbit.Macros.unserializeValue(ctx,$i{aname}));
							etypes.push(macro { name : $v{a.name}, type : { var v : $at; hxbit.Macros.getFieldType(v); }, opt : $v{a.opt} });
						}
						evals.push({ expr : ECall({ expr : EConst(CIdent(c.name)), pos : pos },[for( a in args ) { expr : EConst(CIdent("_"+a.name)), pos : pos }]), pos : pos });
						ucases.push({
							values : [macro $v{c.index+1}],
							expr : { expr : EBlock(evals), pos : pos },
						});
						schemaExprs.push(macro s.fieldsTypes.push(PObj([$a{etypes}])));

					default:
						if( c.name == "_" ) Context.error("Invalid enum constructor", c.pos);
						cases.push({
							values : [ { expr : EConst(CIdent(c.name)), pos : pos } ],
							expr : macro ctx.addByte($v{c.index+1}),
						});
						ucases.push({
							values : [macro $v{c.index+1}],
							expr : { expr : EConst(CIdent(c.name)), pos : pos },
						});
						schemaExprs.push(macro s.fieldsTypes.push(null));
					}
					schemaExprs.push(macro s.fieldsNames.push($v{f}));
				}
				var t : TypeDefinition = {
					name : className.split(".").pop(),
					pack : ["hxbit","enumSer"],
					kind : TDClass(),
					fields : [
					{
						name : "doSerialize",
						access : [AStatic],
						pos : pos,
						kind : FFun( {
							args : [{ name : "ctx", type : macro : hxbit.Serializer },{ name : "v", type : pt.toComplexType() }],
							expr : macro @:privateAccess if( v == null ) ctx.addByte(0) else ${{ expr : ESwitch(macro v,cases,null), pos : pos }},
							ret : macro : Void,
						}),
					},{
						name : "doUnserialize",
						access : [AStatic],
						pos : pos,
						kind : FFun( {
							args : [{ name : "ctx", type : macro : hxbit.Serializer }],
							expr : macro @:privateAccess {
								var b = ctx.getByte();
								if( b == 0 )
									return null;
								var conv = @:privateAccess ctx.enumConvert[$v{pathName}];
								if( conv != null && conv.constructs[b-1] != null ) return ctx.convertEnum(conv);
								return ${{ expr : ESwitch(macro b,ucases,macro throw "Invalid enum index "+b), pos : pos }}
							},
							ret : pt.toComplexType(),
						}),

					},{
						name : "getSchema",
						access : [AStatic, APublic],
						meta : [{name:":ifFeature",pos:pos, params:[macro "hxbit.Dump.readValue"]}],
						pos : pos,
						kind : FFun( {
							args : [],
							expr : macro { var s = new Schema(); $b{schemaExprs}; return s; },
							ret : macro : hxbit.Schema,
						}),
					},{
						name : "serialize",
						access : [AInline, APublic],
						meta : [{name:":extern",pos:pos}],
						pos : pos,
						kind : FFun( {
							args : [{ name : "ctx", type : macro : hxbit.Serializer },{ name : "v", type : pt.toComplexType() }],
							expr : macro { @:privateAccess ctx.usedEnums[$v{pathName}] = true; doSerialize(ctx,v); },
							ret : null,
						}),
					},{
						name : "unserialize",
						access : [AInline, APublic],
						meta : [{name:":extern",pos:pos}],
						pos : pos,
						kind : FFun( {
							args : [{ name : "ctx", type : macro : hxbit.Serializer }],
							expr : macro return doUnserialize(ctx),
							ret : null,
						}),
					}],
					pos : pos,
				};

				// hack to allow recursion (duplicate serialize/unserialize for recursive usage)
				var tf = Reflect.copy(t.fields[t.fields.length - 2]);
				tf.name += "2";
				t.fields.push(tf);
				var tf = Reflect.copy(t.fields[t.fields.length - 2]);
				tf.name += "2";
				t.fields.push(tf);

				Context.defineType(t);
				return Context.getType(className);
			}
		default:
		}
		Context.error("Enum expected", Context.currentPos());
		return null;
	}

	static function quickInferType( e : Expr ) {
		if( e == null )
			return null;
		switch( e.expr ) {
		case EConst(CInt(_)):
			return macro : Int;
		case EConst(CFloat(_)):
			return macro : Float;
		case EConst(CString(_)):
			return macro : String;
		case EConst(CIdent("true" | "false")):
			return macro : Bool;
		default:
		}
		return null;
	}

	static function needProxy( t : PropType ) {
		if( t == null || t.isProxy )
			return false;
		switch( t.d ) {
		case PMap(_), PArray(_), PObj(_), PVector(_), PFlags(_):
			return !t.notMutable;
		default:
			return false;
		}
	}

	static function checkProxy( p : PropType ) {
		if( needProxy(p) ) {
			p.isProxy = true;
			p.t = toProxy(p);
		}
	}

	static function toProxy( p : PropType ) {
		if( !p.isProxy )
			return p.t;
		var pt = p.t;
		return macro : hxbit.Proxy<$pt>;
	}


	static var hasRetVal : Bool;
	static var hasRetCall : Bool;
	static function hasReturnVal( e : Expr ) {
		hasRetVal = false;
		hasRetCall = false;
		checkRetVal(e);
		if( hasRetCall ) hasRetVal = false;
		return { value : hasRetVal, call : hasRetCall };
	}

	static function checkRetVal( e : Expr ) {
		switch( e.expr ) {
		case EReturn(e):
			if( e != null ) {
				hasRetVal = true;
				checkRetVal(e);
			}
		case ECall({ expr : EConst(CIdent("__return")) },_):
			hasRetCall = true;
		case EFunction(_):
			var prev = hasRetVal;
			haxe.macro.ExprTools.iter(e, checkRetVal);
			hasRetVal = prev;
			return;
		default:
			haxe.macro.ExprTools.iter(e, checkRetVal);
		}
	}

	static function replaceReturns( e : Expr ) {
		switch( e.expr ) {
		case EReturn(v) if( v != null ):
			e.expr = (macro { __return($v); return; }).expr;
		case EFunction(_):
			return;
		default:
			haxe.macro.ExprTools.iter(e, replaceReturns);
		}
	}

	static function superImpl( name : String, e : Expr ) {
		switch( e.expr ) {
		case EField( esup = { expr : EConst(CIdent("super")) }, fname) if( fname == name ):
			e.expr = EField(esup, name+"__impl");
		default:
		}
		return haxe.macro.ExprTools.map(e, superImpl.bind(name));
	}

	static function replaceSetter( fname : String, setExpr : Expr -> Expr, e : Expr ) {
		switch( e.expr ) {
		case EBinop(OpAssign, e1 = { expr : (EConst(CIdent(name)) | EField( { expr : EConst(CIdent("this")) }, name)) }, e2) if( name == fname ):
			e.expr = EBinop(OpAssign,e1,setExpr(e2));
		case EBinop(OpAssignOp(_), { expr : (EConst(CIdent(name)) | EField( { expr : EConst(CIdent("this")) }, name)) }, _) if( name == fname ):
			throw "TODO";
		default:
			haxe.macro.ExprTools.iter(e, function(e) replaceSetter(fname,setExpr,e));
		}
	}

	public static function buildNetworkSerializable(?fields: Array<Field>) {
		var cl = Context.getLocalClass().get();
		if( cl.isInterface || Context.defined("display") )
			return null;

		var clName = Context.getLocalClass().toString();
		NW_BUILD_STACK.push(clName);

		if(fields == null)
			fields = Context.getBuildFields();
		var toSerialize = [];
		var rpc = [];
		var superRPC = new Map();
		var superFields = new Map();
		var startFID = 0, rpcID = 0;
		{
			var sup = cl.superClass;
			while( sup != null ) {
				var c = sup.t.get();
				for( m in c.meta.get() )
					switch( m.name)  {
					case ":rpcCalls":
						for( a in m.params )
							switch( a.expr ) {
							case EConst(CIdent(id)):
								rpcID++;
								superRPC.set(id, true);
							default:
								throw "assert";
							}
					case ":sFields":
						for( a in m.params )
							switch( a.expr ) {
							case EConst(CIdent(id)):
								superFields.set(id, true);
								startFID++;
							default:
								throw "assert";
							}
					}
				sup = c.superClass;
			}
		}

		for( f in fields ) {

			if( superRPC.exists(f.name) ) {
				switch( f.kind ) {
				case FFun(ff):
					ff.expr = superImpl(f.name, ff.expr);
				default:
				}
				f.name += "__impl";
				continue;
			}

			if( f.access.indexOf(AOverride) >= 0 && StringTools.startsWith(f.name, "set_") && superFields.exists(f.name.substr(4)) ) {
				// overridden setter of network property
				var fname = f.name.substr(4);
				switch( f.kind ) {
				case FFun(ff):
					replaceSetter(fname, function(e) return macro $i{"__net_mark_"+fname}($e), ff.expr);
				default:
				}
				continue;
			}

			if( f.meta == null ) continue;

			for( meta in f.meta ) {
				if( meta.name == ":s" ) {
					var vis : Null<Int> = null;
					for( m in f.meta )
						if( m.name == ":visible" ) {
							vis = getVisibility(m);
							break;
						}
					toSerialize.push({ f : f, m : meta, visibility : vis, type : null });
					break;
				}
				if( meta.name == ":rpc" ) {
					var mode : RpcMode = All;
					if( meta.params.length != 0 )
						switch( meta.params[0].expr ) {
						case EConst(CIdent("all")):
						case EConst(CIdent("clients")): mode = Clients;
						case EConst(CIdent("server")): mode = Server;
						case EConst(CIdent("owner")): mode = Owner;
						case EConst(CIdent("immediate")): mode = Immediate;
						default:
							Context.error("Unexpected Rpc mode : should be all|clients|server|owner|immediate", meta.params[0].pos);
						}
					rpc.push( { f : f, mode:mode } );
					superRPC.set(f.name, true);
					break;
				}
			}
		}

		var sup = cl.superClass;
		var isSubSer = sup != null && isSerializable(sup.t);
		var pos = Context.currentPos();
		if( !isSubSer ) {
			fields = fields.concat((macro class {
				@:noCompletion public var __host : hxbit.NetworkHost;
				@:noCompletion public var __bits1 : Int = 0;
				@:noCompletion public var __bits2 : Int = 0;
				@:noCompletion public var __next : hxbit.NetworkSerializable;
				#if hxbit_visibility
				@:noCompletion public var __cachedVisibility : Map<hxbit.NetworkSerializable,Int>;
				@:noCompletion public var __dirtyVisibilityGroups : Int;
				#end
				@:noCompletion public function networkSetBit( b : Int ) {
					if( __host != null && @:privateAccess __host.checkSyncingProperty(b) && (__host.isAuth || @:privateAccess __host.checkWrite(this,b)) && (__next != null || @:privateAccess __host.mark(this)) ) {
						if( b < 30 ) __bits1 |= 1 << b else __bits2 |= 1 << (b-30);
					}
				}
				public var enableReplication(get, set) : Bool;
				public var enableAutoReplication(get, set) : Bool;
				inline function get_enableReplication() return __host != null;
				inline function get_enableAutoReplication() return __next == this && __host == null;
				function set_enableReplication(b) {
					@:privateAccess hxbit.NetworkHost.enableReplication(this, b);
					return b;
				}
				function set_enableAutoReplication(b) {
					if( __host != null )
						return false; // ignore (we're already replicated anyway)
					if( __next == this ) {
						if( !b ) __next = null;
					} else if( b ) {
						if( __next != null ) throw "Can't set auto replication if modified";
						__next = this;
					}
					return b;
				}
				public function networkCancelProperty( props : hxbit.NetworkSerializable.NetworkProperty ) {
					var b = props.toInt();
					if( b < 30 ) __bits1 &= ~(1<<b) else __bits2 &= ~(1<<(b-30));
				}
				public inline function networkLocalChange( f : Void -> Void ) {
					var old = __host;
					__host = null;
					f();
					__host = old;
				}
				#if hxbit_visibility
				public inline function setVisibilityDirty( group : hxbit.VisibilityGroup ) {
					__dirtyVisibilityGroups |= 1 << group.getIndex();
					if( __next == null && __host != null ) @:privateAccess __host.mark(this);
				}
				#end
			}).fields);

			if( !Lambda.exists(fields, function(f) return f.name == "networkAllow") )
				fields = fields.concat((macro class {
					public function networkAllow( mode : hxbit.NetworkSerializable.Operation, prop : Int, client : hxbit.NetworkSerializable ) {
						return false;
					}
				}).fields);

			if( !Lambda.exists(fields, function(f) return f.name == "alive") )
				fields = fields.concat((macro class {
					public function alive() { enableReplication = true; }
				}).fields);

			#if hxbit_visibility
			if( !Lambda.exists(fields, function(f) return f.name == "evalVisibility") )
				fields = fields.concat((macro class {
					public function evalVisibility( group : hxbit.VisibilityGroup, from : hxbit.NetworkSerializable ) { return false; }
				}).fields);
			#end

		}

		var firstFID = startFID;
		var flushExpr = [];
		var syncExpr = [];
		var initExpr = [];
		var noComplete : Metadata = [ { name : ":noCompletion", pos : pos } ];
		for( f in toSerialize ) {
			var pos = f.f.pos;
			var fname = f.f.name;
			var getter = "default";
			var einit : Expr;
			var t = null;

			switch( f.f.kind ) {
			case FVar(_t, _e):
				t = _t;
				einit = _e;
			case FProp(_get, _set, _t, _e):
				getter = _get;
				t = _t;
				einit = _e;
				if( _set == "null" ) {
					#if !hxbit_no_warning
					Context.warning("Null setter is not respected when using NetworkSerializable", pos);
					#end
				} else if( _set != "default" && _set != "set" )
					Context.error("Invalid setter", pos);
			default:
				throw "assert";
			}

			if( t == null ) t = quickInferType(einit);
			if( t == null ) Context.error("Type required", pos);
			var tt = Context.resolveType(t, pos);
			var ftype = getPropField(tt, f.f.meta, true);
			if( ftype == null ) {
				// error here (even if it might error again in serialize code)
				Context.error("Unsupported serializable type "+tt.toString(), pos);
				ftype = { t : t, d : PUnknown };
			} else if( ftype.d == PUnknown ) {
				Context.error("Could not resolve field type", pos);
				ftype.t = t;
			}
			checkProxy(ftype);
			if( ftype.isProxy ) {
				switch( ftype.d ) {
				case PFlags(_) if( einit == null ): einit = macro new hxbit.EnumFlagsProxy(0);
				case PMap(_) if( einit != null ):
					switch( einit.expr ) {
					case EArrayDecl(vl) if( vl.length == 0 ): einit = macro new Map();
					default:
					}
				default:
				}
				if( einit != null ) {
					initExpr.push(macro this.$fname = $einit);
					einit = null;
				}
			}
			f.type = ftype;
			f.f.kind = FProp(getter,"set", ftype.t, einit);

			var bitID = startFID++;
			var markExpr = macro networkSetBit($v{ bitID });
			markExpr = makeMarkExpr(fields, fname, ftype, markExpr);

			var compExpr : Expr = macro this.$fname != v;
			if(ftype.d.match(PEnum(_)))
				compExpr = macro !Type.enumEq(this.$fname, v);

			var markFun = "__net_mark_" + f.f.name;
			fields.push( {
				name : markFun,
				access : [AInline],
				meta : noComplete,
				pos : pos,
				kind : FFun({
					args : [{ name : "v", type : ftype.t }],
					ret : ftype.t,
					expr : macro {
						if( $compExpr ) {
							$markExpr;
							${if( ftype.isProxy ) macro (if( v != null ) v.bindHost(this,$v{bitID})) else macro {}};
						}
						return v;
					}
				}),
			});

			var found = false;
			for( set in fields )
				if( set.name == "set_" + f.f.name )
					switch( set.kind ) {
					case FFun(fun):
						replaceSetter(f.f.name, function(e) return withPos(macro $i{markFun}($e),e.pos),fun.expr);
						found = true;
						break;
					default:
					}
			if( !found )
				fields.push({
					name : "set_" + fname,
					pos : pos,
					kind : FFun({
						args : [ { name : "v", type : ftype.t } ],
						expr : macro return this.$fname = $i{markFun}(v),
						ret : ftype.t,
					}),
				});
			var fexpr = { expr : EField({ expr : EConst(CIdent("this")), pos : pos }, fname), pos : pos };
			var bindex = bitID < 30 ? 1 : 2;
			var bvarBit = bitID < 30 ? bitID : bitID - 30;
			flushExpr.push(macro if( $i{"b"+bindex} & (1 << $v{bvarBit} ) != 0 ) hxbit.Macros.serializeValue(ctx, $fexpr));
			syncExpr.push(macro if( $i{"__bits"+bindex} & (1 << $v{bvarBit} ) != 0 ) {
				@:privateAccess __host.isSyncingProperty = $v{bitID};
				hxbit.Macros.unserializeValue(ctx, $fexpr);
				@:privateAccess __host.isSyncingProperty = -1;
			});

			var prop = "networkProp" + fname.charAt(0).toUpperCase() + fname.substr(1);
			fields.push({
				name : prop,
				pos : pos,
				kind : FProp("get", "never", macro : hxbit.NetworkSerializable.NetworkProperty),
				access : [APublic],
			});
			fields.push({
				name : "get_"+prop,
				pos : pos,
				kind : FFun( {
					args : [],
					expr : macro return new hxbit.NetworkSerializable.NetworkProperty($v{bitID}),
					ret : null,
				}),
				access : [AInline],
			});
		}

		// BUILD RPC
		var firstRPCID = rpcID;
		var rpcCases = [];
		for( r in rpc ) {
			switch( r.f.kind ) {
			case FFun(f):
				var id = rpcID++;
				var returnVal = hasReturnVal(f.expr);
				var name = r.f.name;
				var p = r.f.pos;
				var retType = f.ret;
				r.f.name += "__impl";

				var cargs = [for( a in f.args ) { expr : EConst(CIdent(a.name)), pos : p } ];
				var fcall = { expr : ECall( { expr : EField( { expr : EConst(CIdent("this")), pos:p }, r.f.name), pos : p }, cargs), pos : p };

				var doCall = fcall;
				var rpcArgs = f.args;
				var funArgs = f.args;
				var resultCall = macro null;

				if( returnVal.value || returnVal.call ) {
					var typeValue;
					if( returnVal.call ) {
						replaceReturns(f.expr);
						rpcArgs = f.args.copy();
						funArgs = f.args.copy();
						f.ret = macro : Void;
						cargs.push(macro onResult);
						f.args.push({ name : "__return" });
						doCall = macro {
							if( onResult == null ) onResult = function(_){};
							$fcall;
						}
						typeValue = macro { function onResult(v) _v = v; $fcall; };
					} else {
						typeValue = macro _v = $fcall;
						doCall = macro {
							var _v = $fcall;
							if( onResult != null ) onResult(_v);
						}
					}
					resultCall = withPos(macro function(__ctx:hxbit.NetworkSerializable.NetworkSerializer) {
						var _v = cast null;
						if( false ) $typeValue;
						hxbit.Macros.unserializeValue(__ctx, _v);
						if( __ctx.error ) return false;
						if( onResult != null ) onResult(_v);
						return true;
					},f.expr.pos);
					rpcArgs = rpcArgs.copy();
					rpcArgs.push( { name : "onResult", opt: true, type: retType == null ? null : TFunction([retType], macro:Void) } );
				}

				var forwardRPC = macro {
					@:privateAccess __host.doRPC(this,$v{id},$resultCall, function(__ctx) {
						$b{[
							for( a in funArgs )
								withPos(macro hxbit.Macros.serializeValue(__ctx, $i{a.name}), f.expr.pos)
						] };
					});
				};

				if( (returnVal.value || returnVal.call) && r.mode != Server && r.mode != Owner )
					Context.error("Cannot use return value with default rpc mode, use @:rpc(server) or @:rpc(owner)", r.f.pos);

				var rpcExpr = switch( r.mode ) {
				case All:
					macro {
						if( __host != null ) {
							if( !__host.isAuth && !networkAllow(RPC, $v{id}, __host.self.ownerObject) ) {
								var fieldName = networkGetName($v{id}, true);
								__host.logError('Calling the RPC $fieldName on a not allowed object');
								return;
							}
							$forwardRPC;
							if( !__host.isAuth ) return;
						}
						$doCall;
					}
				case Clients:
					macro {
						if( __host != null && __host.isAuth ) {
							$forwardRPC;
							return;
						}
						$doCall;
					}
				case Server:
					macro {
						if( __host == null ) return; // not shared object --> no server
						if( !__host.isAuth ) {
							if( !networkAllow(RPCServer, $v{id}, __host.self.ownerObject) ) {
								var fieldName = networkGetName($v{id}, true);
								__host.logError('Calling the RPC $fieldName on a not allowed object');
								return;
							}
							$forwardRPC;
							return;
						}
						$doCall;
					}
				case Owner:
					macro {
						if( __host == null )
							return; // no distant target possible (networkAllow = false)
						if( __host.isAuth ) {
							// multiple forward possible
							@:privateAccess __host.dispatchClients(function(client) {
								if( networkAllow(Ownership,$v{id},client.ownerObject) && __host.setTargetOwner(client.ownerObject) ) {
									$forwardRPC;
									__host.setTargetOwner(null);
								}
							});
							if( networkAllow(Ownership, $v{id}, __host.self.ownerObject) )
								$doCall;
						} else {
							if( !networkAllow(RPCOwner, $v{id}, __host.self.ownerObject) ) {
								var fieldName = networkGetName($v{id}, true);
								__host.logError('Calling the RPC $fieldName on a not allowed object');
								return;
							}
							// might ping-pong, but need to preserve order
							$forwardRPC;
						}
					}
				case Immediate:
					macro {
						if( __host != null ) {
							if( !__host.isAuth && !networkAllow(Ownership, $v{id}, __host.self.ownerObject) ) {
								var fieldName = networkGetName($v{id}, true);
								__host.logError('Calling the RPC $fieldName on a not allowed object');
								return;
							}
							$forwardRPC;
						}
						$doCall;
					}
				};

				var rpc : Field = {
					name : name,
					access : r.f.access.copy(),
					kind : FFun({
						args : rpcArgs,
						ret : macro : Void,
						expr : rpcExpr,
					}),
					pos : p,
					meta : [{ name : ":final", pos : p }],
				};
				fields.push(rpc);

				r.f.access.remove(APublic);
				r.f.meta.push( { name : ":noCompletion", pos : p } );

				var exprs = [ { expr : EVars([for( a in funArgs ) { name : a.name, type : a.opt ? TPath({ pack : [], name : "Null", params : [TPType(a.type)] }) : a.type, expr : macro cast null } ]), pos : p } ];
				if( returnVal.call ) {
					exprs.push(macro var __v = cast null);
					exprs.push(macro if( false ) { function onResult(v) __v = v; $fcall; }); // force typing
				} else
					exprs.push(macro if( false ) $fcall); // force typing
				for( a in funArgs ) {
					var e = macro hxbit.Macros.unserializeValue(__ctx, $i{ a.name });
					e.pos = p;
					exprs.push(e);
				}
				exprs.push(macro if( __ctx.error ) return false);
				exprs.push(macro if( __host != null ) __host.makeAlive());
				if( returnVal.call ) {
					exprs.push(macro {
						var __res = @:privateAccess __clientResult.beginAsyncRPCResult(null);
						function onResult(v) {
							if( false ) v = __v;
							@:privateAccess __clientResult.beginAsyncRPCResult(__res);
							hxbit.Macros.serializeValue(__ctx, v);
							@:privateAccess __clientResult.endAsyncRPCResult();
						}
						$fcall;
					});
				} else if( returnVal.value ) {
					exprs.push({ expr : EVars([ { name : "result", type : f.ret, expr : fcall } ]), pos : p } );
					exprs.push(macro {
						@:privateAccess __clientResult.beginRPCResult();
						hxbit.Macros.serializeValue(__ctx, result);
					});
				} else {

					// -- when receiving the rpc, check for additional security

					switch( r.mode ) {
					case All:
						exprs.push(macro {
							if( __host != null && __host.isAuth ) {
								// check again
								if( !networkAllow(RPC,$v{id},__host.rpcClient.ownerObject) )
									return false;
								$forwardRPC;
							}
							$fcall;
						});
					case Owner:
						// check again when receiving the RPC if we are on the good owner
						// the server might relay to the actual owner or simply drop if not connected
						exprs.push(macro {
							if( __host != null && __host.isAuth ) {
								// check again
								if( !networkAllow(RPC, $v{id}, __host.rpcClient.ownerObject) )
									return false;
								// multiple forward possible
								@:privateAccess __host.dispatchClients(function(client) {
									if( networkAllow(Ownership,$v{id},client.ownerObject) && __host.setTargetOwner(client.ownerObject) ) {
										$forwardRPC;
										__host.setTargetOwner(null);
									}
								});
								// only execute if ownership
								if( !networkAllow(Ownership, $v{id}, __host.self.ownerObject) )
									return true;
							}
							$fcall;
						});
					case Clients:
						exprs.push(macro {
							$fcall;
						});
					case Server:
						exprs.push(macro {
							if( __host == null || !__host.isAuth || !networkAllow(RPCServer, $v{id}, __host.rpcClient.ownerObject) )
								return false;
							$fcall;
						});
					case Immediate:
						exprs.push(macro {
							if( __host != null && __host.isAuth ) {
								// check again
								if( !networkAllow(Ownership,$v{id},__host.rpcClient.ownerObject) )
									return false;

								@:privateAccess __host.dispatchClients(function(client) {
									if(client != __host.rpcClient && __host.setTargetOwner(client.ownerObject) ) {
										$forwardRPC;
										__host.setTargetOwner(null);
									}
								});
							}
							$fcall;
						});
					}
				}

				rpcCases.push({ values : [{ expr : EConst(CInt(""+id)), pos : p }], guard : null, expr : { expr : EBlock(exprs), pos : p } });

			default:
				Context.error("Cannot use @:rpc on non function", r.f.pos);
			}
		}

		// Add network methods
		var access = [APublic];
		if( isSubSer ) access.push(AOverride);

		if( fields.length != 0 || !isSubSer ) {
			if( isSubSer ) {
				flushExpr.unshift(macro super.networkFlush(ctx));
				syncExpr.unshift(macro super.networkSync(ctx));
			} else {
				flushExpr.unshift(macro {
					if( __bits2 == 0 )
						ctx.addInt(__bits1);
					else if( __bits1 == 0 )
						ctx.addInt(__bits2 | 0x80000000);
					else {
						ctx.addInt(__bits1 | 0x40000000);
						ctx.addInt(__bits2);
					}
				});
				flushExpr.push(macro {
					__bits1 = 0;
					__bits2 = 0;
				});
			}
			flushExpr.unshift(macro var b1 = __bits1, b2 = __bits2);
			fields.push({
				name : "networkFlush",
				pos : pos,
				access : access,
				meta : noComplete,
				kind : FFun({
					args : [ { name : "ctx", type : macro : hxbit.Serializer } ],
					ret : null,
					expr : { expr : EBlock(flushExpr), pos : pos },
				}),
			});

			fields.push({
				name : "networkSync",
				pos : pos,
				access : access,
				meta : noComplete,
				kind : FFun({
					args : [ { name : "ctx", type : macro : hxbit.Serializer } ],
					ret : null,
					expr : macro @:privateAccess $b{syncExpr},
				}),
			});


			#if hxbit_visibility
			var groups = new Map();
			var allFields = haxe.Int64.ofInt(0);
			for( idx => f in toSerialize ) {
				var bit = haxe.Int64.ofInt(1) << (firstFID + idx);
				if( f.visibility == null ) {
					allFields |= bit;
					continue;
				}
				var mask = groups.get(f.visibility);
				if( mask == null ) {
					mask = { v : haxe.Int64.ofInt(0), fl : [] };
					groups.set(f.visibility, mask);
				}
				mask.v = mask.v | bit;
				mask.fl.push(f);
			}
			inline function i64V(v:haxe.Int64) {
				if( v.high == 0 )
					return macro haxe.Int64.ofInt($v{v.low});
				return macro haxe.Int64.make($v{v.high},$v{v.low});
			}
			var maskExpr = [];
			if( isSubSer )
				maskExpr.push(macro var mask = super.getVisibilityMask(groups) | ${i64V(allFields)});
			else
				maskExpr.push(macro var mask = ${i64V(allFields)});
			for( gid => gmask in groups )
				maskExpr.push(macro if( groups & (1 << $v{gid}) != 0 ) mask |= ${i64V(gmask.v)});
			maskExpr.push(macro return mask);
			fields.push({
				name : "getVisibilityMask",
				pos : pos,
				access : access,
				meta : noComplete,
				kind : FFun({
					args : [ { name : "groups", type : macro : Int } ],
					ret : null,
					expr : { expr : EBlock(maskExpr), pos : pos },
				}),
			});

			var scanExpr = [];
			scanExpr.push(macro if( refs[__uid] != null ) return);
			if( isSubSer )
				scanExpr.push(macro super.scanVisibility(from, refs));
			else
				scanExpr.push(macro refs[__uid] = this);
			if( groups.keys().hasNext() ) {
				scanExpr.push(macro var groups : Int = __cachedVisibility.get(from));
			}
			for( f in toSerialize ) {
				if( f.visibility != null ) continue;
				var fname = f.f.name;
				var expr = makeScanExpr(macro this.$fname, f.type, f.f.pos);
				if( expr != null ) scanExpr.push(expr);
			}
			for( gid => info in groups ) {
				scanExpr.push(macro if( groups & $v{1<<gid} != 0 ) $b{[for( f in info.fl ) {
					var fname = f.f.name;
					var expr = makeScanExpr(macro this.$fname, f.type, f.f.pos);
					if( expr != null ) expr;
				}]});
			}


			var found = false;
			for( f in fields ) {
				if( f.name == "scanVisibility" ) {
					function iterRec(e:Expr) {
						switch( e.expr ) {
						case ECall({ expr : EField({ expr : EConst(CIdent("super")) },"scanVisibility") },_):
							found = true;
							e.expr = EBlock(scanExpr);
						default:
							haxe.macro.ExprTools.iter(e, iterRec);
						}
					}
					switch( f.kind ) {
					case FFun(f): iterRec(f.expr);
					default: throw "assert";
					}
					if( !found )
						Context.error("Missing super() call", f.pos);
					break;
				}
			}

			if( !found ) {
				fields.push({
					name : "scanVisibility",
					pos : pos,
					access : access,
					meta : noComplete,
					kind : FFun({
						args : [
							{ name : "from", type : macro : hxbit.NetworkSerializable },
							{ name : "refs", type : macro : hxbit.Serializer.UIDMap },
						],
						ret : null,
						expr : { expr : EBlock(scanExpr), pos : pos },
					}),
				});
			}
			#end
		}

		if( initExpr.length != 0 || !isSubSer ) {
			if( isSubSer )
				initExpr.unshift(macro super.networkInitProxys());
			else {
				// inject in new
				var found = false;
				for( f in fields )
					if( f.name == "new" ) {
						switch( f.kind ) {
						case FFun(f):
							switch( f.expr.expr ) {
							case EBlock(b): b.unshift(macro networkInitProxys());
							default: f.expr = macro { networkInitProxys(); ${f.expr}; };
							}
							found = true;
							break;
						default: throw "assert";
						}
					}
				if( !found ) {
					// create a constructor
					fields.push((macro class {
						function new() {
							networkInitProxys();
						}
					}).fields[0]);
				}
			}
			fields.push({
				name : "networkInitProxys",
				pos : pos,
				access : access,
				meta : noComplete,
				kind : FFun({
					args : [],
					ret : null,
					expr : macro @:privateAccess $b{initExpr},
				}),
			});

		}

		if( rpc.length != 0 || !isSubSer ) {
			var swExpr = { expr : ESwitch( { expr : EConst(CIdent("__id")), pos : pos }, rpcCases, macro throw "Unknown RPC identifier " + __id), pos : pos };
			fields.push({
				name : "networkRPC",
				pos : pos,
				access : access,
				meta : noComplete,
				kind : FFun({
					args : [ { name : "__ctx", type : macro : hxbit.NetworkSerializable.NetworkSerializer }, { name : "__id", type : macro : Int }, { name : "__clientResult", type : macro : hxbit.NetworkHost.NetworkClient } ],
					ret : macro : Bool,
					expr : if( isSubSer && firstRPCID > 0 ) macro { if( __id < $v { firstRPCID } ) return super.networkRPC(__ctx, __id, __clientResult); $swExpr; return true; } else macro { $swExpr; return true; }
				}),
			});
		}


		if( toSerialize.length != 0 || rpc.length != 0 || !isSubSer ) {
			var cases = [];
			for( i in 0...toSerialize.length )
				cases.push( { id : i + firstFID, name : toSerialize[i].f.name } );
			for( i in 0...rpc.length )
				cases.push( { id : i + startFID + firstRPCID, name : rpc[i].f.name.substr(0,-6) } );
			var ecases = [for( c in cases ) { values : [ { expr : EConst(CInt("" + c.id)), pos : pos } ], expr : { expr : EConst(CString(c.name)), pos : pos }, guard : null } ];
			var swExpr = { expr : EReturn( { expr : ESwitch(macro isRPC ? id + $v { startFID } : id, ecases, macro null), pos : pos } ), pos : pos };
			fields.push( {
				name : "networkGetName",
				pos : pos,
				access : access,
				meta : noComplete,
				kind : FFun({
					args : [ { name : "id", type : macro : Int }, { name : "isRPC", type : macro : Bool, value:macro false } ],
					ret : macro : String,
					expr : if( isSubSer ) macro { if( id < (isRPC ? $v{ firstRPCID } : $v{ firstFID }) ) return super.networkGetName(id, isRPC); $swExpr; } else swExpr,
				}),
			});
		}


		// add metadata

		if( startFID > 61 ) Context.error("Too many serializable fields", pos);
		if( rpcID > 255 ) Context.error("Too many rpc calls", pos);

		if( rpc.length > 0 )
			cl.meta.add(":rpcCalls", [for( r in rpc ) { expr : EConst(CIdent(r.f.name.substr(0, -6))), pos : pos } ], pos);
		if( toSerialize.length > 0 )
			cl.meta.add(":sFields", [for( r in toSerialize ) { expr : EConst(CIdent(r.f.name)), pos : pos }], pos);

		NW_BUILD_STACK.pop();
		return fields;
	}

	static function makeScanExpr( expr : Expr, t : PropType, pos : Position ) {
		switch( t.d ) {
		case PInt, PFloat, PBool, PString, PBytes, PInt64, PFlags(_), PUnknown, PStruct:
		case PSerializable(name), PSerInterface(name):
			return macro if( $expr != null ) $expr.scanVisibility(from,refs);
		case PEnum(name):
			var e = switch( Context.resolveType(t.t, pos) ) {
			case TEnum(e,_): e.get();
			default: throw "assert";
			};
			var cases = [];
			for( c in e.constructs ) {
				switch( c.type ) {
				case TFun(args,_):
					var scans = [], eargs = [];
					for( a in args ) {
						var arg = macro $i{a.name};
						var se = makeScanExpr(macro $arg, getPropType(a.t,false), pos);
						if( se != null )
							scans.push(macro if( $arg != null ) $se);
						eargs.push(arg);
					}
					if( scans.length > 0 )
						cases.push({ values : [macro $i{c.name}($a{eargs})], expr : macro {$b{scans}} });
				default:
				}
			}
			var swexpr = { expr : ESwitch(expr,cases,macro null), pos : expr.pos };
			return cases.length == 0 ? null : macro if( $expr != null ) $swexpr;
		case PMap(k,v):
			var ek = makeScanExpr(macro __key, k, pos);
			var ev = makeScanExpr(macro __val, v, pos);
			if( ek == null && ev == null )
				return null;
			if( ek != null && ev != null )
				return macro if( $expr != null ) { for( __key => __val in $expr ) { $ek; $ev; } };
			if( ek != null )
				return macro if( $expr != null ) { for( __key in $expr.keys() ) $ek; };
			return macro if( $expr != null ) { for( __val in $expr ) $ev; };
		case PArray(v), PVector(v):
			var ev = makeScanExpr(macro __val, v, pos);
			return ev == null ? null : macro if( $expr != null ) { for( __val in $expr ) $ev; };
		case PObj(fields):
			var out = [];
			for( f in fields ) {
				var name = f.name;
				var ev = makeScanExpr(macro $expr.$name, f.type, pos);
				if( ev != null )
					out.push(macro if( $expr.$name != null ) $ev);
			}
			return out.length == 0 ? null : macro if( $expr != null ) $b{out};
		case PAlias(t):
			return makeScanExpr(expr, t, pos);
		case PNull(t):
			return makeScanExpr(expr, t, pos);
		case PDynamic:
			return macro @:privateAccess hxbit.NetworkHost.scanDynRec($expr, from, refs);
		}
		return null;
	}

	static function makeMarkExpr( fields : Array<Field>, fname : String, t : PropType, mark : Expr ) {
		var rname = "__ref_" + fname;
		var needRef = false;
		if( t.increment != null ) {
			needRef = true;
			mark = macro if( Math.floor(v / $v{t.increment}) != this.$rname ) { this.$rname = Math.floor(v / $v{t.increment}); $mark; };
		}
		if( t.condSend != null ) {
			function loop(e:Expr) {
				switch( e.expr ) {
				case EConst(CIdent("current")):
					needRef = true;
					return { expr : EConst(CIdent(rname)), pos : e.pos };
				default:
					return haxe.macro.ExprTools.map(e, loop);
				}
			}
			if( t.condSend.expr.match(EConst(CIdent("false"))) )
				return macro {}; // no marking
			var condSend = loop(t.condSend);
			if( needRef ) {
				mark = macro if( $condSend ) { this.$rname = v; $mark; };
			} else {
				mark = macro if( $condSend ) $mark;
			}
		}
		if( needRef && fields != null )
			fields.push({
				name : rname,
				pos : mark.pos,
				meta : [{ name : ":noCompletion", pos : mark.pos }],
				kind : FVar(t.t, switch( t.d ) { case PInt, PFloat: macro 0; default: macro null; }),
			});
		return mark;
	}

	static function typeName(t:PropType) {
		switch( t.d ) {
		case PObj(fields):
			var fields = fields.copy();
			fields.sort(function(f1, f2) return Reflect.compare(f1.name, f2.name));
			return "O"+[for( f in fields ) f.name+"_" + ~/[<>.]/g.replace(typeName(f.type),"_")].join("_");
		case PArray(t):
			return "Arr_" + typeName(t);
		case PMap(k,v):
			return "Map_"+typeName(k)+"_"+typeName(v);
		default:
		}
		var str = t.t.toString();
		str = str.split("<StdTypes.").join("<");
		if( StringTools.startsWith(str, "StdTypes.") )
			str = str.substr(9);
		return str;
	}


	static function buildProxyType( p : PropType ) : ComplexType {
		if( !needProxy(p) )
			return p.t;
		switch( p.d ) {
		case PArray(k):
			checkProxy(k);
			var subName = k.isProxy ? "ArrayProxy2" : "ArrayProxy";
			return TPath( { pack : ["hxbit"], name : "ArrayProxy", sub : subName, params : [TPType(k.t)] } );
		case PVector(k):
			checkProxy(k);
			var subName = k.isProxy ? "VectorProxy2" : "VectorProxy";
			return TPath( { pack : ["hxbit"], name : "VectorProxy", sub : subName, params : [TPType(k.t)] } );
		case PMap(k, v):
			checkProxy(v);
			var subName = v.isProxy ? "MapProxy2" : "MapProxy";
			return TPath( { pack : ["hxbit"], name : "MapProxy", sub : subName, params : [TPType(k.t),TPType(v.t)] } );
		case PObj(fields):
			// define type
			var name = "ObjProxy_";
			name += typeName(p);
			try {
				return Context.getType("hxbit." + name).toComplexType();
			} catch( e : Dynamic ) {
				var pos = Context.currentPos();
				var pt = p.t;
				var myT = TPath( { pack : ["hxbit"], name : name } );
				var tfields = (macro class {
					var obj : hxbit.NetworkSerializable.ProxyHost;
					var bit : Int;
					@:noCompletion public var __value(get, never) : $pt;
					inline function get___value() : $pt return cast this;
					inline function mark() if( obj != null ) obj.networkSetBit(bit);
					@:noCompletion public function networkSetBit(_) mark();
					@:noCompletion public function bindHost(obj, bit) { this.obj = obj; this.bit = bit; }
					@:noCompletion public function unbindHost() this.obj = null;
					@:noCompletion public function toString() return hxbit.NetworkSerializable.BaseProxy.objToString(this);
				}).fields;
				for( f in fields ) {
					var ft = f.type.t;
					var fname = f.name;
					tfields.push({
						name : f.name,
						pos : pos,
						access : [APublic],
						kind : FProp("default","set",ft),
					});

					var markExpr = makeMarkExpr(tfields, fname, f.type, macro mark());
					var cond = macro this.$fname != v;
					var check = switch( f.type.d ) {
						case PInt, PFloat, PBool, PString, PInt64: true;
						case PNull({ d : PInt | PFloat | PBool | PString | PInt64 }): true;
						default: false;
					}
					if( check )
						markExpr = macro if(this.$fname != v) $markExpr;

					tfields.push( {
						name : "set_" + f.name,
						pos : pos,
						access : [AInline],
						kind : FFun({
							ret : ft,
							args : [ { name : "v", type : ft } ],
							expr : macro { $markExpr; this.$fname = v; return v; }
						}),
					});
				}
				tfields.push({
					name : "new",
					pos : pos,
					access : [APublic],
					kind : FFun({
						ret : null,
						args : [for( f in fields ) { name : f.name, type : f.type.t, opt : f.opt } ],
						expr : { expr : EBlock([for( f in fields ) { var fname = f.name; macro this.$fname = $i{fname}; }]), pos : pos },
					})
				});
				var optMeta : Metadata = [{ name : ":optional", pos : pos, params : [] }];
				tfields.push({
					name : "__load",
					pos : pos,
					access : [APublic],
					kind : FFun({
						ret : null,
						args : [{ name : "v", type : TAnonymous([for( f in fields ) { name : f.name, pos : pos, kind : FVar(f.type.t), meta : f.opt ? optMeta : null }]) }],
						expr : { expr : EBlock([for( f in fields ) { var fname = f.name; macro this.$fname = v.$fname; }]), pos : pos },
					})
				});
				var t : TypeDefinition = {
					pos : pos,
					pack : ["hxbit"],
					meta : [{ name : ":structInit", pos : pos }],
					name : name,
					kind : TDClass([
						{ pack : ["hxbit"], name : "NetworkSerializable", sub : "ProxyHost" },
						{ pack : ["hxbit"], name : "NetworkSerializable", sub : "ProxyChild" },
					]),
					fields : tfields,
				};
				Context.defineType(t);
				return TPath({ pack : ["hxbit"], name : name });
			}
		case PFlags(e):
			return TPath( { pack : ["hxbit"], name : "EnumFlagsProxy", params : [TPType(e.t)] } );
		default:
		}
		return null;
	}

	public static function buildSerializableProxy() {
		var t = Context.getLocalType();
		switch( t ) {
		case TInst(_, [pt]):
			var p = getPropType(pt, false);
			if( p != null ) {
				var t = buildProxyType(p);
				if( t != null ) return toType(t);
			}
			throw "TODO "+pt+" ("+p+")";
		default:
			throw "assert";
		}
	}

	public static function buildVisibilityGroups() {
		try {
			Context.getType("hxbit.VisibilityGroupDef");
		} catch( e : Dynamic ) {
			var pos = Context.currentPos();
			Context.defineType({
				name : "VisibilityGroupDef",
				pack : ["hxbit"],
				pos : pos,
				kind : TDEnum,
				fields : [for( c in VISIBILITY_VALUES ) {
					pos : pos,
					name : c.charAt(0).toUpperCase() + c.substr(1),
					kind : FVar(null,null),
				}],
			});
		}
		return macro : hxbit.VisibilityGroupDef;
	}

	#end

}
