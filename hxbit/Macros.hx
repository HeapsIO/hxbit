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
		Like `All`, but executes immediately locally
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
}

typedef PropType = {
	var d : PropTypeDesc<PropType>;
	var t : ComplexType;
	@:optional var isProxy : Bool;
	@:optional var increment : Float;
	@:optional var condSend : Expr;
	@:optional var notMutable : Bool;
}

class Macros {

	static var IN_ENUM_SER = false;

	public static macro function serializeValue( ctx : Expr, v : Expr ) : Expr {
		var t = Context.typeof(v);
		var pt = getPropType(t);
		if( pt == null ) {
			Context.error("Unsupported serializable type " + t.toString(), v.pos);
			return macro { };
		}
		IN_ENUM_SER = StringTools.startsWith(Context.getLocalClass().toString(), "hxbit.enumSer.");
		return withPos(serializeExpr(ctx, v, pt),v.pos);
	}

	public static macro function unserializeValue( ctx : Expr, v : Expr, depth : Int = 0 ) : Expr {
		var t = Context.typeof(v);
		var pt = getPropType(t);
		if( pt == null ) {
			return macro { };
		}
		IN_ENUM_SER = StringTools.startsWith(Context.getLocalClass().toString(), "hxbit.enumSer.");
		return withPos(unserializeExpr(ctx, v, pt, depth),v.pos);
	}

	public static macro function getFieldType( v : Expr ) {
		var t = Context.typeof(v);
		var pt = getPropType(t);
		if( pt == null )
			return macro null;
		var v = toFieldType(pt);
		return macro $v{v};
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
		return lookupInterface(c, "hxbit.Serializable");
	}

	static function isStructSerializable( c : Ref<ClassType> ) {
		return lookupInterface(c, "hxbit.StructSerializable");
	}

	static function getPropField( ft : Type, meta : Metadata ) {
		var t = getPropType(ft);
		if( t == null )
			return null;
		for( m in meta) {
			switch( m.name ) {
			case ":s", ":optional":
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
			default:
				Context.error("Unsupported network metadata", m.pos);
			}
		}
		return t;
	}

