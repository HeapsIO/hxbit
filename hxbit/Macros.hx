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
	PCustom;
	PSerInterface( name : String );
	PStruct( name : String, fields : Array<{ name : String, type : PropType }> );
	PAliasCDB( k : PropType );
	PNoSave( k : PropType );
}

typedef PropType = {
	var d : PropTypeDesc<PropType>;
	var t : ComplexType;
	var ?isProxy : Bool;
	var ?increment : Float;
	var ?condSend : Expr;
	var ?notMutable : Bool;
	var ?noSync : Bool;
	var ?visibility : Int;
}

private enum Condition {
	PartialResolution;
	PreventCDB;
}

class Macros {

	static var PREFIX_VARS : Map<String,Bool> = null;
	public static var IGNORED_META : Map<String,Bool> = new Map();
	public static var VISIBILITY_VALUES = [];

	/** Generate game-specific property getters, mostly to be used in networkAllow() **/
	public static var CUSTOM_GETTERS : Array<{name: String, ret: ComplexType, func : {id: Int, name: String, field: Field} -> Dynamic }> = [];

	@:persistent static var NW_BUILD_STACK : Array<String> = [];

	#if macro
	public static function markAsSerializable( className : String ) {
		NW_BUILD_STACK.push(className);
	}
	#end

	public static function initVisibility(vis) {
		VISIBILITY_VALUES = vis;
	}

	public static function makeEnumPath( name : String ) {
		name = name.split(".").join("_");
		name = name.charAt(0).toUpperCase() + name.substr(1);
		return "hxbit.enumSer." + name;
	}

	public static macro function serializeValue( ctx : Expr, v : Expr ) : Expr {
		var t = Context.typeof(v);
		var conds = new haxe.EnumFlags<Condition>();
		var pt = getPropType(t, conds);
		if( pt == null ) {
			Context.error("Unsupported serializable type " + t.toString(), v.pos);
			return macro { };
		}
		return withPos(serializeExpr(ctx, v, pt),v.pos);
	}

	public static macro function unserializeValue( ctx : Expr, v : Expr, depth : Int = 0, conds : Int = 0 ) : Expr {
		var t = Context.typeof(v);
		var conds : haxe.EnumFlags<Condition> = cast conds;
		var pt = getPropType(t, conds);
		if( pt == null ) {
			Context.error("Unsupported serializable type " + t.toString(), v.pos);
			return macro { };
		}
		var cl = Context.getLocalClass();
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
		return withPos(unserializeExpr(ctx, v, pt, depth, conds),v.pos);
	}

	public static macro function markValue( v : Expr ) : Expr {
		var t = Context.typeof(v);
		var conds = new haxe.EnumFlags<Condition>();
		var pt = getPropType(t, conds);
		if( pt == null )
			return macro { };
		var se = markExpr(v, pt, v.pos);
		if( se == null )
			return macro { };
		return se;
	}

	public static macro function clearValue( v : Expr, ?isEnum:Bool ) : Expr {
		var t = Context.typeof(v);
		var conds = new haxe.EnumFlags<Condition>();
		var pt = getPropType(t, conds);
		if( pt == null )
			return macro { };
		var se = clearExpr(v, pt, v.pos, (e) -> isEnum ? macro { $v = $e; __changed = true; } : macro $v = $e);
		if( se == null )
			return macro { };
		return se;
	}