	static function getPropType( t : haxe.macro.Type ) : PropType {
		var isProxy = false;
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
				var tk = getPropType(pl[0]);
				var tv = getPropType(pl[1]);
				if( tk == null || tv == null )
					return null;
				PMap(tk, tv);
			case "haxe.ds.Vector":
				var tk = getPropType(pl[0]);
				if( tk == null )
					return null;
				PVector(tk);
			case "hxbit.VectorProxy":
				var t = getPropType(pl[0]);
				if( t == null )
					return null;
				isProxy = true;
				PVector(t);
			case "hxbit.ArrayProxy", "hxbit.ArrayProxy2":
				var t = getPropType(pl[0]);
				if( t == null )
					return null;
				isProxy = true;
				PArray(t);
			case "hxbit.MapProxy", "hxbit.MapProxy2":
				var k = getPropType(pl[0]);
				var v = getPropType(pl[1]);
				if( k == null || v == null ) return null;
				isProxy = true;
				PMap(k, v);
			case "hxbit.EnumFlagsProxy":
				var e = getPropType(pl[0]);
				if( e == null ) return null;
				isProxy = true;
				PFlags(e);
			case "haxe.EnumFlags":
				var e = getPropType(pl[0]);
				if( e == null ) return null;
				PFlags(e);
			case "Null":
				var p = getPropType(pl[0]);
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
				var pt = getPropType(t2);
				if( pt == null ) return null;
				PAlias(pt);
			}
		case TEnum(e,_):
			PEnum(e.toString());
		case TDynamic(_):
			PDynamic;
		case TAnonymous(a):
			var a = a.get();
			var fields = [];
			for( f in a.fields ) {
				if( f.meta.has(":noSerialize") )
					continue;
				var ft = getPropField(f.type, f.meta.get());
				if( ft == null ) return null;
				fields.push( { name : f.name, type : ft, opt : f.meta.has(":optional") } );
			}
			PObj(fields);
		case TInst(c, pl):
			switch( c.toString() ) {
			case "String":
				PString;
			case "Array":
				var at = getPropType(pl[0]);
				if( at == null ) return null;
				PArray(at);
			case "haxe.ds.IntMap":
				var vt = getPropType(pl[0]);
				if( vt == null ) return null;
				PMap({ t : macro : Int, d : PInt }, vt);
			case "haxe.ds.StringMap":
				var vt = getPropType(pl[0]);
				if( vt == null ) return null;
				PMap({ t : macro : String, d : PString }, vt);
			case "haxe.io.Bytes":
				PBytes;
			case name if( StringTools.startsWith(name, "hxbit.ObjProxy_") ):
				var fields = c.get().fields.get();
				for( f in fields )
					if( f.name == "__value" ) {
						var t = getPropType(f.type);
						t.isProxy = true;
						return t;
					}
				throw "assert";
			default:
				if( isSerializable(c) )
					PSerializable(c.toString());
				else if( isStructSerializable(c) )
					PStruct;
				else
					return null;
			}
		case TType(td, pl):
			switch( td.toString() ) {
			case "Null":
				var p = getPropType(pl[0]);
				if( p != null && !isNullable(p) )
					p = { d : PNull(p), t : TPath( { pack : [], name : "Null", params : [TPType(p.t)] } ) };
				return p;
			default:
				var p = getPropType(Context.follow(t, true));
				if( p != null )
					p.t = t.toComplexType(); // more general, still identical
				return p;
			}
		default:
			return null;
		}
		var p : PropType = {
			d : desc,
			t : t.toComplexType(),
		};
		if( isProxy ) p.isProxy = isProxy;
		return p;
	}

	static function isNullable( t : PropType ) {
		switch( t.d ) {
		case PInt, PFloat, PBool, PFlags(_):
			return false;
		case PAlias(t):
			return isNullable(t);
		// case PInt64: -- might depend on the platform ?
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
			var vt = vt.t;
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

	static function unserializeExpr( ctx : Expr, v : Expr, t : PropType, depth : Int ) {
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
			var vt = t.t;
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
			var cexpr = Context.parse(loop(t.t).toString(), v.pos);
			return macro $v = $ctx.getRef($cexpr,@:privateAccess $cexpr.__clid);
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
				$v = new hxbit.EnumFlagsProxy(v);
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
		if( cl.isInterface )
			return null;
		var fields = Context.getBuildFields();
		var toSerialize = [];
		var addCustomSerializable = false;
		var addCustomUnserializable = false;

		var sup = cl.superClass;
		var isSubSer = sup != null && isSerializable(sup.t);
		var hasNonSerializableParent = sup != null && !isSerializable(sup.t);

		if( !Context.defined("display") )
		for( f in fields ) {
			if( f.name == "customSerialize" && ( f.access.indexOf(AOverride) < 0 || hasNonSerializableParent ) ) {
				addCustomSerializable = true;
			}
			if( f.name == "customUnserialize" && ( f.access.indexOf(AOverride) < 0 || hasNonSerializableParent ) ) {
				addCustomUnserializable = true;
			}
			if( f.meta == null ) continue;
			for( meta in f.meta )
				if( meta.name == ":s" ) {
					toSerialize.push({ f : f, m : meta });
					break;
				}
		}

		if( cl.meta.has(":serializeSuperClass") ) {
			if( toSerialize.length != 0 || !isSubSer )
				Context.error("Cannot use serializeSuperClass on this class", cl.pos);
			return null;
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
		var el = [], ul = [];
		for( f in toSerialize ) {
			var fname = f.f.name;
			el.push(withPos(macro hxbit.Macros.serializeValue(__ctx, this.$fname),f.f.pos));
			ul.push(withPos(macro hxbit.Macros.unserializeValue(__ctx, this.$fname),f.f.pos));
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
				kind : FVar(macro : Int, macro @:privateAccess hxbit.Serializer.allocUID()),
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
			fields.push({
				name : "serialize",
				pos : pos,
				access : access,
				kind : FFun({
					args : [ { name : "__ctx", type : macro : hxbit.Serializer } ],
					ret : null,
					expr : macro @:privateAccess {
						${ if( isSubSer ) macro super.serialize(__ctx) else macro { } };
						$b{el};
						${ if( addCustomSerializable ) macro this.customSerialize(__ctx) else macro { } };
					}
				}),
			});
			var schema = [for( s in toSerialize ) {
				var name = s.f.name;
				macro { schema.fieldsNames.push($v{name}); schema.fieldsTypes.push(hxbit.Macros.getFieldType(this.$name)); }
			}];
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
				${ if( isSubSer ) macro super.unserialize(__ctx) else macro { } };
				$b{ul}
				${ if( addCustomUnserializable ) macro this.customUnserialize(__ctx) else macro { } };
			};

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
					return fields;
				}

			fields.push({
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
			var name = e.pack.length == 0 ? e.name : e.pack.join("_") + "_" + e.name;
			try {
				return Context.getType("hxbit.enumSer." + name);
			} catch( _ : Dynamic ) {
				var pos = Context.currentPos();
				var cases = [], ucases = [], schemaExprs = [];
				if( e.names.length >= 256 )
					Context.error("Too many constructors", pos);
				for( f in e.names ) {
					var c = e.constructs.get(f);
					switch( Context.follow(c.type) ) {
					case TFun(args, _):
						var eargs = [for( a in args ) { var arg = { expr : EConst(CIdent(a.name)), pos : c.pos }; macro hxbit.Macros.serializeValue(ctx, $arg); }];
						cases.push({
							values : [{ expr : ECall({ expr : EConst(CIdent(c.name)), pos : pos },[for( a in args ) { expr : EConst(CIdent(a.name)), pos : pos }]), pos : pos }],
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
							etypes.push(macro { var v : $at; hxbit.Macros.getFieldType(v); });
						}
						evals.push({ expr : ECall({ expr : EConst(CIdent(c.name)), pos : pos },[for( a in args ) { expr : EConst(CIdent("_"+a.name)), pos : pos }]), pos : pos });
						ucases.push({
							values : [macro $v{c.index+1}],
							expr : { expr : EBlock(evals), pos : pos },
						});
						schemaExprs.push(macro s.fieldsTypes.push(PObj([for( t in [$b{etypes}] ) { name : "", type : t, opt : false }])));

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
					name : name,
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
								return ${{ expr : ESwitch(macro b,ucases,macro throw "Invalid enum index "+b), pos : pos }}
							},
							ret : pt.toComplexType(),
						}),

					},{
						name : "getSchema",
						access : [AStatic, APublic],
						meta : [{name:":keep",pos:pos}],
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
							expr : macro doSerialize(ctx,v),
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
				return Context.getType("hxbit.enumSer." + name);
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
	static function hasReturnVal( e : Expr ) {
		hasRetVal = false;
		checkRetVal(e);
		return hasRetVal;
	}

	static function checkRetVal( e : Expr ) {
		if( hasRetVal )
			return;
		switch( e.expr ) {
		case EReturn(e):
			if( e != null )
				hasRetVal = true;
		case EFunction(_):
			return;
		default:
			haxe.macro.ExprTools.iter(e, checkRetVal);
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

	public static function buildNetworkSerializable() {
		var cl = Context.getLocalClass().get();
		if( cl.isInterface )
			return null;
		var fields = Context.getBuildFields();
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

		if( !Context.defined("display") )
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
					toSerialize.push({ f : f, m : meta });
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
							Context.error("Unexpected Rpc mode : should be all|client|server|owner|immediate", meta.params[0].pos);
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
				@:noCompletion public var __bits : Int = 0;
				@:noCompletion public var __next : hxbit.NetworkSerializable;
				@:noCompletion public inline function networkSetBit( b : Int ) {
					if( __host != null && (__host.isAuth || @:privateAccess __host.checkWrite(this,b)) && (__next != null || @:privateAccess __host.mark(this)) )
						__bits |= 1 << b;
				}
				public var enableReplication(get, set) : Bool;
				inline function get_enableReplication() return __host != null;
				function set_enableReplication(b) {
					@:privateAccess hxbit.NetworkHost.enableReplication(this, b);
					return b;
				}
				public inline function networkCancelProperty( props : hxbit.NetworkSerializable.NetworkProperty ) {
					__bits &= ~props.toInt();
				}
				public inline function networkLocalChange( f : Void -> Void ) {
					var old = __host;
					__host = null;
					f();
					__host = old;
				}
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

		}

		var firstFID = startFID;
		var flushExpr = [];
		var syncExpr = [];
		var initExpr = [];
		var noComplete : Metadata = [ { name : ":noCompletion", pos : pos } ];
		for( f in toSerialize ) {
			var pos = f.f.pos;
			var fname = f.f.name;
			var bitID = startFID++;
			var ftype : PropType;
			switch( f.f.kind ) {
			case FVar(t, e):
				if( t == null ) t = quickInferType(e);
				if( t == null ) Context.error("Type required", pos);
				var tt = Context.resolveType(t, pos);
				ftype = getPropField(tt, f.f.meta);
				if( ftype == null ) ftype = { t : t, d : PUnknown };
				checkProxy(ftype);
				if( ftype.isProxy ) {
					switch( ftype.d ) {
					case PFlags(_) if( e == null ): e = macro new hxbit.EnumFlagsProxy(0);
					default:
					}
					if( e != null ) {
						initExpr.push(macro this.$fname = $e);
						e = null;
					}
				}
				f.f.kind = FProp("default", "set", ftype.t, e);
			case FProp(get, set, t, e):
				if( t == null ) t = quickInferType(e);
				if( t == null ) Context.error("Type required", pos);
				var tt = Context.resolveType(t, pos);
				ftype = getPropField(tt, f.f.meta);
				if( ftype == null ) ftype = { t : t, d : PUnknown };
				checkProxy(ftype);
				if( set == "null" )
					Context.warning("Null setter is not respected when using NetworkSerializable", pos);
				else if( set != "default" && set != "set" )
					Context.error("Invalid setter", pos);
				if( ftype.isProxy ) {
					switch( ftype.d ) {
					case PFlags(_) if( e == null ): e = macro new hxbit.EnumFlagsProxy(0);
					default:
					}
					if( e != null ) {
						initExpr.push(e);
						e = null;
					}
				}
				f.f.kind = FProp(get,"set", ftype.t, e);
			default:
				throw "assert";
			}

			var markExpr = macro networkSetBit($v{ bitID });
			markExpr = makeMarkExpr(fields, fname, ftype, markExpr);

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
						if( this.$fname != v ) {
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
						replaceSetter(f.f.name, function(e) return macro $i{markFun}($e),fun.expr);
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
			flushExpr.push(macro if( b & (1 << $v{ bitID } ) != 0 ) hxbit.Macros.serializeValue(ctx, $fexpr));
			syncExpr.push(macro if( __bits & (1 << $v { bitID } ) != 0 ) hxbit.Macros.unserializeValue(ctx, $fexpr));

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
					expr : macro return new hxbit.NetworkSerializable.NetworkProperty(1 << $v{bitID}),
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
				var hasReturnVal = hasReturnVal(f.expr);
				var name = r.f.name;
				var p = r.f.pos;
				r.f.name += "__impl";

				var cargs = [for( a in f.args ) { expr : EConst(CIdent(a.name)), pos : p } ];
				var fcall = { expr : ECall( { expr : EField( { expr : EConst(CIdent("this")), pos:p }, r.f.name), pos : p }, cargs), pos : p };

				var doCall = fcall;
				var rpcArgs = f.args;
				var resultCall = macro null;

				if( hasReturnVal ) {
					doCall = macro onResult($fcall);
					resultCall = withPos(macro function(__ctx:hxbit.NetworkSerializable.NetworkSerializer) {
						var v = cast null;
						if( false ) v = $fcall;
						hxbit.Macros.unserializeValue(__ctx, v);
						if( __ctx.error ) return false;
						onResult(v);
						return true;
					},f.expr.pos);
					rpcArgs = rpcArgs.copy();
					rpcArgs.push( { name : "onResult", type: f.ret == null ? null : TFunction([f.ret], macro:Void) } );
				}

				var forwardRPC = macro {
					var __ctx = @:privateAccess __host.beginRPC(this,$v{id},$resultCall);
					$b{[
						for( a in f.args )
							withPos(macro hxbit.Macros.serializeValue(__ctx, $i{a.name}), f.expr.pos)
					] };
					@:privateAccess __host.endRPC();
				};

				if( hasReturnVal && r.mode != Server )
					Context.error("Cannot use return value with default rpc mode, use @:rpc(server)", r.f.pos);

				var rpcExpr = switch( r.mode ) {
				case All:
					macro {
						if( __host != null ) {
							if( !__host.isAuth && !networkAllow(RPC, $v{id}, __host.self.ownerObject) ) {
								__host.logError("Calling RPC on an not allowed object");
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
								__host.logError("Calling RPC on an not allowed object");
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
							if( !networkAllow(RPC, $v{id}, __host.self.ownerObject) ) {
								__host.logError("Calling RPC on a not allowed object");
								return;
							}
							// might ping-pong, but need to preserve order
							$forwardRPC;
						}
					}
				case Immediate:
					macro {
						if( __host != null ) {
							if( !__host.isAuth && !networkAllow(RPC, $v{id}, __host.self.ownerObject) ) {
								__host.logError("Calling RPC on an not allowed object");
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

				var exprs = [ { expr : EVars([for( a in f.args ) { name : a.name, type : a.opt ? TPath({ pack : [], name : "Null", params : [TPType(a.type)] }) : a.type, expr : macro cast null } ]), pos : p } ];
				exprs.push(macro if( false ) $fcall); // force typing
				for( a in f.args ) {
					var e = macro hxbit.Macros.unserializeValue(__ctx, $i{ a.name });
					e.pos = p;
					exprs.push(e);
				}
				exprs.push(macro if( __ctx.error ) return false);
				if( hasReturnVal ) {
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
							if( __host != null ) {
								// should only be called by server
								__host.logError("assert");
								return false;
							}
							$fcall;
						});
					case Server:
						exprs.push(macro {
							if( __host == null || !__host.isAuth ) throw "assert";
							if( !networkAllow(RPCServer, $v{id}, __host.rpcClient.ownerObject) )
								return false;
							$fcall;
						});
					case Immediate:
						exprs.push(macro {
							if( __host != null && __host.isAuth ) {
								// check again
								if( !networkAllow(RPC,$v{id},__host.rpcClient.ownerObject) )
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
				flushExpr.unshift(macro ctx.addInt(__bits));
				flushExpr.push(macro __bits = 0);
			}
			flushExpr.unshift(macro var b = __bits);
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

		if( startFID > 32 ) Context.error("Too many serializable fields", pos);
		if( rpcID > 255 ) Context.error("Too many rpc calls", pos);

		if( rpc.length > 0 )
			cl.meta.add(":rpcCalls", [for( r in rpc ) { expr : EConst(CIdent(r.f.name.substr(0, -6))), pos : pos } ], pos);
		if( toSerialize.length > 0 )
			cl.meta.add(":sFields", [for( r in toSerialize ) { expr : EConst(CIdent(r.f.name)), pos : pos }], pos);

		return fields;
	}

	static function makeMarkExpr( fields : Array<Field>, fname : String, t : PropType, mark : Expr ) {
		var rname = "__ref_" + fname;
		var needRef = false;
		if( t.increment != null ) {
			needRef = true;
			mark = macro if( Math.floor(this.$fname / $v{t.increment}) != this.$rname ) { this.$rname = Math.floor(this.$fname / $v{t.increment}); $mark; };
		}
		if( t.condSend != null ) {
			function loop(e:Expr) {
				switch( e.expr ) {
				case EConst(CIdent("current")):
					return { expr : EConst(CIdent(rname)), pos : e.pos };
				default:
					return haxe.macro.ExprTools.map(e, loop);
				}
			}
			if( t.condSend.expr.match(EConst(CIdent("false"))) )
				return macro {}; // no marking
			var condSend = loop(t.condSend);
			needRef = true;
			mark = macro if( $condSend ) { this.$rname = this.$fname; $mark; };
		}
		if( needRef && fields != null )
			fields.push({
				name : rname,
				pos : mark.pos,
				meta : [{ name : ":noCompletion", pos : mark.pos }],
				kind : FVar(t.t,macro 0),
			});
		return mark;
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
			var subName = k.isProxy ? "MapProxy2" : "MapProxy";
			return TPath( { pack : ["hxbit"], name : "MapProxy", sub : subName, params : [TPType(k.t),TPType(v.t)] } );
		case PObj(fields):
			// define type
			var name = "ObjProxy_";
			fields.sort(function(f1, f2) return Reflect.compare(f1.name, f2.name));
			inline function typeName(t:PropType) {
				var str = t.t.toString();
				str = str.split("<StdTypes.").join("<");
				if( StringTools.startsWith(str, "StdTypes.") )
					str = str.substr(9);
				return str;
			}
			name += [for( f in fields ) f.name+"_" + ~/[<>.]/g.replace(typeName(f.type),"_")].join("_");
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

					tfields.push( {
						name : "set_" + f.name,
						pos : pos,
						access : [AInline],
						kind : FFun({
							ret : ft,
							args : [ { name : "v", type : ft } ],
							expr : macro { this.$fname = v; $markExpr; return v; }
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
			var p = getPropType(pt);
			if( p != null ) {
				var t = buildProxyType(p);
				if( t != null ) return toType(t);
			}
			throw "TODO "+pt+" ("+p+")";
		default:
			throw "assert";
		}
	}

	#end

}