	public static macro function getFieldType( v : Expr ) {
		var t = Context.typeof(v);
		var conds = new haxe.EnumFlags<Condition>();
		var pt = getPropType(t, conds);
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
		case PAlias(t), PAliasCDB(t):
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
		case PAlias(t), PAliasCDB(t), PNoSave(t): return toFieldType(t);
		case PVector(k): PVector(toFieldType(k));
		case PNull(t): PNull(toFieldType(t));
		case PFlags(t): PFlags(toFieldType(t));
		case PCustom: PCustom;
		case PUnknown: PUnknown;
		case PDynamic: PDynamic;
		case PSerInterface(name): PSerInterface(name);
		case PStruct(name, fields): PStruct(name,[for( f in fields ) { name : f.name, type : toFieldType(f.type) }]);
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

	static function isCustomSerializable( c : Ref<ClassType> ) {
		return lookupInterface(c, "hxbit.CustomSerializable");
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

	static function getPropField( ft : Type, meta : Metadata, conds : haxe.EnumFlags<Condition> ) {
		for( m in meta )
			if( m.name == ":allowCDB" )
				conds.unset(PreventCDB);
		var t = getPropType(ft, conds);
		if( t == null )
			return null;
		for( m in meta) {
			switch( m.name ) {
			case ":s", ":optional", ":serializePriority", ":allowCDB", ":isVar":
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
			case ":noSync":
				t.notMutable = true;
				t.noSync = true;
			case ":noSave":
				var prev = t;
				t = Reflect.copy(t);
				t.d = PNoSave(prev);
			case ":visible" if( m.params.length == 1 ):
				t.visibility = getVisibility(m);
			case ":value":
				// generated by haxe 5
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

	static function getPropType( t : haxe.macro.Type, conds : haxe.EnumFlags<Condition> ) : PropType {
		var isProxy = false;
		var isMutable = true;
		var desc = switch( t ) {
		case TAbstract(a, pl):
			switch( a.toString() ) {
			case "haxe.Int64", "hl.I64":
				PInt64;
			case "Float", "Single":
				PFloat;
			case "Int","UInt":
				PInt;
			case "Bool":
				PBool;
			case "Map", "haxe.ds.Map":
				var tk = getPropType(pl[0],conds);
				var tv = getPropType(pl[1],conds);
				if( tk == null || tv == null )
					return null;
				PMap(tk, tv);
			case "haxe.ds.Vector":
				var tk = getPropType(pl[0],conds);
				if( tk == null )
					return null;
				PVector(tk);
			case "hxbit.VectorProxy":
				var t = getPropType(pl[0],conds);
				if( t == null )
					return null;
				isProxy = true;
				PVector(t);
			case "hxbit.ArrayProxy", "hxbit.ArrayProxy2":
				var t = getPropType(pl[0],conds);
				if( t == null )
					return null;
				isProxy = true;
				PArray(t);
			case "hxbit.MapProxy", "hxbit.MapProxy2":
				var k = getPropType(pl[0],conds);
				var v = getPropType(pl[1],conds);
				if( k == null || v == null ) return null;
				isProxy = true;
				PMap(k, v);
			case "hxbit.EnumFlagsProxy":
				var e = getPropType(pl[0],conds);
				if( e == null ) return null;
				isProxy = true;
				PFlags(e);
			case "haxe.EnumFlags":
				var e = getPropType(pl[0],conds);
				if( e == null ) return null;
				PFlags(e);
			case "Null":
				var p = getPropType(pl[0],conds);
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
				var ainf = a.get(), isCDB = false;
				if( ainf.meta.has(":cdb") ) {
					if( conds.has(PreventCDB) ) {
						Context.warning("Unsupported CDB type, store the id-kind or use @:allowCDB ", Context.currentPos());
						return null;
					}
					isCDB = true;
					isMutable = false;
				} else if( ainf.meta.has(":noProxy") )
					isMutable = false;
				var pt = getPropType(t2,conds);
				if( pt == null ) return null;
				isCDB ? PAliasCDB(pt) : PAlias(pt);
			}
		case TEnum(e,_):
			var e = e.get();
			var path = getNativePath(e);
			if( conds.has(PreventCDB) && e.meta.has(":cdb") ) {
				Context.warning("Unsupported enum containing CDB type, store the id-kind", Context.currentPos());
				return null;
			}
			PEnum(path);
		case TDynamic(_):
			PDynamic;
		case TAnonymous(a):
			var a = a.get();
			var fields = [];
			isMutable = false;
			for( f in a.fields ) {
				if( f.meta.has(":noSerialize") )
					continue;
				var ft = getPropField(f.type, f.meta.get(), conds);
				if( ft == null ) return null;
				fields.push( { name : f.name, type : ft, opt : f.meta.has(":optional") } );
				if( !(f.isFinal || ft.noSync) || needProxy(ft) ) isMutable = true;
			}
			a.fields.length == 0 ? PDynamic : PObj(fields);
		case TInst(c, pl):
			switch( c.toString() ) {
			case "String":
				PString;
			case "Array":
				var at = getPropType(pl[0],conds);
				if( at == null ) return null;
				PArray(at);
			case "haxe.ds.IntMap":
				var vt = getPropType(pl[0],conds);
				if( vt == null ) return null;
				PMap({ t : macro : Int, d : PInt }, vt);
			case "haxe.ds.StringMap":
				var vt = getPropType(pl[0],conds);
				if( vt == null ) return null;
				PMap({ t : macro : String, d : PString }, vt);
			case "haxe.io.Bytes":
				PBytes;
			case name if( StringTools.startsWith(name, "hxbit.ObjProxy_") ):
				var fields = c.get().fields.get();
				for( f in fields )
					if( f.name == "__value" ) {
						var t = getPropType(f.type,conds);
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
				} else if( isCustomSerializable(c) )
					PCustom;
				else if( isStructSerializable(c) ) {
					var c = c.get();
					var path = getNativePath(c);
					var fields = [];
					for( f in c.fields.get() ) {
						if( !f.meta.has(":s") ) continue;
						var t = getPropField(f.type, f.meta.get(), conds);
						if( t == null )
							return null;
						fields.push({ name : f.name, type : t });
					}
					if( c.meta.has(":isProxy") )
						isProxy = true;
					PStruct(path, fields);
				} else
					return null;
			}
		case TType(td, pl):
			switch( td.toString() ) {
			case "Null":
				var p = getPropType(pl[0],conds);
				if( p != null && !isNullable(p) )
					p = { d : PNull(p), t : TPath( { pack : [], name : "Null", params : [TPType(p.t)] } ) };
				return p;
			default:
				var p = getPropType(Context.follow(t, true),conds);
				if( p != null )
					p.t = t.toComplexType(); // more general, still identical
				return p;
			}
		case TLazy(f):
			// browsing TLazy would flush the context leading to more recursions,
			// since we are in our build phase, let's instead return Unknown
			if( conds.has(PartialResolution) )
				return { d : PUnknown, t : null };
			return getPropType(f(), conds);
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
		case PAlias(t), PAliasCDB(t), PNoSave(t):
			return isNullable(t);
		default:
			return true;
		}
	}

	static function toType( t : ComplexType ) : Type {
		return ComplexTypeTools.toType(t);
	}


	static function makeEnumCall( t : PropType, name : String, args ) {
		var et = t.t;
		return macro (null : hxbit.Serializable.SerializableEnum<$et>).$name($a{args});
	}

	static function serializeExpr( ctx : Expr, v : Expr, t : PropType, skipCheck = false ) {

		if( t.isProxy && !skipCheck && !t.d.match(PStruct(_)) )
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
			return makeEnumCall(t, "serialize", [ctx, v]);
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
		case PAlias(t), PAliasCDB(t):
			return serializeExpr(ctx, { expr : ECast(v, null), pos : v.pos }, t);
		case PNoSave(t):
			return macro if( !$ctx.forSave ) ${serializeExpr(ctx,v,t)};
		case PNull(t):
			var e = serializeExpr(ctx, v, t);
			return macro if( $v == null ) $ctx.addByte(0) else { $ctx.addByte(1); $e; };
		case PDynamic:
			return macro $ctx.addDynamic($v);
		case PFlags(t):
			return serializeExpr(ctx, { expr : ECast(v, null), pos : v.pos }, { t : macro : Int, d : PInt });
		case PCustom:
			return macro $ctx.addCustom($v);
		case PStruct(_):
			return macro {
				var v = $v;
				if( v == null )
					$ctx.addByte(0);
				else
					v.serialize($ctx);
			}
		case PUnknown:
			throw "assert";
		}
	}

	dynamic static function unserializeExpr( ctx : Expr, v : Expr, t : PropType, depth : Int, conds : haxe.EnumFlags<Condition> ) {
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
				$v = $ctx.getMap(function() { hxbit.Macros.unserializeValue($ctx, $vk, $v{depth + 1}, $v{conds.toInt()}); return $vk; }, function() { hxbit.Macros.unserializeValue($ctx, $vv, $v{depth+1}, $v{conds.toInt()}); return $vv; });
			};
		case PEnum(_):
			var et = t.t;
			return macro { var __e : $et; __e = ${makeEnumCall(t,"unserialize",[ctx])}; $v = __e; }
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
								exprs.push(macro hxbit.Macros.unserializeValue($ctx, $i{name}, $v{depth+1}, $v{conds.toInt()}));
							} else {
								exprs.unshift(macro var $name : $ct = null);
								exprs.push(macro if( fbits & $v { 1 << nidx } != 0 ) hxbit.Macros.unserializeValue($ctx, $i{name}, $v{depth+1}, $v{conds.toInt()}));
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
				$v = $ctx.getArray(function() { hxbit.Macros.unserializeValue($ctx, $i{ename}, $v{depth+1}, $v{conds.toInt()}); return $i{ename}; });
			};
		case PVector(at):
			var at = toProxy(at);
			var ve = { expr : EConst(CIdent("e")), pos : v.pos };
			var ename = "e" + depth;
			return macro {
				var $ename : $at;
				$v = $ctx.getVector(function() { hxbit.Macros.unserializeValue($ctx, $i{ename}, $v{depth+1}, $v{conds.toInt()}); return $i{ename}; });
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
		case PAlias(at), PAliasCDB(at):
			var cvt = at.t;
			var vname = "v" + depth;
			return macro {
				var $vname : $cvt;
				${unserializeExpr(ctx,macro $i{vname},at,depth+1,conds)};
				$v = cast $i{vname};
			};
		case PNoSave(at):
			return macro if( !$ctx.forSave ) ${unserializeExpr(ctx, v, at, depth, conds)};
		case PNull(t):
			var e = unserializeExpr(ctx, v, t, depth, conds);
			return macro if( $ctx.getByte() == 0 ) $v = null else $e;
		case PDynamic:
			return macro $v = $ctx.getDynamic();
		case PFlags(_):
			return macro {
				var v : Int;
				${unserializeExpr(ctx,macro v,{ t : macro : Int, d : PInt },depth + 1, conds)};
				$v = ${t.isProxy ? macro new hxbit.EnumFlagsProxy(v) : macro new haxe.EnumFlags(v)};
			};
		case PCustom:
			return macro $v = $ctx.getCustom();
		case PStruct(name,_):
			var cexpr = Context.parse(t.t.toString(), v.pos);
			return macro {
				if( $ctx.getByte() == 0 )
					$v = null;
				else {
					@:privateAccess $ctx.inPos--;
					var tmp = Type.createEmptyInstance($cexpr);
					tmp.unserialize($ctx);
					$v = tmp;
				}
			}
		case PUnknown:
			throw "assert";
		}
	}

	static function withPos( e : Expr, p : Position ) {
		e.pos = p;
		haxe.macro.ExprTools.iter(e, function(e) withPos(e, p));
		return e;
	}

	static function markExpr( expr, type, pos ) {
		return makeRecExpr(expr, type, pos, function(expr, t) {
			switch( t.d ) {
			case PDynamic:
				return macro @:privateAccess hxbit.Serializer.markReferencesDyn($expr, mark, from);
			case PEnum(_):
				return makeEnumCall(t,"markReferences",[macro cast $expr,macro mark, macro from]);
			default:
				return macro $expr.markReferences(mark,from);
			}
		});
	}

	static function clearExpr( expr : Expr, t : PropType, pos : Position, fset : Expr -> Expr ) {
		switch( t.d ) {
		case PInt, PFloat, PBool, PString, PBytes, PInt64, PFlags(_), PUnknown, PAliasCDB(_):
			return null;
		case PSerializable(_), PSerInterface(_):
			return macro if( $expr != null ) {
				if( ($expr.__mark & mark.clear) != 0 )
					${fset(macro null)}
				else
					$expr.clearReferences(mark);
			}
		case PStruct(_), PCustom:
			return macro if( $expr != null ) $expr.clearReferences(mark);
		case PMap(k,v):
			var ek = clearExpr(macro __key, k, pos, (_) -> macro { __map.remove(__key); continue; });
			var ev = clearExpr(macro __val, v, pos, (e) -> e.expr.match(EConst(CIdent("null"))) ? macro { __map.remove(__key); continue; } : macro { __map.set(__key,$e); continue; } );
			if( ek == null && ev == null )
				return null;
			var b = [];
			if( ek != null ) b.push(ek);
			if( ev != null ) b.push(ev);
			return macro { var __map = $expr; if( __map != null ) { for( __key => __val in __map ) $b{b}; } };
		case PArray(v), PVector(v):
			var ev = clearExpr(macro __val, v, pos, (e) -> macro __arr[i] = $e);
			return ev == null ? null : macro { var __arr = $expr; if( __arr != null ) { for( i => __val in __arr ) $ev; } };
		case PObj(fields):
			var out = [];
			for( f in fields ) {
				var name = f.name;
				var ev = clearExpr(macro __obj.$name, f.type, pos, (e) -> macro @:pos(pos) __obj.$name = $e);
				if( ev != null )
					out.push(ev);
			}
			return out.length == 0 ? null : macro { var __obj = $expr; if( __obj != null ) $b{out}; }
		case PEnum(_):
			return macro { var _e = ${makeEnumCall(t,"clearReferences",[macro cast $expr, macro mark])}; if( _e != $expr ) ${fset(macro _e)}; };
		case PDynamic:
			return macro { var _e = @:privateAccess hxbit.Serializer.clearReferencesDyn($expr,mark); if( _e != $expr ) ${fset(macro _e)}; };
		case PAlias(t), PNull(t), PNoSave(t):
			return clearExpr(expr, t, pos, fset);
		}
	}

	static function patchField( fields : Array<Field>, code : Expr, fieldName : String, ?isNetwork : Bool ) {
		code.expr = EMeta({ name : isNetwork ? ":networkSerializableGen" : ":serializableGen", params : [], pos : code.pos }, { expr : code.expr, pos : code.pos });
		for( f in fields ) {
			if( f.name != fieldName )
				continue;
			var injectPoint = null;
			var cancelInject = false;
			function iterRec(e:Expr) {
				switch( e.expr ) {
				case ECall({ expr : EField({ expr : EConst(CIdent("super")) },fff) },_) if( fff == fieldName ):
					injectPoint = e;
				case EMeta({ name : ":networkSerializableGen" },_):
					cancelInject = true;
				case EMeta({ name : ":serializableGen" },_):
					injectPoint = e;
				default:
					haxe.macro.ExprTools.iter(e, iterRec);
				}
			}
			switch( f.kind ) {
			case FFun(f):
				iterRec(f.expr);
			default: throw "assert";
			}
			if( cancelInject )
				return true;
			if( injectPoint == null )
				Context.error("Missing super() call", f.pos);
			else
				injectPoint.expr = code.expr;
			return true;
		}
		return false;
	}

	public static function buildSerializable(isStruct=false) {
		var cl = Context.getLocalClass().get();
		if( cl.isInterface || cl.meta.has(":skipSerialize") )
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

			var isPrio = false, isSer = null;
			for( meta in f.meta ) {
				switch( meta.name ) {
				case ":s": isSer = meta;
				case ":serializePriority": isPrio = true;
				}
			}
			if( isSer != null ) {
				if( isPrio ) serializePriority = f;
				toSerialize.push({ f : f, m : isSer, meta : f.meta });
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
			if( f.access != null && f.access.indexOf(AStatic) >= 0 ) continue;
			switch( f.kind ) {
			case FVar(_, e), FProp(_, _, _, e) if( e != null ):
				if (f.access != null && f.access.contains(AFinal))
					Context.error("Serializables may not have member final variables", f.pos);
				// before unserializing
				fieldsInits.push({ expr : EBinop(OpAssign,{ expr : EConst(CIdent(f.name)), pos : e.pos },e), pos : e.pos });
			default:
			}
		}

		var pos = Context.currentPos();
		// todo : generate proper generic static var ?
		// this is required for fixing conflicting member var / package name
		var useStaticSer = cl.params.length == 0 && !isStruct;
		var el = [], ul = [], serializePriorityFuns = null;

		if( isStruct ) {
			ul.push(macro var __bits = __ctx.getInt());
			ul.push(macro __bits--);
			el.push(macro var __bits = 0);
			var bit = 0, elAfter = [];
			var conds = new haxe.EnumFlags<Condition>();
			conds.set(PreventCDB);
			conds.set(PartialResolution);
			for( s in toSerialize ) {
				var f = s.f;
				var fname = f.name;
				var vt = switch( f.kind ) {
				case FVar(t,_), FProp(_,_,t): t;
				default: null;
				}
				if( vt == null ) Context.error("Type required", pos);
				var tt = Context.resolveType(vt, pos);
				var ftype = getPropField(tt, f.meta, conds);
				if( ftype == null )
					Context.error("Unsupported serializable type "+tt.toString(), pos);

				var sexpr = macro @:pos(pos) hxbit.Macros.serializeValue(__ctx,this.$fname);
				var uexpr = macro @:pos(pos) hxbit.Macros.unserializeValue(__ctx,this.$fname);
				if( isNullable(ftype) ) {
					var b = bit++;
					if( b == 31 ) Context.error("Too many nullable fields", pos);
					el.push(macro @:pos(pos) if( this.$fname == null ) __bits |= 1 << $v{b});
					sexpr = macro @:pos(pos) if( this.$fname != null ) $sexpr;
					uexpr = macro @:pos(pos) if( __bits & (1 << $v{b}) == 0 ) $uexpr;
				}
				if( ftype.d.match(PNoSave(_)) ) {
					sexpr = macro @:pos(pos) if( !ctx.forSave ) $sexpr;
					uexpr = macro @:pos(pos) if( !ctx.forSave ) $uexpr;
				}
				elAfter.push(sexpr);
				ul.push(uexpr);
			}
			el.push(macro __ctx.addInt(__bits + 1));
			el = el.concat(elAfter);
		} else {
			for( f in toSerialize ) {
				var fname = f.f.name;
				var ef = useStaticSer && f.f != serializePriority ? macro __this.$fname : macro this.$fname;
				var pos = f.f.pos;
				var sexpr = macro @:pos(pos) hxbit.Macros.serializeValue(__ctx,$ef);
				var uexpr = macro @:pos(pos) hxbit.Macros.unserializeValue(__ctx, $ef);
				var vis = null, noSave = false;
				for( m in f.meta ) {
					switch( m.name ) {
					case ":visible":
						vis = getVisibility(m);
					case ":noSave":
						noSave = true;
					}
				}
				if( vis != null ) {
					sexpr = macro if( @:privateAccess __ctx.visibilityGroups & (1<<$v{vis}) != 0 ) $sexpr;
					uexpr = macro if( @:privateAccess __ctx.visibilityGroups & (1<<$v{vis}) != 0 ) $uexpr else $ef = cast null;
				}
				if( noSave ) {
					sexpr = macro if( !__ctx.forSave ) $sexpr;
					uexpr = macro if( !__ctx.forSave ) $uexpr;
				}
				if( f.f == serializePriority ) {
					if( serializePriorityFuns != null ) throw "assert";
					serializePriorityFuns = { ser : sexpr, unser : uexpr };
				} else {
					el.push(sexpr);
					ul.push(uexpr);
				}
			}
		}

		var noCompletion = [{ name : ":noCompletion", pos : pos }];
		var access = [APublic];
		if( isStruct ) {
			if( isSubSer )
				Context.error("StructSerializable cannot extend Serializable", pos);
			cl.meta.add(":final",[], pos);
			var isProxy = cl.meta.has(":isProxy");
			if( !isProxy && cl.superClass != null && cl.superClass.t.get().meta.has(":isProxy") ) {
				isProxy = true;
				cl.meta.add(":isProxy",[], pos);
			}
			if( isProxy ) {
				for( s in toSerialize ) {
					switch( s.f.kind ) {
					case FProp(_):
						Context.error("Property not allowed on proxy StructSerializable", s.f.pos);
					case FVar(t,e):
						s.f.kind = FProp("default","set", t, e);
						var fname = s.f.name;
						fields.push({
							name : "set_"+fname,
							access : [AInline],
							pos : s.f.pos,
							kind : FFun({
								args : [{ name : "v", type : t }],
								expr : macro { this.$fname = v; mark(); return v; }
							})
						});
					default:
					}
				}
			}
		} else if( isSubSer )
			access.push(AOverride);
		else {
			fields.push({
				name : "__uid",
				pos : pos,
				access : [APublic],
				meta : noCompletion,
				kind : FVar(macro : hxbit.UID, macro @:privateAccess hxbit.Serializer.allocUID()),
			});
			#if (hxbit_visibility || hxbit_mark || hxbit_clear)
			fields.push({
				name : "__mark",
				pos : pos,
				access : [APublic],
				meta : noCompletion,
				kind : FVar(macro : Int),
			});
			#end
		}

		var clName = StringTools.endsWith(cl.module,"."+cl.name) ? cl.module.split(".") : [cl.name];
		if( !isStruct ) {
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
		}

		var needSerialize = toSerialize.length != 0 || !isSubSer || addCustomSerializable;
		var needUnserialize = needSerialize || fieldsInits.length != 0 || addCustomUnserializable;

		if( needSerialize ) {
			var serExpr = macro @:privateAccess {
				${ if( serializePriorityFuns != null ) serializePriorityFuns.ser else macro { } };
				${ if( isSubSer ) macro super.serialize(__ctx) else macro { } };
				${ if( useStaticSer ) macro doSerialize(__ctx,this) else macro $b{el} };
				${ if( addCustomSerializable ) macro this.customSerialize(__ctx) else macro { } };
			};
			var serFound = false;
			for( f in fields )
				if( f.name == "serialize" ) {
					var found = false;
					function repl(e:Expr) {
						switch( e.expr ) {
						case ECall( { expr : EField( { expr : EConst(CIdent("super")) }, "serialize") }, [ctx]):
							found = true;
							return macro { var __ctx : hxbit.Serializer = $ctx; $serExpr; }
						default:
							return haxe.macro.ExprTools.map(e, repl);
						}
					}
					switch( f.kind ) {
					case FFun(f):
						f.expr = repl(f.expr);
					default:
					}
					if( !found ) Context.error("Override of serialize() with no super.serialize(ctx) found", f.pos);
					serFound = true;
					break;
				}

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
			if( !serFound ) fields.push({
				name : "serialize",
				pos : pos,
				access : access,
				kind : FFun({
					args : [ { name : "__ctx", type : macro : hxbit.Serializer } ],
					ret : null,
					expr : serExpr,
				}),
			});
			var schema = [];
			for( s in toSerialize ) {
				var name = s.f.name;
				var acall = s.f == serializePriority ? "unshift" : "push";
				var e = macro { schema.fieldsNames.$acall($v{name}); schema.fieldsTypes.$acall(hxbit.Macros.getFieldType(this.$name)); };
				for( m in s.meta ) {
					switch( m.name ) {
					case ":noSave":
						e = macro if (!forSave) $e{e};
					}
				}
				schema.push(e);
			}
			fields.push({
				name : "getSerializeSchema",
				pos : pos,
				access : access,
				meta : noCompletion,
				kind : FFun({
					args : [{ name : "forSave", type : macro : Bool, value : macro true }],
					ret : null,
					expr : macro {
						var schema = ${if( isSubSer ) macro super.getSerializeSchema(forSave) else macro new hxbit.Schema()};
						$b{schema};
						schema.isFinal = ${isStruct ? macro true : macro hxbit.Serializer.isClassFinal(__clid)};
						return schema;
					}
				})
			});
			#if (hxbit_visibility || hxbit_mark)
			var markExprs = [];
			if( !isStruct ) {
				markExprs.push(macro if( (__mark&mark.set) == mark.set ) return);
				if( isSubSer )
					markExprs.push(macro super.markReferences(mark, from));
				else
					markExprs.push(macro __mark = (__mark & mark.mask) | mark.set);
			}
			for( s in toSerialize ) {
				var name = s.f.name;
				markExprs.push(macro @:pos(s.f.pos) hxbit.Macros.markValue(this.$name));
			}
			var code = { expr : EBlock(markExprs), pos : pos };
			if( !patchField(fields,code,"markReferences") ) {
				fields.push({
					name : "markReferences",
					pos : pos,
					access : access,
					kind : FFun({
						args : [{ name : "mark", type : macro : hxbit.Serializable.MarkInfo },{ name : "from", type : macro : hxbit.NetworkSerializable }],
						expr : code,
					}),
				});
			}
			#end
			#if hxbit_clear
			var clearExprs = [];
			if( !isStruct ) {
				clearExprs.push(macro if( (__mark&mark.set) == mark.set ) return);
				if( isSubSer )
					clearExprs.push(macro super.clearReferences(mark));
				else
					clearExprs.push(macro __mark = (__mark&mark.mask) | mark.set);
			}
			for( s in toSerialize ) {
				var name = s.f.name;
				clearExprs.push(macro @:pos(s.f.pos) hxbit.Macros.clearValue(this.$name));
			}
			var code = { expr : EBlock(clearExprs), pos : pos };
			if( !patchField(fields,code,"clearReferences") ) {
				fields.push({
					name : "clearReferences",
					pos : pos,
					access : access,
					kind : FFun({
						args : [{ name : "mark", type : macro : hxbit.Serializable.MarkInfo }],
						expr : code,
					}),
				});
			}
			#end
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
				var conds = new haxe.EnumFlags<Condition>();
				conds.set(PreventCDB);
				if( e.meta.has(":allowCDB") || e.meta.has(":cdb") )
					conds.unset(PreventCDB);
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
							evals.push(macro @:pos(e.pos) hxbit.Macros.unserializeValue(ctx,$i{aname},0,$v{conds.toInt()}));
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
						access : [AInline, APublic, AExtern],
						meta : [],
						pos : pos,
						kind : FFun( {
							args : [{ name : "ctx", type : macro : hxbit.Serializer },{ name : "v", type : pt.toComplexType() }],
							expr : macro { @:privateAccess ctx.usedEnums[$v{pathName}] = true; doSerialize(ctx,v); },
							ret : null,
						}),
					},{
						name : "unserialize",
						access : [AInline, APublic, AExtern],
						meta : [],
						pos : pos,
						kind : FFun( {
							args : [{ name : "ctx", type : macro : hxbit.Serializer }],
							expr : macro return doUnserialize(ctx),
							ret : null,
						}),
					},
					#if (hxbit_visibility || hxbit_mark)
					{
						name : "markReferences",
						access : [AInline, APublic, AExtern],
						meta : [],
						pos : pos,
						kind : FFun( {
							args : [{ name : "value", type : pt.toComplexType() },{ name : "mark", type : macro : hxbit.Serializable.MarkInfo },{ name : "from", type : macro : hxbit.NetworkSerializable }],
							expr : macro doMarkReferences(value, mark, from),
							ret : null,
						}),
					}, {
						name : "doMarkReferences",
						access : [AStatic],
						pos : pos,
						kind : FFun({
							args : [{ name : "value", type : pt.toComplexType() },{ name : "mark", type : macro : hxbit.Serializable.MarkInfo },{ name : "from", type : macro : hxbit.NetworkSerializable }],
							expr : {
								var cases = [];
								var conds = new haxe.EnumFlags<Condition>();
								for( c in e.constructs ) {
									switch( c.type ) {
									case TFun(args,_):
										var marks = [], eargs = [];
										for( a in args ) {
											var arg = macro $i{a.name};
											marks.push(macro hxbit.Macros.markValue($arg));
											eargs.push(arg);
										}
										if( marks.length > 0 )
											cases.push({ values : [macro $i{c.name}($a{eargs})], expr : macro {$b{marks}} });
									default:
									}
								}
								var swexpr = { expr : ESwitch(macro value,cases,macro null), pos : pos };
								if( cases.length == 0 ) macro {} else macro if( value != null ) $swexpr;
							}
						})
					},
					#end
					#if hxbit_clear
					{
						name : "clearReferences",
						access : [AInline, APublic,AExtern],
						meta : [],
						pos : pos,
						kind : FFun( {
							args : [{ name : "value", type : pt.toComplexType() },{ name : "mark", type : macro : hxbit.Serializable.MarkInfo }],
							expr : macro return doClearReferences(value, mark),
							ret : pt.toComplexType(),
						}),
					}, {
						name : "doClearReferences",
						access : [AStatic],
						pos : pos,
						kind : FFun({
							args : [{ name : "__value", type : pt.toComplexType() },{ name : "mark", type : macro : hxbit.Serializable.MarkInfo }],
							ret : pt.toComplexType(),
							expr : {
								var cases = [];
								var conds = new haxe.EnumFlags<Condition>();
								for( c in e.constructs ) {
									switch( c.type ) {
									case TFun(args,_):
										var marks = [], eargs = [];
										for( a in args ) {
											var arg = macro $i{a.name};
											marks.push(macro hxbit.Macros.clearValue($arg,true));
											eargs.push(arg);
										}
										if( marks.length > 0 ) {
											marks.unshift(macro var __changed = false);
											marks.push(macro __changed ? $i{c.name}($a{eargs}): __value);
											cases.push({ values : [macro $i{c.name}($a{eargs})], expr : macro {$b{marks}} });
										}
									default:
									}
								}
								var swexpr = { expr : ESwitch(macro __value,cases,macro __value), pos : pos };
								if( cases.length == 0 )
									macro return __value;
								else
									macro return __value == null ? null : $swexpr;
							}
						})
					},
					#end
					],
					pos : pos,
				};
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
		case PNull(st), PAlias(st):
			return !t.notMutable && needProxy(st);
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
		case ECall({ expr : EConst(CIdent("__return")) },[v]):
			e.expr = (macro { __return($v); return; }).expr;
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
		if( cl.isInterface )
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

		var requiredSetters = new Map(), setterCount = 0;

		for( f in fields ) {

			if( superRPC.exists(f.name) ) {
				switch( f.kind ) {
				case FFun(ff):
					ff.expr = superImpl(f.name, ff.expr);
					if( hasReturnVal(ff.expr).call ) {
						replaceReturns(ff.expr);
						ff.ret = macro : Void;
						ff.args.push({ name : "__return" });
					}
				default:
				}
				f.name += "__impl";
				continue;
			}

			if( StringTools.startsWith(f.name, "set_") && requiredSetters.remove(f.name.substr(4)) )
				setterCount--;

			if( f.access != null && f.access.indexOf(AOverride) >= 0 && StringTools.startsWith(f.name, "set_") && superFields.exists(f.name.substr(4)) ) {
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
					if( f.kind != null )
						switch( f.kind ) {
						case FProp(_, "set",_,_):
							requiredSetters.set(f.name, f.pos);
							setterCount++;
						default:
						}
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

		if( setterCount > 0 ) {
			for( f in fields )
				if( f.name.substr(0,4) == "set_" )
					requiredSetters.remove(f.name.substr(4));
			for( name in requiredSetters.keys() )
				Context.warning("Method set_"+name+" required by property "+name+" is missing", requiredSetters.get(name));
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
		var condMarkCases: Array<Case> = [];
		var noComplete : Metadata = [ { name : ":noCompletion", pos : pos } ];
		var saveMask : haxe.Int64 = 0;
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
			var conds = new haxe.EnumFlags<Condition>();
			conds.set(PreventCDB);
			conds.set(PartialResolution);
			var ftype = getPropField(tt, f.f.meta, conds);
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
			var baseMarkExpr = macro networkSetBit($v{ bitID });
			var markExpr = makeMarkExpr(fields, fname, ftype, baseMarkExpr);
			var condMarkExpr = makeMarkExpr(fields, fname, ftype, baseMarkExpr, false);

			var compExpr : Expr = macro this.$fname != v;
			if(ftype.d.match(PEnum(_)))
				compExpr = macro !Type.enumEq(this.$fname, v);

			switch( ftype.d ) {
			case PNoSave(_): saveMask |= (1:haxe.Int64) << bitID;
			default:
			}

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
			condMarkCases.push({
				values : [macro $v{bitID}],
				expr : condMarkExpr,
			});
		}

		if( toSerialize.length != 0 || !isSubSer ) {
			var access = [APublic];
			if( isSubSer )
				access.push(AOverride);
			var defaultCase = macro networkSetBit(b);
			if( isSubSer )
				defaultCase = macro super.networkSetBitCond(b);
			var swExpr = { expr : ESwitch( { expr : EConst(CIdent("b")), pos : pos }, condMarkCases, defaultCase), pos : pos };
			fields.push({
				name : "networkSetBitCond",
				pos : pos,
				access : access,
				meta : noComplete,
				kind : FFun({
					args : [ { name : "b", type : macro : Int } ],
					ret : macro : Void,
					expr : swExpr,
				}),
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

				var conds = new haxe.EnumFlags<Condition>();
				conds.set(PreventCDB);
				var visibility : Null<Int> = null;
				for( m in r.f.meta ) {
					if( m.name == ":allowCDB" )
						conds.unset(PreventCDB);
					if( m.name == ":visible" )
						visibility = getVisibility(m);
				}

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
						hxbit.Macros.unserializeValue(__ctx, _v, 0, $v{conds});
						if( __ctx.error ) return false;
						if( onResult != null ) onResult(_v);
						return true;
					},f.expr.pos);
					rpcArgs = rpcArgs.copy();
					rpcArgs.push( { name : "onResult", opt: true, type: retType == null ? null : TFunction([retType], macro:Void) } );
				}

				var forwardRPC = macro {
					@:privateAccess __host.doRPC(this,$v{id}, $v{visibility}, $resultCall, function(__ctx) {
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
					access : r.f.access.concat([AFinal]),
					kind : FFun({
						args : rpcArgs,
						ret : macro : Void,
						expr : rpcExpr,
					}),
					pos : p,
				};
				fields.push(rpc);

				r.f.access.remove(APublic);
				r.f.meta.push( { name : ":noCompletion", pos : p } );

				var exprs = [ { expr : EVars([for( a in funArgs ) { name : a.name, type : a.opt && a.type != null ? TPath({ pack : [], name : "Null", params : [TPType(a.type)] }) : a.type, expr : macro cast null } ]), pos : p } ];
				if( returnVal.call ) {
					exprs.push(macro var __v = cast null);
					exprs.push(macro if( false ) { function onResult(v) __v = v; $fcall; }); // force typing
				} else
					exprs.push(macro if( false ) $fcall); // force typing
				for( a in funArgs ) {
					var e = macro hxbit.Macros.unserializeValue(__ctx, $i{ a.name }, 0, $v{conds.toInt()});
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
			#end

			#if (hxbit_visibility || hxbit_mark)
			var markExprs = [];
			markExprs.push(macro if( (__mark&mark.set) == mark.set ) return);
			if( isSubSer )
				markExprs.push(macro super.markReferences(mark,from));
			else
				markExprs.push(macro __mark = (__mark & mark.mask) | mark.set);

			for( f in toSerialize ) {
				#if hxbit_visibility
				if( f.visibility != null ) continue;
				#end
				var fname = f.f.name;
				var expr = markExpr(macro this.$fname, f.type, f.f.pos);
				if( expr != null ) markExprs.push(expr);
			}

			#if hxbit_visibility
				var gexprs = [], eexprs = [];
				if( groups.keys().hasNext() ) {
					gexprs.push(macro var groups : Int = __cachedVisibility == null ? 0 : __cachedVisibility.get(from));
				}
				for( gid => info in groups ) {
					gexprs.push(macro if( groups & $v{1<<gid} != 0 ) $b{[for( f in info.fl ) {
						var fname = f.f.name;
						var expr = markExpr(macro this.$fname, f.type, f.f.pos);
						if( expr != null ) {
							eexprs.push(expr);
							expr;
						}
					}]});
				}
				markExprs.push(macro if( from == null ) $b{eexprs} else $b{gexprs});
			#end

			var code = { expr : EBlock(markExprs), pos : pos };
			if( !patchField(fields, code, "markReferences", true) ) {
				fields.push({
					name : "markReferences",
					pos : pos,
					access : access,
					meta : noComplete,
					kind : FFun({
						args : [
							{ name : "mark", type : macro : hxbit.Serializable.MarkInfo },
							{ name : "from", type : macro : hxbit.NetworkSerializable },
						],
						ret : null,
						expr : code,
					}),
				});
			}
			#end


			if( !isSubSer || saveMask != 0 ) {
				fields.push({
					name : "getNoSaveMask",
					pos : pos,
					access : access,
					meta : noComplete,
					kind : FFun({
						args : [],
						ret : macro : haxe.Int64,
						expr : macro {
							var mask = haxe.Int64.make($v{saveMask.high}, $v{saveMask.low});
							${if( isSubSer ) macro mask |= super.getNoSaveMask() else macro null};
							return mask;
						}
					}),
				});
			}
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
				cases.push( { id : i + firstFID, name : toSerialize[i].f.name, field: toSerialize[i].f } );
			for( i in 0...rpc.length )
				cases.push( { id : i + startFID + firstRPCID, name : rpc[i].f.name.substr(0,-6), field: rpc[i].f } );

			function networkGetter(name: String, ret: ComplexType, func : {id: Int, name: String, field: Field} -> Dynamic) {
				var ecases = [for( c in cases ) { values : [ { expr : EConst(CInt("" + c.id)), pos : pos } ], expr : macro $v{func(c)}, guard : null } ];
				var swExpr = { expr : EReturn( { expr : ESwitch(macro isRPC ? id + $v { startFID } : id, ecases, macro $v{func(null)}), pos : pos } ), pos : pos };
				fields.push( {
					name : name,
					pos : pos,
					access : access,
					meta : noComplete,
					kind : FFun({
						args : [ { name : "id", type : macro : Int }, { name : "isRPC", type : macro : Bool, value:macro false } ],
						ret : ret,
						expr : if( isSubSer ) macro { if( id < (isRPC ? $v{ firstRPCID } : $v{ firstFID }) ) return super.$name(id, isRPC); $swExpr; } else swExpr,
					}),
				});
			}

			networkGetter("networkGetName", macro: String, function(c) {
				if(c == null) return null;
				return c.name;
			});
			for(getter in CUSTOM_GETTERS)
				networkGetter(getter.name, getter.ret, getter.func);
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

	static function makeRecExpr( expr : Expr, t : PropType, pos : Position, mk : Expr -> PropType -> Expr ) {
		switch( t.d ) {
		case PInt, PFloat, PBool, PString, PBytes, PInt64, PFlags(_), PUnknown, PAliasCDB(_):
		case PSerializable(_), PSerInterface(_), PStruct(_), PDynamic, PEnum(_), PCustom:
			return macro if( $expr != null ) ${mk(expr,t)};
		case PMap(k,v):
			var ek = makeRecExpr(macro __key, k, pos, mk);
			var ev = makeRecExpr(macro __val, v, pos, mk);
			if( ek == null && ev == null )
				return null;
			if( ek != null && ev != null )
				return macro if( $expr != null ) { for( __key => __val in $expr ) { $ek; $ev; } };
			if( ek != null )
				return macro if( $expr != null ) { for( __key in $expr.keys() ) $ek; };
			return macro if( $expr != null ) { for( __val in $expr ) $ev; };
		case PArray(v), PVector(v):
			var ev = makeRecExpr(macro __val, v, pos, mk);
			return ev == null ? null : macro if( $expr != null ) { for( __val in $expr ) $ev; };
		case PObj(fields):
			var out = [];
			for( f in fields ) {
				var name = f.name;
				var ev = makeRecExpr(macro $expr.$name, f.type, pos, mk);
				if( ev != null ) out.push(ev);
			}
			return out.length == 0 ? null : macro if( $expr != null ) $b{out};
		case PAlias(t), PNull(t), PNoSave(t):
			return makeRecExpr(expr, t, pos, mk);
		}
		return null;
	}

	static function makeMarkExpr( fields : Array<Field>, fname : String, t : PropType, mark : Expr, forSetter=true ) {
		var rname = "__ref_" + fname;
		var needRef = false;
		if( t.increment != null && forSetter ) {
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
		var str = _typeName(t);
		if( str.length > 50 )
			str = haxe.crypto.Md5.encode(str);
		return str;
	}

	static function _typeName(t:PropType) {
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

				var hasProxy = false;
				for( f in fields ) {
					checkProxy(f.type);
					if( f.type.isProxy )
						hasProxy = true;
				}
				var optMeta : Metadata = [{ name : ":optional", pos : pos, params : [] }];
				var loadT = haxe.macro.Expr.ComplexType.TAnonymous([for( f in fields ) { name : f.name, pos : pos, kind : FVar(f.type.t), meta : f.opt ? optMeta : null }]);
				if( hasProxy )
					pt = loadT;

				var myT = TPath( { pack : ["hxbit"], name : name } );
				var tfields = (macro class {
					var obj : hxbit.NetworkSerializable.ProxyHost;
					var bit : Int;
					@:noCompletion public var __value(get, never) : $pt;
					inline function get___value() : $pt return cast this;
					public inline function mark() if( obj != null ) obj.networkSetBitCond(bit);
					@:noCompletion public inline function networkSetBitCond(_) mark();
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

					var expr;
					if( f.type.isProxy ) {
						expr = macro { $markExpr; if( this.$fname != null ) this.$fname.unbindHost(); this.$fname = v; if( v != null ) v.bindHost(this,0); return v; }
					} else {
						expr = macro { $markExpr; this.$fname = v; return v; }
					}

					tfields.push( {
						name : "set_" + f.name,
						pos : pos,
						access : [AInline],
						kind : FFun({
							ret : ft,
							args : [ { name : "v", type : ft } ],
							expr : expr,
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
				tfields.push({
					name : "__load",
					pos : pos,
					access : [APublic],
					kind : FFun({
						ret : null,
						args : [{ name : "v", type : loadT }],
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
		case PAlias(t):
			return buildProxyType(t);
		case PNull(t):
			return TPath({ pack : [], name : "Null", params : [TPType(buildProxyType(t))] });
		default:
		}
		return null;
	}

	static function buildReadOnlyType( p : PropType ) : ComplexType {
		switch( p.d ) {
		case PMap(k,v):
			var k = buildReadOnlyType(k);
			var v = buildReadOnlyType(v);
			return macro : hxbit.ReadOnly.ReadOnlyMap<$k,$v>;
		case PArray(v):
			var v = buildReadOnlyType(v);
			return macro : hxbit.ReadOnly.ReadOnlyArray<$v>;
		case PVector(v):
			var v = buildReadOnlyType(v);
			return macro : hxbit.ReadOnly.ReadOnlyVector<$v>;
		case PNull(t):
			var t = buildReadOnlyType(t);
			return macro : Null<$t>;
		case PAlias(t):
			if( !needProxy(t) )
				return p.t;
			return buildReadOnlyType(t);
		case PObj(fields):
			// define type
			var name = "ReadOnly_";
			name += typeName(p);
			try {
				return Context.getType("hxbit." + name).toComplexType();
			} catch( e : Dynamic ) {
				var pos = Context.currentPos();
				var tfields : Array<Field> = [];
				for( f in fields ) {
					var ro = buildReadOnlyType(f.type);
					var fname = f.name;
					tfields.push({
						pos : pos,
						name : f.name,
						access : [APublic],
						kind : FProp("get","never", ro),
					});
					tfields.push({
						pos : pos,
						name : "get_"+f.name,
						access : [AInline],
						kind : FFun({
							args : [],
							ret : ro,
							expr : macro return this.$fname,
						}),
					});
				}
				tfields.push({
					pos : pos,
					name : "__value",
					access : [APublic],
					kind : FProp("get","never", p.t),
				});
				tfields.push({
					pos : pos,
					name : "get___value",
					access : [AInline],
					kind : FFun({
						args : [],
						expr : macro return this,
					}),
				});
				var t : TypeDefinition = {
					pos : pos,
					pack : ["hxbit"],
					name : name,
					kind : TDAbstract(p.t,[p.t]),
					fields : tfields,
				};
				Context.defineType(t);
				return TPath({ pack : ["hxbit"], name : name });
			}
		default:
			return p.t;
		}
	}

	public static function buildSerializableProxy() {
		var t = Context.getLocalType();
		switch( t ) {
		case TInst(_, [pt]):
			var conds = new haxe.EnumFlags();
			var p = getPropType(pt, conds);
			if( p != null ) {
				var t = buildProxyType(p);
				if( t != null ) return toType(t);
			}
			throw "TODO "+pt+" ("+p+")";
		default:
			throw "assert";
		}
	}

	public static function buildReadOnly() {
		var t = Context.getLocalType();
		switch( t ) {
		case TInst(_, [pt]):
			var conds = new haxe.EnumFlags<Condition>();
			conds.set(PreventCDB);
			var p = getPropType(pt, conds);
			if( p != null ) {
				var t = buildReadOnlyType(p);
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
